#!/bin/bash
# Detached update runner for omaplug.
#
# The Omarchy shell hot-reloads plugins whenever a checkout changes. Running
# updates from a tracked QML Process therefore destroys the process owner after
# the first merge. Quickshell launches this helper detached, and it records
# progress outside the watched plugin directory so a reloaded panel can
# reconnect.
#
# Usage: update-helper.sh <status-file> <job-id> <plugin-id> [plugin-id ...]

set -uo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ ${1:-} != --run ]]; then
  exec python3 "$SCRIPT_DIR/runtime-state.py" update "$@"
fi
shift
JOB_ID="${1:-}"
[[ $JOB_ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 2
shift
(( $# > 0 )) || exit 2

PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"

write_status() {
  printf '%s\n' "$1"
}

one_line() {
  local text="$1"
  local last
  last=$(printf '%s\n' "$text" | awk 'NF { line=$0 } END { print line }')
  last=${last//$'\t'/ }
  last=${last//$'\r'/ }
  printf '%.300s' "$last"
}

preflight_error() {
  local id="$1"
  local dir="$PLUGINS_DIR/$id"
  local changes

  if [[ -L $dir ]]; then
    printf 'plugin became a symlink after the update check'
  elif [[ ! -d $dir/.git ]]; then
    printf 'plugin is no longer a direct git checkout'
  elif ! git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'plugin has no commit to update'
  elif ! git -C "$dir" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
    printf 'plugin is on a detached HEAD'
  elif ! changes=$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null); then
    printf 'could not inspect plugin changes'
  elif [[ -n $changes ]]; then
    printf 'plugin gained local changes after the update check'
  else
    return 1
  fi
}

write_status $'version\t1'
write_status $'job\t'"$JOB_ID"
write_status $'pid\t'"$$"
write_status $'started\t'"$(date +%s)"
write_status $'total\t'"$#"

updated=0
failed=0

for id in "$@"; do
  if [[ ! $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || $id == *..* ]]; then
    write_status $'failed\t'"$(one_line "$id")"$'\tinvalid plugin id'
    failed=$((failed + 1))
    continue
  fi

  if safety_error=$(preflight_error "$id"); then
    write_status $'failed\t'"$id"$'\t'"$safety_error"
    failed=$((failed + 1))
    continue
  fi

  write_status $'start\t'"$id"
  out=$(timeout -k 2 120 omarchy plugin update "$id" --yes 2>&1 | { head -c 8000; cat >/dev/null; }; exit "${PIPESTATUS[0]}")
  rc=$?
  detail=$(one_line "$out")

  if (( rc == 0 )); then
    write_status $'ok\t'"$id"$'\t'"$detail"
    updated=$((updated + 1))
  else
    write_status $'failed\t'"$id"$'\t'"$detail"
    failed=$((failed + 1))
  fi
done

write_status $'finished\t'"$(date +%s)"
write_status $'done\t'"$updated"$'\t'"$failed"
(( failed == 0 ))
