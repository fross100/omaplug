#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'quickshell-detached-test: skipped (quickshell not installed)\n'
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

BIN="$TMP/bin"
TEST_HOME="$TMP/home"
PLUGINS="$TEST_HOME/.config/omarchy/plugins"
STATUS="$TMP/update.status"
mkdir -p -- "$BIN" "$PLUGINS"

for id in slow good; do
  dir="$PLUGINS/$id"
  git init -q -b main "$dir"
  git -C "$dir" config user.name "Omaplug Tests"
  git -C "$dir" config user.email "omaplug-tests@example.invalid"
  printf '{"id":"%s"}\n' "$id" > "$dir/manifest.json"
  git -C "$dir" add manifest.json
  git -C "$dir" commit -qm "fixture"
done

cat > "$BIN/omarchy" <<'EOF'
#!/bin/bash
[[ ${3:-} == slow ]] && sleep 0.4
printf 'updated %s\n' "${3:-}"
EOF
chmod +x "$BIN/omarchy"

PATH="$BIN:$PATH" \
HOME="$TEST_HOME" \
OMAPLUG_TEST_HELPER="$ROOT/update-helper.sh" \
OMAPLUG_TEST_STATUS="$STATUS" \
QT_QPA_PLATFORM=offscreen \
  quickshell --no-color -p "$ROOT/tests/DetachedLaunch.qml" >/dev/null 2>&1

for _ in {1..200}; do
  grep -Fqx $'done\t2\t0' "$STATUS" 2>/dev/null && break
  sleep 0.01
done

grep -Fqx $'job\tjob-quickshell' "$STATUS"
grep -Fqx $'done\t2\t0' "$STATUS"
printf 'quickshell-detached-test: ok\n'
