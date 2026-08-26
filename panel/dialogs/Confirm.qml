pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: dialog

  required property bool open
  required property string title
  required property string message
  required property string confirmText
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  property bool dismissEnabled: true
  property real maximumWidth: Style.space(360)
  property color borderColor: Style.selectedStateColor(foreground, Color.accent)
  property color confirmForeground: foreground
  property color confirmAccent: Color.accent
  property bool confirmBordered: false
  property int titleWrapMode: Text.NoWrap

  signal cancelRequested
  signal confirmRequested

  visible: open
  color: Util.alpha(panelBackground, 0.7)
  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onEscapePressed: {
    if (dialog.dismissEnabled) dialog.cancelRequested()
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (dialog.dismissEnabled) dialog.cancelRequested()
    }
  }

  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), dialog.maximumWidth)
    height: content.implicitHeight + Style.space(36)
    color: dialog.panelBackground
    radius: Style.cornerRadius
    border.color: dialog.borderColor
    border.width: 1

    ColumnLayout {
      id: content

      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(12)

      Text {
        text: dialog.title
        textFormat: Text.PlainText
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
        wrapMode: dialog.titleWrapMode
      }

      Text {
        text: dialog.message
        textFormat: Text.PlainText
        color: Qt.darker(dialog.foreground, 1.6)
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        Button {
          text: "Cancel"
          foreground: dialog.foreground
          accent: Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.cancelRequested()
        }

        Button {
          text: dialog.confirmText
          bordered: dialog.confirmBordered
          foreground: dialog.confirmForeground
          accent: dialog.confirmAccent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.confirmRequested()
        }
      }
    }
  }
}
