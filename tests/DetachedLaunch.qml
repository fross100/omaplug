import QtQuick
import Quickshell

ShellRoot {
  Component.onCompleted: {
    Quickshell.execDetached([
      Quickshell.env("OMAPLUG_TEST_HELPER"),
      Quickshell.env("OMAPLUG_TEST_STATUS"),
      "job-quickshell",
      "slow",
      "good"
    ])
    exitTimer.start()
  }

  Timer {
    id: exitTimer
    interval: 50
    onTriggered: Qt.quit()
  }
}
