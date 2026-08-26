#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"
LOG="$TMP/calls.log"
STATUS="$TMP/update.status"
TEST_HOME="$TMP/home"
PLUGINS="$TEST_HOME/.config/omarchy/plugins"
mkdir -p -- "$BIN" "$PLUGINS"

make_plugin() {
  local id="$1"
  local dir="$PLUGINS/$id"
  git init -q -b main "$dir"
  git -C "$dir" config user.name "Omaplug Tests"
  git -C "$dir" config user.email "omaplug-tests@example.invalid"
  printf '{"id":"%s"}\n' "$id" > "$dir/manifest.json"
  git -C "$dir" add manifest.json
  git -C "$dir" commit -qm "fixture"
}

for id in good fail slow dirty detached; do make_plugin "$id"; done
printf '\n' >> "$PLUGINS/dirty/manifest.json"
git -C "$PLUGINS/detached" checkout -q --detach
ln -s -- "$PLUGINS/good" "$PLUGINS/linked"

cat > "$BIN/omarchy" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$OMAPLUG_TEST_LOG"
case "${3:-}" in
  slow) sleep 0.4 ;;
esac
if [[ ${3:-} == fail ]]; then
  printf 'could not update %s\n' "$3" >&2
  exit 7
fi
printf 'updated %s\n' "${3:-}"
EOF
chmod +x "$BIN/omarchy"

export PATH="$BIN:$PATH"
export OMAPLUG_TEST_LOG="$LOG"
export HOME="$TEST_HOME"

# A prior run may have left a status file created under a permissive umask.
# The helper must tighten it before writing any job details.
: > "$STATUS"
chmod 0644 "$STATUS"

assert_line() {
  local line="$1"
  local file="$2"
  grep -Fqx -- "$line" "$file" || {
    printf 'FAIL: missing line %q in %s\n' "$line" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

if "$ROOT/update-helper.sh" "$STATUS" job-direct good fail dirty detached linked 'bad/id'; then
  printf 'FAIL: a partially failed update job returned success\n' >&2
  exit 1
fi

assert_line $'job\tjob-direct' "$STATUS"
assert_line $'start\tgood' "$STATUS"
assert_line $'ok\tgood\tupdated good' "$STATUS"
assert_line $'start\tfail' "$STATUS"
assert_line $'failed\tfail\tcould not update fail' "$STATUS"
assert_line $'failed\tdirty\tplugin gained local changes after the update check' "$STATUS"
assert_line $'failed\tdetached\tplugin is on a detached HEAD' "$STATUS"
assert_line $'failed\tlinked\tplugin became a symlink after the update check' "$STATUS"
assert_line $'failed\tbad/id\tinvalid plugin id' "$STATUS"
assert_line $'done\t1\t5' "$STATUS"
[[ $(stat -c '%a' "$STATUS") == 600 ]] || {
  printf 'FAIL: status file mode is %s instead of 600\n' "$(stat -c '%a' "$STATUS")" >&2
  exit 1
}
[[ $(tail -n 1 "$STATUS") == $'done\t1\t5' ]] || {
  printf 'FAIL: done is not the final status record\n' >&2
  cat "$STATUS" >&2
  exit 1
}
assert_line 'plugin update good --yes' "$LOG"
assert_line 'plugin update fail --yes' "$LOG"
[[ $(wc -l < "$LOG") -eq 2 ]] || {
  printf 'FAIL: invalid plugin id reached omarchy\n' >&2
  cat "$LOG" >&2
  exit 1
}

# A live runner owns the stable status path. A second runner must fail without
# replacing or appending to that job's status stream.
: > "$LOG"
"$ROOT/update-helper.sh" "$STATUS" job-first slow &
first_pid=$!
for _ in {1..100}; do
  [[ -d $STATUS.lock ]] && break
  sleep 0.01
done
if "$ROOT/update-helper.sh" "$STATUS" job-second good; then
  printf 'FAIL: a concurrent update runner acquired the same lock\n' >&2
  exit 1
else
  second_rc=$?
fi
[[ $second_rc -eq 3 ]] || {
  printf 'FAIL: concurrent runner returned %s instead of 3\n' "$second_rc" >&2
  exit 1
}
wait "$first_pid"
assert_line $'job\tjob-first' "$STATUS"
if grep -Fq $'job\tjob-second' "$STATUS"; then
  printf 'FAIL: concurrent runner clobbered the active status\n' >&2
  exit 1
fi

printf 'update-helper-test: ok\n'
