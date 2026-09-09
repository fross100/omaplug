#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'auto-check-test: skipped (quickshell not installed)\n'
  exit 0
fi

run() {
  QT_QPA_PLATFORM=offscreen \
  OMAPLUG_TEST_SETTINGS="${1:-{\}}" \
  OMAPLUG_TEST_UPDATE_STATES="${2:-{\}}" \
  OMAPLUG_TEST_PLUGIN_REPOS="${3:-{\}}" \
  OMAPLUG_TEST_TOGGLE_AFTER_MS="${4:-0}" \
  OMAPLUG_TEST_TOGGLE_TO="${5:-false}" \
    quickshell --no-color -p "$ROOT/tests/AutoCheckLogic.qml" 2>&1
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  if [[ $haystack != *"$needle"* ]]; then
    printf 'FAIL: %s: expected output to contain %q\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  if [[ $haystack == *"$needle"* ]]; then
    printf 'FAIL: %s: expected output to NOT contain %q\n' "$label" "$needle" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

# True if a TIMER_FIRED line appears strictly after the first line matching
# marker, i.e. after the point in the run's timeline where the setting changed.
found_fire_after() {
  local marker="$1"
  local haystack="$2"
  awk -v m="$marker" '
    $0 ~ m { seen=1; next }
    seen && /TIMER_FIRED/ { found=1 }
    END { exit !found }
  ' <<<"$haystack"
}

assert_no_fire_after() {
  local marker="$1" haystack="$2" label="$3"
  if found_fire_after "$marker" "$haystack"; then
    printf 'FAIL: %s: TIMER_FIRED appeared after %q\n' "$label" "$marker" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_fire_after() {
  local marker="$1" haystack="$2" label="$3"
  if ! found_fire_after "$marker" "$haystack"; then
    printf 'FAIL: %s: expected TIMER_FIRED after %q but none seen\n' "$label" "$marker" >&2
    printf '%s\n' "$haystack" >&2
    exit 1
  fi
}

# Pulls the text between "<marker>-BEGIN" and "<marker>-END" comment lines.
extract_block() {
  local file="$1" marker="$2"
  awk -v b="${marker}-BEGIN" -v e="${marker}-END" '
    $0 ~ b { flag=1; next }
    $0 ~ e { flag=0 }
    flag
  ' "$file"
}

# Panel.qml only loads inside the full Omarchy shell, so AutoCheckLogic.qml
# duplicates its auto-check expressions to test them standalone (see the
# header comment in each file). A copy that's never re-checked against the
# original is worse than no test: it would keep passing while the real
# Panel.qml logic silently drifts. This fails loudly the moment they disagree.
assert_blocks_match() {
  local marker="$1" label="$2"
  local a b
  a=$(extract_block "$ROOT/Panel.qml" "$marker")
  b=$(extract_block "$ROOT/tests/AutoCheckLogic.qml" "$marker")
  if [[ -z $a || -z $b ]]; then
    printf 'FAIL: %s: marker %q missing from Panel.qml or AutoCheckLogic.qml\n' "$label" "$marker" >&2
    exit 1
  fi
  if [[ $a != "$b" ]]; then
    printf 'FAIL: %s: Panel.qml and tests/AutoCheckLogic.qml have drifted apart\n' "$label" >&2
    diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") >&2 || true
    exit 1
  fi
}

assert_blocks_match AUTOCHECK-SETTINGS auto-check-settings-in-sync
assert_blocks_match PENDING-UPDATE-COUNT pending-update-count-in-sync

# The sync guard above only proves the settings math agrees; it says nothing
# about what the real Timer's onTriggered calls. Pin that down directly so a
# future edit can't quietly swap in a new/duplicate check function instead of
# the one the manual "Check for updates" button already uses.
grep -Fq 'onTriggered: root.checkUpdates(root.autoCheckCoordinatorPath)' "$ROOT/Panel.qml" || {
  printf 'FAIL: Panel.qml autoUpdateCheckTimer is not wired to the existing checkUpdates()\n' >&2
  exit 1
}

# Defaults: enabled, 6h interval, fires on start.
OUT=$(run '{}')
assert_contains 'RESOLVED_ENABLED true' "$OUT" default-enabled
assert_contains 'RESOLVED_HOURS 6' "$OUT" default-hours
assert_contains 'TIMER_FIRED' "$OUT" default-fires

# Explicitly disabled: never fires, even once, within the test window.
OUT=$(run '{"autoCheckUpdates":false}')
assert_contains 'RESOLVED_ENABLED false' "$OUT" disabled-flag
assert_not_contains 'TIMER_FIRED' "$OUT" disabled-does-not-fire

# Custom interval passes through unchanged.
OUT=$(run '{"autoCheckIntervalHours":3}')
assert_contains 'RESOLVED_HOURS 3' "$OUT" custom-hours

# A fractional value must survive as-is, not truncate to 0 (which an `int`
# property would silently do, turning into a zero-interval, tight-looping
# Timer - not reachable through the shipped 1/3/6/12/24h picker, but settings
# are hand-editable in shell.json).
OUT=$(run '{"autoCheckIntervalHours":0.5}')
assert_contains 'RESOLVED_HOURS 0.5' "$OUT" fractional-hours-not-truncated

# Zero, negative, and non-numeric intervals all fall back to 6h rather than
# producing a zero/negative-interval Timer (which would fire in a tight loop).
OUT=$(run '{"autoCheckIntervalHours":0}')
assert_contains 'RESOLVED_HOURS 6' "$OUT" zero-hours-fallback

OUT=$(run '{"autoCheckIntervalHours":-2}')
assert_contains 'RESOLVED_HOURS 6' "$OUT" negative-hours-fallback

OUT=$(run '{"autoCheckIntervalHours":"banana"}')
assert_contains 'RESOLVED_HOURS 6' "$OUT" non-numeric-hours-fallback

# pendingUpdateCount only counts UPDATE states for keys plugin-state.sh also
# reported a repo URL for (mirrors the real property's join against
# pluginRepos, which is what keeps a stale/removed plugin out of the count).
OUT=$(run '{}' '{"a":"UPDATE","b":"CURRENT","c":"UPDATE","d":"UPDATE"}' '{"a":"url","b":"url","d":"url"}')
assert_contains 'RESOLVED_PENDING 2' "$OUT" pending-count-filters-unknown-repo

# Live toggle off: this is what happens when the user flips the panel's
# switch off while the shell keeps running - no restart, so the same process
# must stop firing right away. A sub-second interval (0.0001h) guarantees a
# refire would land inside the test window if disabling didn't take effect.
OUT=$(run '{"autoCheckIntervalHours":0.0001}' '{}' '{}' 500 false)
assert_contains 'TOGGLED_ENABLED false' "$OUT" live-disable-toggled
assert_no_fire_after 'TOGGLED_ENABLED false' "$OUT" live-disable-stops-firing

# Live toggle on: starts disabled (proven quiet up to the toggle line), then
# flips on mid-run - the resumed Timer's triggeredOnStart must fire again
# immediately rather than waiting for the next shell restart.
OUT=$(run '{"autoCheckUpdates":false}' '{}' '{}' 300 true)
assert_not_contains 'TIMER_FIRED' "${OUT%%TOGGLED_ENABLED*}" live-enable-quiet-before-toggle
assert_contains 'TOGGLED_ENABLED true' "$OUT" live-enable-toggled
assert_fire_after 'TOGGLED_ENABLED true' "$OUT" live-enable-resumes-firing

printf 'auto-check-test: ok\n'
