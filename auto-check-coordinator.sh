#!/bin/bash

# Coordinates plugin-state.sh across the bar's per-monitor instances. The
# omaplug widget exists once per monitor, each running its own independent
# Panel.qml and its own background auto-check Timer, so an unattended tick
# firing at (roughly) the same moment on every monitor would otherwise run
# N fully redundant git-fetch passes over every installed plugin. This wraps
# plugin-state.sh with a lock + shared cache so only one instance's tick
# does the real work; the others reuse its output.
#
# The manual "Check for updates" button in the panel bypasses this entirely
# and always calls plugin-state.sh directly - only the unattended Timer path
# (Panel.qml's autoUpdateCheckTimer) uses this wrapper.
#
# Usage: auto-check-coordinator.sh <plugins-dir>
# Output: identical CHECK/state line format to plugin-state.sh.

set -euo pipefail

PLUGINS_DIR="${1:?usage: auto-check-coordinator.sh <plugins-dir>}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

exec python3 "$SCRIPT_DIR/runtime-state.py" check "$PLUGINS_DIR"
