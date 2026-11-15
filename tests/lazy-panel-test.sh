#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WIDGET="$ROOT/BarWidget.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Issue #48: building the panel at shell startup freezes the shell for seconds.
if grep -Fq 'active: true' "$WIDGET"; then
  fail 'panel loader must not be eagerly active'
fi
grep -Fq 'active: false' "$WIDGET" || fail 'panel loader must start inactive'

# First use must activate it, and the queued call must be delivered on load.
grep -Fq 'property string pendingPanelCall' "$WIDGET" || fail 'first call is not queued'
grep -Fq 'panelLoader.active = true' "$WIDGET" || fail 'nothing activates the panel loader'
grep -Fq 'root.withPanel(call)' "$WIDGET" || fail 'queued call is not delivered after load'

# The update badge and the auto-check timer still come up without a first click.
grep -Fq 'onTriggered: panelLoader.active = true' "$WIDGET" || fail 'deferred load timer missing'

printf 'lazy-panel-test: ok\n'
