#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"
LOG="$TMP/calls.log"
STDIN_COPY="$TMP/stdin.txt"
TEST_HOME="$TMP/home"
REPO="$TMP/repo"
mkdir -p -- "$BIN" "$TEST_HOME" "$REPO"

# A fixture repository with the shapes the bundler has to handle: two text
# files, a binary, and one over the per-file cap.
git init -q -b main "$REPO"
git -C "$REPO" config user.name "Omaplug Tests"
git -C "$REPO" config user.email "omaplug-tests@example.invalid"
printf '{"id":"fixture","name":"Fixture"}\n' > "$REPO/manifest.json"
printf 'import QtQuick\nItem { Component.onCompleted: console.log("MARKER_QML") }\n' > "$REPO/Widget.qml"
printf '\x89PNG\r\n\x1a\n\x00\x00BINARY' > "$REPO/preview.png"
head -c $((300 * 1024)) /dev/zero | tr '\0' 'x' > "$REPO/huge.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"
SHA=$(git -C "$REPO" rev-parse HEAD)

# The claude stub records its arguments and stdin, then answers like the real
# CLI's --output-format json does. OMAPLUG_TEST_MODE picks the shape.
cat > "$BIN/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$OMAPLUG_TEST_LOG"
cat > "$OMAPLUG_TEST_STDIN"
case "${OMAPLUG_TEST_MODE:-ok}" in
  ok)
    printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.42,"duration_ms":1234,"result":"{}","structured_output":{"verdict":"caution","summary":"Fixture summary.","capabilities":["logs to console"],"findings":[{"severity":"low","title":"Console logging","file":"Widget.qml","detail":"Logs a marker at startup."}],"prompt_injection_detected":false}}\n'
    ;;
  result-only)
    printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.1,"duration_ms":5,"result":"{\\"verdict\\":\\"safe\\",\\"summary\\":\\"From result.\\",\\"capabilities\\":[],\\"findings\\":[],\\"prompt_injection_detected\\":false}"}\n'
    ;;
  error)
    printf '{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}\n'
    exit 1
    ;;
  garbage)
    printf 'not json at all\n'
    exit 3
    ;;
esac
STUB
chmod +x "$BIN/claude"

export PATH="$BIN:/usr/bin"
export HOME="$TEST_HOME"
export OMAPLUG_TEST_LOG="$LOG"
export OMAPLUG_TEST_STDIN="$STDIN_COPY"

assert_line() {
  local line="$1"
  local file="$2"
  grep -Fqx -- "$line" "$file" || {
    printf 'FAIL: missing line %q in %s\n' "$line" "$file" >&2
    cat "$file" >&2
    exit 1
  }
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'FAIL: %s does not contain %q\n' "$file" "$needle" >&2
    exit 1
  }
}

# ------------------------------------------------------------ happy path

OUT="$TMP/out.ok"
WORK="$TMP/work-ok"
OMAPLUG_TEST_MODE=ok "$ROOT/review-helper.sh" "$REPO" "$WORK" > "$OUT"
assert_line $'stage\tclone' "$OUT"
assert_line "commit	$SHA" "$OUT"
assert_line $'stage\tbundle' "$OUT"
assert_line $'stage\treview' "$OUT"
# manifest.json + Widget.qml; the png is binary and huge.txt is over the cap.
grep -q $'^files\t2\t[0-9]*\t1$' "$OUT" || { printf 'FAIL: files line wrong\n' >&2; cat "$OUT" >&2; exit 1; }

review=$(grep $'^review\t' "$OUT" | cut -f2-)
[[ -n $review ]] || { printf 'FAIL: no review line\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r .verdict) == caution ]] || { printf 'FAIL: verdict\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r .commit) == "$SHA" ]] || { printf 'FAIL: commit not attached\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r .model) == claude-fable-5-1 ]] || { printf 'FAIL: default model\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r .cost_usd) == 0.42 ]] || { printf 'FAIL: cost not attached\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r .truncated) == true ]] || { printf 'FAIL: truncated flag\n' >&2; exit 1; }
[[ $(printf '%s' "$review" | jq -r '.findings | length') == 1 ]] || { printf 'FAIL: findings\n' >&2; exit 1; }
[[ -s "$WORK/review.json" ]] || { printf 'FAIL: review.json not written\n' >&2; exit 1; }

# The reviewer got the source, the skip list, and the default flags.
assert_contains "MARKER_QML" "$STDIN_COPY"
assert_contains "BEGIN FILE Widget.qml" "$STDIN_COPY"
assert_contains "huge.txt" "$STDIN_COPY"
assert_contains "preview.png (binary)" "$STDIN_COPY"
grep -q 'BEGIN FILE preview.png' "$STDIN_COPY" && { printf 'FAIL: binary was bundled\n' >&2; exit 1; }
assert_contains "--tools  --disable-slash-commands" "$LOG"
assert_contains "--model claude-fable-5-1" "$LOG"
assert_contains "--json-schema" "$LOG"
assert_contains "--no-session-persistence" "$LOG"
grep -q -- '--bare' "$LOG" && { printf 'FAIL: --bare skips credentials and must not be used\n' >&2; exit 1; }

# The delimiter nonce is per run, so a file cannot forge a boundary.
nonce=$(grep -o 'token [0-9a-f]\{24\}' "$STDIN_COPY" | head -n 1 | cut -d' ' -f2)
[[ -n $nonce ]] || { printf 'FAIL: no nonce in prompt\n' >&2; exit 1; }
assert_contains "===== $nonce BEGIN FILE manifest.json" "$STDIN_COPY"

# ------------------------------------------------------------ env overrides

OUT2="$TMP/out.model"
OMAPLUG_TEST_MODE=result-only OMAPLUG_REVIEW_MODEL=claude-opus-5 OMAPLUG_REVIEW_EFFORT=low \
  "$ROOT/review-helper.sh" "$REPO" "$TMP/work-model" > "$OUT2"
assert_contains "--model claude-opus-5 --effort low" "$LOG"
review2=$(grep $'^review\t' "$OUT2" | cut -f2-)
[[ $(printf '%s' "$review2" | jq -r .verdict) == safe ]] || { printf 'FAIL: result-only fallback\n' >&2; exit 1; }
[[ $(printf '%s' "$review2" | jq -r .model) == claude-opus-5 ]] || { printf 'FAIL: model override\n' >&2; exit 1; }

# ------------------------------------------------------------ failures

OUT3="$TMP/out.err"
if OMAPLUG_TEST_MODE=error "$ROOT/review-helper.sh" "$REPO" "$TMP/work-err" > "$OUT3"; then
  printf 'FAIL: claude error should fail the helper\n' >&2; exit 1
fi
assert_contains $'error\tclaude: Not logged in' "$OUT3"
grep -q $'^review\t' "$OUT3" && { printf 'FAIL: review line on error\n' >&2; exit 1; }

OUT4="$TMP/out.garbage"
if OMAPLUG_TEST_MODE=garbage "$ROOT/review-helper.sh" "$REPO" "$TMP/work-garbage" > "$OUT4"; then
  printf 'FAIL: garbage output should fail the helper\n' >&2; exit 1
fi
assert_contains $'error\tclaude produced no JSON (exit 3)' "$OUT4"

OUT5="$TMP/out.noclone"
if "$ROOT/review-helper.sh" "$TMP/does-not-exist" "$TMP/work-noclone" > "$OUT5"; then
  printf 'FAIL: bad URL should fail the helper\n' >&2; exit 1
fi
assert_contains $'error\tclone failed' "$OUT5"

OUT6="$TMP/out.noclaude"
if PATH=/usr/bin "$ROOT/review-helper.sh" "$REPO" "$TMP/work-noclaude" > "$OUT6"; then
  printf 'FAIL: missing claude should fail the helper\n' >&2; exit 1
fi
assert_contains $'error\tclaude CLI not found' "$OUT6"

printf 'review-helper-test: ok\n'
