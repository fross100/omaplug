#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$ROOT/plugin-state-test.sh"
"$ROOT/update-helper-test.sh"
"$ROOT/quickshell-detached-test.sh"
"$ROOT/verification-status-test.sh"
