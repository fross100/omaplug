#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PANEL="$ROOT/Panel.qml"
HELPER="$ROOT/marketplace-catalog.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

grep -Fq 'Qt.resolvedUrl("marketplace-catalog.sh")' "$PANEL"
grep -Fq 'marketplaceProcess.command = [root.marketplaceHelperPath]' "$PANEL"
grep -Fq 'if (exitCode !== 0)' "$PANEL"
grep -Fq '!Array.isArray(catalog.plugins)' "$PANEL"
grep -Fq -- '--max-filesize 16777216' "$HELPER"

if grep -Fq 'head -c 4194304' "$PANEL"; then
  printf 'FAIL: marketplace fetch must reject oversized catalogs, not truncate them\n' >&2
  exit 1
fi

FIXTURE="$TMP/catalog.json"
jq -n '{
  ignored: ("x" * 4500000),
  plugins: [
    {
      id: "fixture",
      verificationStatus: "verified",
      verificationCommit: "abc",
      upstreamObservedCommit: "def",
      repositoryRelease: {url: "https://example.invalid/release"},
      extra: ("y" * 10000)
    }
  ]
}' > "$FIXTURE"

test "$(wc -c < "$FIXTURE")" -gt 4194304
SUMMARY=$("$HELPER" "file://$FIXTURE")
jq -e '.plugins | length == 1' <<< "$SUMMARY" >/dev/null
jq -e '.plugins[0] == {
  id: "fixture",
  verificationStatus: "verified",
  verificationCommit: "abc",
  verificationSnapshotStatus: null,
  verificationCoverage: null,
  upstreamObservedCommit: "def",
  repositoryRelease: {url: "https://example.invalid/release"}
}' <<< "$SUMMARY" >/dev/null
test "$(wc -c <<< "$SUMMARY")" -lt 4096

printf 'catalog-fetch-test: ok\n'
