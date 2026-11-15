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
grep -Fq -- '--max-filesize 67108864' "$HELPER"

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

# Long remote fields must be truncated at the producer, not carried into the panel.
HOSTILE="$TMP/hostile.json"
jq -n '{plugins: [{
  id: ("i" * 5000),
  verificationStatus: ("v" * 5000),
  verificationCommit: ("c" * 5000),
  repositoryRelease: {url: ("https://github.com/o/r/" + ("x" * 5000))}
}]}' > "$HOSTILE"
jq -e '.plugins[0]
  | (.id | length) == 128 and (.verificationStatus | length) == 64
  and (.verificationCommit | length) == 64
  and (.repositoryRelease.url | length) == 512' \
  <<< "$("$HELPER" "file://$HOSTILE")" >/dev/null

# curl's cap counts compressed bytes, so the helper also rejects an oversized
# decompressed payload (simulated here with a lowered cap).
LOWCAP="$TMP/lowcap.sh"
sed -e 's/--max-filesize 67108864/--max-filesize 1000000000/' \
  -e 's/-le 67108864/-le 1000/' "$HELPER" > "$LOWCAP"
set +e
bash "$LOWCAP" "file://$FIXTURE" >/dev/null 2>&1
rc=$?
set -e
test "$rc" -eq 63

printf 'catalog-fetch-test: ok\n'
