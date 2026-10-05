#!/bin/bash

set -euo pipefail

CATALOG_URL=${1:-https://plugins.omarchy.org/catalog.json}

curl -fsSL --max-time 30 --max-filesize 16777216 "$CATALOG_URL" |
  jq -ce '
    if (.plugins | type) != "array" then
      error("catalog.plugins is not an array")
    else
      {
        plugins: [
          .plugins[]
          | select((.id | type) == "string" and (.id | length) > 0)
          | ({
              id,
              verificationStatus,
              verificationCommit,
              verificationSnapshotStatus,
              verificationCoverage,
              upstreamObservedCommit,
              repositoryRelease: (
                if (.repositoryRelease | type) == "object" then
                  {url: .repositoryRelease.url}
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
  '
