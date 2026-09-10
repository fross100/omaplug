#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/nested-widget-toggle.sh"

grep -Fq 'omarchy bar set "$host" widgets "$widgets" --json' "$HELPER"
grep -Fq 'omarchy plugin disable "$id"' "$HELPER"
grep -Fq '(.widgets | index($id)) != null' "$HELPER"

printf 'nested-widget-toggle-test: ok\n'
