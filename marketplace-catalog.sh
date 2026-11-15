#!/bin/bash

set -euo pipefail

CATALOG_URL=${1:-https://plugins.omarchy.org/catalog.json}

# The catalog is served gzipped (17 MB -> 2.3 MB), but curl's --max-filesize
# counts compressed bytes, so the decompressed payload is capped here too.
CATALOG_FILE=$(mktemp)
trap 'rm -f -- "$CATALOG_FILE"' EXIT
curl -fsSL --compressed --max-time 60 --max-filesize 67108864 -o "$CATALOG_FILE" "$CATALOG_URL"
test "$(wc -c < "$CATALOG_FILE")" -le 67108864 ||
  { printf 'catalog exceeded the 67108864 byte cap\n' >&2; exit 63; }

jq -ce '
    def s($n): if type == "string" then .[0:$n] else . end;
    if (.plugins | type) != "array" then
      error("catalog.plugins is not an array")
    else
      {
        plugins: [
          .plugins[]
          | select((.id | type) == "string" and (.id | length) > 0)
          | ({
              id: (.id | s(128)),
              verificationStatus: (.verificationStatus | s(64)),
              verificationCommit: (.verificationCommit | s(64)),
              verificationSnapshotStatus: (.verificationSnapshotStatus | s(64)),
              verificationCoverage: (.verificationCoverage | s(64)),
              upstreamObservedCommit: (.upstreamObservedCommit | s(64)),
              repositoryRelease: (
                if (.repositoryRelease | type) == "object" then
                  {url: (.repositoryRelease.url | s(512))}
                else
                  null
                end
              )
            }
            + (if (.name | type) == "string" then {name: .name[0:128]} else {} end)
            + (if (.version | type) == "string" then {version: .version[0:64]} else {} end)
            + (if (.author | type) == "string" then {author: .author[0:128]} else {} end)
            + (if (.description | type) == "string" then {description: .description[0:2048]} else {} end)
            + (if (.icon | type) == "string" then {icon: .icon[0:64]} else {} end)
            + (if (.repositoryUrl | type) == "string" then {repositoryUrl: .repositoryUrl[0:512]} else {} end)
            + (if (.sourceUrl | type) == "string" then {sourceUrl: .sourceUrl[0:512]} else {} end)
            + (if (.source | type) == "string" then {source: .source[0:512]} else {} end)
            + (if (.installCommand | type) == "string" then {installCommand: .installCommand[0:512]} else {} end)
            + (if (.repository | type) == "string" then {repositoryUrl: .repository[0:512]} else {} end)
            + (if (.repository | type) == "object" and (.repository.url | type) == "string" then {repositoryUrl: .repository.url[0:512]} else {} end)
          )
        ]
      }
    end
  ' "$CATALOG_FILE"
