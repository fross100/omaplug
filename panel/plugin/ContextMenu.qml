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
  required property string updateState
  required property bool updateRunning
  required property point requestedPosition
  required property color foreground
  required property string fontFamily
  required property color panelBackground
  property bool canMove: false
  property string currentSection: ""

  signal closeRequested
  signal enabledChangeRequested(string pluginId, bool enabled)
  signal sourceRequested(string sourceKey)
  signal updateRequested(string sourceKey)
  signal removalRequested(string pluginId)
  signal moveRequested(string pluginId, string section)

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
        visible: menu.plugin && menu.plugin.updatable && menu.updateState === "UPDATE"
        text: menu.updateRunning ? "Updating…" : "Update"
        enabled: !menu.updateRunning
        foreground: menu.foreground
        accent: Color.accent
        fontFamily: menu.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft
        onClicked: {
          menu.updateRequested(menu.plugin.sourceKey)
          menu.closeRequested()
        }
      }

      // Bar-widget placement. Only visible for widgets currently on the bar;
      // the widget's own section is marked and disabled so the menu shows
      // where the widget lives now.
      Repeater {
        model: menu.canMove ? ["left", "center", "right"] : []

        Button {
          required property string modelData

          readonly property bool isCurrent: menu.currentSection === modelData

          visible: menu.canMove
          text: (isCurrent ? "● " : "") + "Move to " + modelData
          enabled: !isCurrent
          opacity: isCurrent ? 0.55 : 1.0
          foreground: menu.foreground
          accent: Color.accent
          fontFamily: menu.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(5)
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignLeft
          onClicked: {
            menu.moveRequested(menu.plugin.id, modelData)
            menu.closeRequested()
          }
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
