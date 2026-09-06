#!/bin/bash

# Coordinates plugin-state.sh across the bar's per-monitor instances. The
# omaplug widget exists once per monitor, each running its own independent
# Panel.qml and its own background auto-check Timer, so an unattended tick
# firing at (roughly) the same moment on every monitor would otherwise run
# N fully redundant git-fetch passes over every installed plugin. This wraps
# plugin-state.sh with a lock + shared cache so only one instance's tick
# does the real work; the others reuse its output.
#
# The manual "Check for updates" button in the panel bypasses this entirely
# and always calls plugin-state.sh directly - only the unattended Timer path
# (Panel.qml's autoUpdateCheckTimer) uses this wrapper.
#
# Usage: auto-check-coordinator.sh <plugins-dir>
# Output: identical CHECK/state line format to plugin-state.sh.

set -uo pipefail

PLUGINS_DIR="${1:?usage: auto-check-coordinator.sh <plugins-dir>}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

STATE_ROOT="${XDG_RUNTIME_DIR:-$HOME/.cache}/omaplug"
mkdir -p -- "$STATE_ROOT"
LOCK="$STATE_ROOT/auto-check.lock"
CACHE="$STATE_ROOT/auto-check.cache"

# Same stale-lock recovery as update-helper.sh's acquire_lock(): Panel.qml's
# checkWatchdog kills a check that runs past 45s with SIGKILL, which cannot
# be trapped, so a lock left behind by a killed instance must not wedge
# every future auto-check across every monitor forever.
acquire_lock() {
  if mkdir -- "$LOCK" 2>/dev/null; then
    return 0
  fi

  local old_pid=""
  [[ -r $LOCK/pid ]] && read -r old_pid < "$LOCK/pid"
  if [[ $old_pid =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    return 1
  fi

  rm -rf -- "$LOCK"
  mkdir -- "$LOCK" 2>/dev/null
}

if acquire_lock; then
  printf '%s\n' "$$" > "$LOCK/pid"
  trap 'rm -rf -- "$LOCK"' EXIT
  "$SCRIPT_DIR/plugin-state.sh" "$PLUGINS_DIR" | tee -- "$CACHE.tmp"
  rc=${PIPESTATUS[0]}
  mv -f -- "$CACHE.tmp" "$CACHE"
  exit "$rc"
fi

# Another instance already holds the lock and is running the real check.
# Wait for it, bounded well under Panel.qml's 45s checkWatchdog so this
# process always exits with *something* rather than getting SIGKILLed
# mid-wait and leaving that monitor's badge stuck on "checking" forever.
for _ in $(seq 1 35); do
  [[ -d $LOCK ]] || break
  sleep 1
done

cat -- "$CACHE" 2>/dev/null
exit 0
