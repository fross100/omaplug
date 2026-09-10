import QtQuick
import Quickshell

// Standalone harness for the background auto-check logic added to
// Panel.qml (autoCheckEnabled, autoCheckIntervalHours, and the
// pendingUpdateCount filter). Panel.qml itself only loads inside the full
// Omarchy shell (qs.Ui, qs.Commons, the live PluginRegistry), so this copies
// the pure expressions to exercise them in isolation. Keep the three
// `readonly property` blocks below byte-for-byte in sync with Panel.qml if
// that logic changes.
ShellRoot {
  id: root

  property var settings: {
    var raw = Quickshell.env("OMAPLUG_TEST_SETTINGS")
    return raw ? JSON.parse(raw) : {}
  }

  // Mirrors qs.Ui/Panel.qml's setting(name, fallback).
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Kept byte-identical to Panel.qml by auto-check-test.sh's sync guard;
  // edit both or the build fails.
  // AUTOCHECK-SETTINGS-BEGIN
  readonly property bool autoCheckEnabled: root.setting("autoCheckUpdates", false) === true
  // real, not int: an int property truncates any fractional hours value
  // (e.g. 0.5) towards zero, which would silently turn into a zero-interval
  // Timer below and spin checkUpdates() in a tight loop.
  readonly property real autoCheckIntervalHours: {
    var hours = Number(root.setting("autoCheckIntervalHours", 6))
    return (isFinite(hours) && hours > 0) ? hours : 6
  }
  // AUTOCHECK-SETTINGS-END

  property var updateStates: JSON.parse(Quickshell.env("OMAPLUG_TEST_UPDATE_STATES") || "{}")
  property var pluginRepos: JSON.parse(Quickshell.env("OMAPLUG_TEST_PLUGIN_REPOS") || "{}")

  // Kept byte-identical to Panel.qml by auto-check-test.sh's sync guard;
  // edit both or the build fails.
  // PENDING-UPDATE-COUNT-BEGIN
  readonly property int pendingUpdateCount: {
    var n = 0
    for (var k in root.updateStates) {
      if (root.pluginRepos[k] === undefined) continue
      if (root.updateStates[k] === "UPDATE") n++
    }
    n
  }
  // PENDING-UPDATE-COUNT-END

  Component.onCompleted: {
    console.log("RESOLVED_ENABLED", root.autoCheckEnabled)
    console.log("RESOLVED_HOURS", root.autoCheckIntervalHours)
    console.log("RESOLVED_PENDING", root.pendingUpdateCount)
  }

  // The property under test: same shape as Panel.qml's autoUpdateCheckTimer.
  // running/interval stay bound to autoCheckEnabled/autoCheckIntervalHours so
  // a live settings change (see toggleTimer below) reaches this Timer the
  // same way persistAutoCheckSetting()'s write to root.settings does in the
  // real Panel.qml - no restart, just the binding re-evaluating.
  Timer {
    interval: root.autoCheckIntervalHours * 3600000
    running: root.autoCheckEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: console.log("TIMER_FIRED")
  }

  // Simulates the user flipping the panel's toggle (or picking a new
  // interval) while the shell is already running: OMAPLUG_TEST_TOGGLE_AFTER_MS
  // schedules a one-shot settings mutation partway through the run, proving
  // the Timer above reacts live rather than only at startup.
  property real toggleAfterMs: Number(Quickshell.env("OMAPLUG_TEST_TOGGLE_AFTER_MS") || "0")
  Timer {
    interval: root.toggleAfterMs
    running: root.toggleAfterMs > 0
    onTriggered: {
      var next = {}
      for (var k in root.settings) next[k] = root.settings[k]
      next.autoCheckUpdates = Quickshell.env("OMAPLUG_TEST_TOGGLE_TO") === "true"
      root.settings = next
      console.log("TOGGLED_ENABLED", root.autoCheckEnabled)
    }
  }

  // Bounds how long the process waits for triggers before exiting; must be
  // well under any interval used above so a firing timer wins the race, and
  // comfortably after toggleAfterMs so the post-toggle behavior is observed.
  Timer {
    interval: 1200
    running: true
    onTriggered: Qt.quit()
  }
}
