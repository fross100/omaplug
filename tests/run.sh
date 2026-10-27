#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$ROOT/plugin-state-test.sh"
"$ROOT/update-helper-test.sh"
"$ROOT/quickshell-detached-test.sh"
bash "$ROOT/verification-status-test.sh"
node "$ROOT/plugin-metadata-test.cjs"
node "$ROOT/presentation-links-test.cjs"
node "$ROOT/bulk-update-scope-test.cjs"
"$ROOT/auto-check-test.sh"
"$ROOT/auto-check-coordinator-test.sh"
"$ROOT/nested-widget-toggle-test.sh"
python3 "$ROOT/security-regression-test.py"
python3 "$ROOT/plugin-folder-layout-test.py"
python3 "$ROOT/review-repository-test.py"
python3 "$ROOT/menu-entry-test.py"
python3 "$ROOT/shortcut-test.py"
node "$ROOT/shortcut-capture-test.cjs"
python3 "$ROOT/qml-import-test.py"
