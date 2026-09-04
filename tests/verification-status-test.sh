#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PAGE="$ROOT/panel/updates/Page.qml"
PANEL="$ROOT/Panel.qml"

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || {
    printf 'FAIL: missing %q in %s\n' "$needle" "$file" >&2
    exit 1
  }
}

assert_contains 'required property var marketplaceMap' "$PAGE"
assert_contains 'required property bool marketplaceFetchFailed' "$PAGE"
assert_contains 'function verificationText(id)' "$PAGE"
assert_contains 'page.verificationText(updateRow.modelData.id)' "$PAGE"
assert_contains 'marketplaceMap: root.marketplaceMap' "$PANEL"
assert_contains 'marketplaceFetching: root.marketplaceFetching' "$PANEL"
assert_contains 'marketplaceFetchFailed: root.marketplaceFetchFailed' "$PANEL"
assert_contains '"--max-filesize", "8388608"' "$PANEL"

printf 'verification-status-test: ok\n'
