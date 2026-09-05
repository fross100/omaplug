#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$ROOT/plugin-state-test.sh"
"$ROOT/update-helper-test.sh"
"$ROOT/quickshell-detached-test.sh"
bash "$ROOT/verification-status-test.sh"
bash "$ROOT/icon-glyph-test.sh"
