#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PAGE="$ROOT/panel/updates/Page.qml"
PANEL="$ROOT/Panel.qml"
ROW="$ROOT/panel/plugin/Row.qml"

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
assert_contains 'function verificationText(id, sourceKey)' "$PAGE"
assert_contains 'page.verificationText(updateRow.modelData.id, updateRow.modelData.sourceKey)' "$PAGE"
assert_contains 'marketplaceMap: root.marketplaceMap' "$PANEL"
assert_contains 'marketplaceFetching: root.marketplaceFetching' "$PANEL"
assert_contains 'marketplaceFetchFailed: root.marketplaceFetchFailed' "$PANEL"
assert_contains 'marketplaceProcess.command = [root.marketplaceHelperPath]' "$PANEL"
assert_contains 'Marketplace unavailable' "$PANEL"
assert_contains 'onClicked: root.fetchMarketplace()' "$PANEL"
assert_contains 'console.warn("marketplace catalog fetch failed' "$PANEL"
assert_contains 'catalog exceeded the 16 MiB fetch cap (curl exit 63)' "$PANEL"
assert_contains 'required property bool marketplaceUnavailable' "$ROW"
assert_contains 'marketplaceUnavailable: !pluginRow.modelData.firstParty && root.marketplaceFetchFailed' "$PANEL"
assert_contains '--max-filesize 16777216' "$ROOT/marketplace-catalog.sh"

printf 'verification-status-test: ok\n'
