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
          | {
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
        ]
      }
    end
  '
