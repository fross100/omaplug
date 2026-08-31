pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: menu

  required property bool open
  required property var plugin
  required property bool pluginEnabled
  required property bool repoKnown
  required property point requestedPosition
  required property color foreground
  required property string fontFamily
  required property color panelBackground
  // Bar section the plugin currently sits in ("left"/"center"/"right"), or
  // "" when it is not a placed bar widget. Drives the Move-to selector.
  required property string pluginSection

  signal closeRequested
  signal enabledChangeRequested(string pluginId, bool enabled)
  signal sourceRequested(string sourceKey)
  signal removalRequested(string pluginId)
  signal moveRequested(string pluginId, string section)

  readonly property bool canMove: menu.plugin
    && menu.pluginEnabled
    && String(menu.plugin.kinds).indexOf("bar-widget") !== -1

  visible: open
  color: "transparent"
  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onEscapePressed: menu.closeRequested()

  MouseArea {
    anchors.fill: parent
    onClicked: menu.closeRequested()
  }

  Rectangle {
    id: card

    x: Math.min(menu.requestedPosition.x, parent.width - width - Style.space(4))
    y: Math.min(menu.requestedPosition.y, parent.height - height - Style.space(4))
    width: actions.implicitWidth + Style.space(8)
    height: actions.implicitHeight + Style.space(8)
    color: menu.panelBackground
    radius: Style.cornerRadius
    border.color: Util.alpha(menu.foreground, 0.2)
    border.width: 1

    ColumnLayout {
      id: actions

      anchors.fill: parent
      anchors.margins: Style.space(4)
      spacing: Style.space(2)
      implicitWidth: Style.space(180)

      Button {
        text: menu.pluginEnabled
          ? (menu.plugin && menu.plugin.canDisable ? "Disable" : "Active bar")
          : "Enable"
        enabled: menu.plugin && (menu.plugin.canDisable || !menu.pluginEnabled)
        foreground: menu.foreground
        accent: Color.accent
        fontFamily: menu.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft
        onClicked: {
          menu.enabledChangeRequested(menu.plugin.id, !menu.pluginEnabled)
          menu.closeRequested()
        }
      }

      // Move a placed bar widget between the left / center / right sections.
      // The button for the current section is disabled so it reads as state.
      ColumnLayout {
        visible: menu.canMove
        Layout.fillWidth: true
        spacing: Style.space(2)

        Label {
          text: "Move to section"
          color: Util.alpha(menu.foreground, 0.6)
          font.family: menu.fontFamily
          font.pixelSize: Style.font.caption
          Layout.leftMargin: Style.space(8)
          Layout.topMargin: Style.space(4)
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Repeater {
            model: [
              { value: "left", label: "Left" },
              { value: "center", label: "Center" },
              { value: "right", label: "Right" }
            ]

            Button {
              required property var modelData
              text: modelData.label
              enabled: menu.pluginSection !== modelData.value
              foreground: menu.foreground
              accent: Color.accent
              fontFamily: menu.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(5)
              Layout.fillWidth: true
              onClicked: {
                menu.moveRequested(menu.plugin.id, modelData.value)
                menu.closeRequested()
              }
            }
          }
        }
      }

      Button {
        visible: menu.plugin && menu.plugin.sourceKey !== "" && menu.repoKnown
        text: "Source"
        foreground: menu.foreground
        accent: Color.accent
        fontFamily: menu.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft
        onClicked: {
          menu.sourceRequested(menu.plugin.sourceKey)
          menu.closeRequested()
        }
      }

      Button {
        visible: menu.plugin && !menu.plugin.firstParty
        text: "Remove"
        foreground: Color.urgent
        accent: Color.urgent
        fontFamily: menu.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft
        onClicked: {
          var pluginId = menu.plugin.id
          menu.closeRequested()
          menu.removalRequested(pluginId)
        }
      }
    }
  }
}
