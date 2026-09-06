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

  // Mirrors Panel.qml's autoCheckEnabled / autoCheckIntervalHours.
  readonly property bool autoCheckEnabled: root.setting("autoCheckUpdates", true) === true
  readonly property int autoCheckIntervalHours: {
    var hours = Number(root.setting("autoCheckIntervalHours", 6))
    return (isFinite(hours) && hours > 0) ? hours : 6
  }

  // Mirrors Panel.qml's pendingUpdateCount.
  property var updateStates: JSON.parse(Quickshell.env("OMAPLUG_TEST_UPDATE_STATES") || "{}")
  property var pluginRepos: JSON.parse(Quickshell.env("OMAPLUG_TEST_PLUGIN_REPOS") || "{}")
  readonly property int pendingUpdateCount: {
    var n = 0
    for (var k in root.updateStates) {
      if (root.pluginRepos[k] === undefined) continue
      if (root.updateStates[k] === "UPDATE") n++
    }
    n
  }

  Component.onCompleted: {
    console.log("RESOLVED_ENABLED", root.autoCheckEnabled)
    console.log("RESOLVED_HOURS", root.autoCheckIntervalHours)
    console.log("RESOLVED_PENDING", root.pendingUpdateCount)
  }

  // The property under test: same shape as Panel.qml's autoUpdateCheckTimer.
  Timer {
    interval: root.autoCheckIntervalHours * 3600000
    running: root.autoCheckEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: console.log("TIMER_FIRED")
  }

  // Bounds how long the process waits for a trigger before exiting; must be
  // well under any interval used above so a firing timer wins the race.
  Timer {
    interval: 400
    running: true
    onTriggered: Qt.quit()
  }
}
