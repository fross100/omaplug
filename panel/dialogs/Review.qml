pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Rectangle {
  id: dialog

  required property bool open
  required property bool running
  required property bool failed
  required property string result
  required property color foreground
  required property string fontFamily
  required property color panelBackground
  required property string runtimeStatePath

  signal closeRequested
  signal installRequested(string rawUrl)

  visible: open
  color: Util.alpha("black", 0.6)
  focus: true
  onOpenChanged: {
    if (open) {
      Qt.callLater(function() { urlField.forceActiveFocus() })
    } else {
      urlPasteGen++
      if (urlPaste.running) urlPaste.running = false
    }
  }
  Keys.priority: Keys.BeforeItem
  Keys.onEscapePressed: {
    if (!dialog.running) dialog.closeRequested()
  }

  function pasteIntoUrl() {
    if (urlPaste.running) return
    urlPasteGen++
    urlPaste.gen = urlPasteGen
    urlPaste.running = true
  }

  property int urlPasteGen: 0

  // Native Qt Quick paste does an unbounded synchronous Wayland read, so a
  // hostile clipboard owner can stall the shell. Read with a size/time cap.
  Process {
    id: urlPaste
    property int gen: 0
    command: ["python3", dialog.runtimeStatePath, "paste"]
    stdout: StdioCollector { id: urlPasteOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (urlPaste.gen !== dialog.urlPasteGen || !dialog.open || !urlField.activeFocus) return
      if (exitCode !== 0) return
      var text = String(urlPasteOut.text || "")
      if (text === "") return
      if (urlField.selectionEnd > urlField.selectionStart)
        urlField.remove(urlField.selectionStart, urlField.selectionEnd)
      urlField.insert(urlField.cursorPosition, text)
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (!dialog.running) dialog.closeRequested()
    }
  }

  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), Style.space(360))
    height: content.implicitHeight + Style.space(36)
    color: dialog.panelBackground
    radius: Style.cornerRadius
    border.color: Style.selectedStateColor(dialog.foreground, Commons.Color.accent)
    border.width: 1

    ColumnLayout {
      id: content

      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(12)

      Text {
        text: "Install a plugin from a git repo"
        textFormat: Text.PlainText
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      Text {
        text: "Plugins run as arbitrary, unsandboxed code inside your omarchy-shell process. Only add repos you trust — review the code before you enable the plugin."
        textFormat: Text.PlainText
        color: Qt.darker(dialog.foreground, 1.6)
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      TextField {
        id: urlField

        placeholderText: "Paste a GitHub plugin link"
        placeholderTextColor: Util.alpha(dialog.foreground, 0.45)
        foreground: dialog.foreground
        accent: Commons.Color.accent
        font.family: dialog.fontFamily
        Layout.fillWidth: true
        // Replace native paste (unbounded synchronous Wayland read) with the
        // capped reader; accept here so the TextField never sees it.
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if ((event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier))
              || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
            event.accepted = true
            dialog.pasteIntoUrl()
          }
        }
        MouseArea {
          anchors.fill: parent
          z: 1
          acceptedButtons: Qt.MiddleButton
          cursorShape: Qt.IBeamCursor
          onPressed: dialog.pasteIntoUrl()
        }
        onAccepted: {
          if (urlField.text.trim() !== "" && !dialog.running)
            dialog.installRequested(urlField.text)
        }
      }

      Text {
        visible: dialog.result !== ""
        text: dialog.result
        textFormat: Text.PlainText
        color: dialog.running ? dialog.foreground
          : (dialog.failed ? Commons.Color.urgent
            : Style.selectedStateColor(dialog.foreground, Commons.Color.accent))
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: dialog.result !== "" ? "Close" : "Cancel"
          enabled: !dialog.running
          foreground: dialog.foreground
          accent: Commons.Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.closeRequested()
        }

        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: dialog.running ? "Installing…" : "Review"
          enabled: !dialog.running
          foreground: dialog.foreground
          accent: Commons.Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.installRequested(urlField.text)
        }
      }
    }
  }
}
