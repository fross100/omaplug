#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/nested-widget-toggle.sh"

TASK_DIR=$(mktemp -d)
trap 'rm -rf -- "$TASK_DIR"' EXIT
export CALL_LOG="$TASK_DIR/calls"
export CONFIG BAR_FAIL=0

# Executable stubs also intercept the helper's final exec command.
omarchy-shell() {
  [[ $* == 'shell listShellConfig' ]] || return 90
  printf '%s\n' "$CONFIG"
}
omarchy() {
  jq -cn --args '$ARGS.positional' -- "$@" >> "$CALL_LOG"
  if [[ ${1:-} == bar && $BAR_FAIL == 1 ]]; then return 42; fi
}
mkdir "$TASK_DIR/bin"
printf '#!/bin/bash\n%s\nomarchy-shell "$@"\n' "$(declare -f omarchy-shell)" > "$TASK_DIR/bin/omarchy-shell"
printf '#!/bin/bash\n%s\nomarchy "$@"\n' "$(declare -f omarchy)" > "$TASK_DIR/bin/omarchy"
chmod +x "$TASK_DIR/bin/omarchy-shell" "$TASK_DIR/bin/omarchy"
export PATH="$TASK_DIR/bin:$PATH"

failures=0
check() {
  local label=$1
  shift
  if ! "$@" > /dev/null; then
    printf 'FAIL: %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}
run_helper() {
  : > "$CALL_LOG"
  result=0
  bash "$HELPER" "$@" > "$TASK_DIR/stdout" 2> "$TASK_DIR/stderr" || result=$?
}

CONFIG='{"bar":{"layout":{"left":[{"id":"host","widgets":["before","child","after","child"]}],"right":[{"id":"other","widgets":["untouched"]}]}}}'
run_helper child disable
check 'nested disable succeeds' test "$result" -eq 0
check 'remove only requested child before disabling it' jq -se '
  . == [["bar","set","host","widgets","[\"before\",\"after\"]","--json"],
        ["plugin","disable","child"]]
' "$CALL_LOG"

CONFIG='{"bar":{"layout":{"left":[{"id":"host","widgets":["other"]}]}}}'
run_helper standalone disable
check 'non-nested disable succeeds' test "$result" -eq 0
check 'non-nested disable does not modify hosts' jq -se '. == [["plugin","disable","standalone"]]' "$CALL_LOG"

CONFIG='{not valid json'
run_helper child disable
check 'invalid JSON fails' test "$result" -ne 0
check 'invalid JSON never disables a plugin' test ! -s "$CALL_LOG"

CONFIG='{"bar":{"layout":42}}'
run_helper child disable
check 'invalid layout fails' test "$result" -ne 0
check 'jq failure never disables a plugin' test ! -s "$CALL_LOG"

CONFIG='{"bar":{"layout":{"left":[{"id":"host","widgets":["child","other"]}]}}}'
BAR_FAIL=1
run_helper child disable
check 'host update error propagates' test "$result" -eq 42
check 'failed host update prevents plugin disable' jq -se '
  . == [["bar","set","host","widgets","[\"other\"]","--json"]]
' "$CALL_LOG"

(( failures == 0 )) || exit 1

printf 'nested-widget-toggle-test: ok\n'
