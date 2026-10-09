pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Rectangle {
  id: dialog
  required property bool open
  required property bool running
  required property string pluginName
  required property string savedShortcut
  required property string pendingShortcut
  required property string result
  required property color foreground
  required property string fontFamily
  required property color panelBackground
  signal closeRequested
  signal actionRequested(string action, string combination)
  property string capturedShortcut: ""
  visible: open
  color: Util.alpha("black", 0.6)
  onOpenChanged: if (open) {
    capturedShortcut = ""
    captureBox.forceActiveFocus()
  }
  onRunningChanged: if (open && !running) captureBox.forceActiveFocus()

  ShortcutInhibitor {
    id: shortcutInhibitor
    window: dialog.QsWindow.window
    enabled: dialog.open && captureBox.activeFocus
  }
  MouseArea { anchors.fill: parent; onClicked: if (!dialog.running) dialog.closeRequested() }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), Style.space(420))
    height: content.implicitHeight + Style.space(32)
    color: dialog.panelBackground
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(dialog.foreground, 0.3)
    MouseArea { anchors.fill: parent }
    ColumnLayout {
      id: content
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(10)
      Label {
        text: "Shortcut for " + dialog.pluginName
        textFormat: Text.PlainText
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Label {
        text: "Press a shortcut to check it. Available shortcuts save automatically; conflicts can be replaced."
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        id: captureBox
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(56)
        radius: Style.cornerRadius
        color: Util.alpha(dialog.foreground, 0.06)
        border.color: activeFocus ? Commons.Color.accent : Util.alpha(dialog.foreground, 0.3)
        border.width: 1
        activeFocusOnTab: true
        property int heldKey: 0
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          event.accepted = true
          if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
            if (!dialog.running) dialog.closeRequested()
            return
          }
          if (dialog.running || event.isAutoRepeat || captureBox.heldKey || !shortcutInhibitor.active) return
          var key = ""
          if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            key = String.fromCharCode(event.key)
          else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            key = String.fromCharCode(event.key)
          else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12)
            key = "F" + (event.key - Qt.Key_F1 + 1)
          else {
            var names = {}
            names[Qt.Key_Space] = "SPACE"
            names[Qt.Key_Slash] = "SLASH"
            names[Qt.Key_Question] = "SLASH"
            names[Qt.Key_Return] = "RETURN"
            names[Qt.Key_Tab] = "TAB"
            names[Qt.Key_Backtab] = "TAB"
            names[Qt.Key_Escape] = "ESCAPE"
            names[Qt.Key_Home] = "HOME"
            names[Qt.Key_End] = "END"
            names[Qt.Key_Insert] = "INSERT"
            names[Qt.Key_Delete] = "DELETE"
            names[Qt.Key_PageUp] = "PAGEUP"
            names[Qt.Key_PageDown] = "PAGEDOWN"
            names[Qt.Key_Up] = "UP"
            names[Qt.Key_Down] = "DOWN"
            names[Qt.Key_Left] = "LEFT"
            names[Qt.Key_Right] = "RIGHT"
            key = names[event.key] || ""
          }
          if (!key) return
          var parts = []
          if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
          if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
          if (event.modifiers & Qt.AltModifier) parts.push("ALT")
          if ((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Question) parts.push("SHIFT")
          if (!parts.length || (event.modifiers & (Qt.KeypadModifier | Qt.GroupSwitchModifier))) return
          captureBox.heldKey = event.key
          dialog.capturedShortcut = parts.concat([key]).join(" + ")
          dialog.actionRequested("save", dialog.capturedShortcut)
        }
        Keys.onReleased: function(event) {
          if (event.key === captureBox.heldKey) captureBox.heldKey = 0
          event.accepted = true
        }
        onActiveFocusChanged: if (!activeFocus) heldKey = 0
        Label {
          anchors.centerIn: parent
          text: dialog.capturedShortcut || (captureBox.activeFocus ? "Press your shortcut…" : "Click to record a shortcut")
          color: dialog.foreground
          font.family: dialog.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea { anchors.fill: parent; onClicked: captureBox.forceActiveFocus() }
      }
      Label {
        text: dialog.running ? "Checking and saving…"
          : captureBox.activeFocus && !shortcutInhibitor.active
            ? "Press Escape or click Done to cancel."
            : ""
        textFormat: Text.PlainText
        visible: dialog.running || (captureBox.activeFocus && !shortcutInhibitor.active)
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
      }
      RowLayout {
        spacing: Style.space(8)
        Label {
          visible: dialog.result !== ""
          text: dialog.result
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignLeft
          wrapMode: Text.WordWrap
          color: /saved|removed|Available|No shortcut/.test(dialog.result) ? Commons.Color.accent : Commons.Color.urgent
          font.family: dialog.fontFamily
          font.pixelSize: Style.font.caption
        }
        Button {
          objectName: "replaceShortcutButton"
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          visible: dialog.pendingShortcut !== ""
          text: "Replace"
          enabled: !dialog.running
          foreground: Commons.Color.urgent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.caption
          onClicked: dialog.actionRequested("replace", dialog.pendingShortcut)
        }
        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: "Remove shortcut"
          enabled: !dialog.running && dialog.savedShortcut !== ""
          foreground: dialog.foreground
          fontFamily: dialog.fontFamily
          fontSize: Style.font.caption
          onClicked: dialog.actionRequested("remove", "")
        }
        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: "Done"
          enabled: !dialog.running
          foreground: dialog.foreground
          fontFamily: dialog.fontFamily
          fontSize: Style.font.caption
          onClicked: dialog.closeRequested()
        }
      }
    }
  }
}
