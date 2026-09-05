#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PANEL="$ROOT/Panel.qml"

assert_contains() {
  local needle="$1"
  grep -Fq -- "$needle" "$PANEL" || {
    printf 'FAIL: missing %q in %s\n' "$needle" "$PANEL" >&2
    exit 1
  }
}

assert_contains 'function leadingIconGlyph(text)' 
assert_contains 'var first = s.charCodeAt(0)'
assert_contains 'return codePoint >= 0xF0000 && codePoint <= 0x10FFFD ? s.substring(0, 2) : ""'
assert_contains 'var live = root.leadingIconGlyph(root.liveGlyphFor(id))'

printf 'icon-glyph-test: ok\n'
