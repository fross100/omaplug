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

printf 'auto-check-test: ok\n'
