pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

ColumnLayout {
  id: actions

  required property var plugin
  required property bool pluginEnabled
  required property bool repoKnown
  required property string updateState
  required property bool updateRunning
  required property string updatingId
  required property color foreground
  required property string fontFamily

  signal enabledChangeRequested(bool enabled)
  signal sourceRequested(string sourceKey)
  signal updateRequested(string sourceKey)
  signal menuRequested(var sourceItem, real x, real y)

  readonly property bool showSourceRow: plugin.updatable && repoKnown

  Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
  spacing: Style.space(4)

  RowLayout {
    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    spacing: Style.space(6)

    // Active bar options cannot be disabled directly. Their reduced opacity
    // mirrors the native-toggle guard while still allowing disabled plugins
    // to be enabled from this row.
    Item {
      id: toggle

      readonly property bool checked: actions.pluginEnabled
      readonly property bool canToggle: actions.plugin.canDisable || !checked
      readonly property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
      readonly property int trackWidth: Math.round(trackHeight * 1.9)
      readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
      readonly property int inset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

      implicitWidth: trackWidth
      implicitHeight: trackHeight
      opacity: canToggle ? 1 : 0.4
      Layout.alignment: Qt.AlignVCenter

      Rectangle {
        width: toggle.trackWidth
        height: toggle.trackHeight
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: toggle.checked
          ? Color.accent
          : Style.normalFillFor(actions.foreground, Color.accent)
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
          width: toggle.knobSize
          height: toggle.knobSize
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          x: toggle.checked ? toggle.trackWidth - width - toggle.inset : toggle.inset
          anchors.verticalCenter: parent.verticalCenter
          color: toggle.checked ? Color.background : Qt.darker(actions.foreground, 1.25)
          Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: toggle.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          if (!toggle.canToggle) return
          Qt.callLater(function() { actions.enabledChangeRequested(!toggle.checked) })
        }
      }
    }

    Button {
      id: menuButton

      iconText: "\uf142"
      tooltipText: "More actions"
      visible: !actions.plugin.firstParty
      bordered: true
      borderSpec: menuButton.hot ? Border.none()
        : Border.controlSpec("normal", menuButton.foreground, Color.accent)
      foreground: actions.foreground
      accent: Color.accent
      fontFamily: actions.fontFamily
      fontSize: Style.font.bodySmall
      horizontalPadding: Style.space(6)
      verticalPadding: Style.space(3)
      Layout.alignment: Qt.AlignVCenter
      onClicked: actions.menuRequested(menuButton, 0, menuButton.height)
    }
  }

  RowLayout {
    visible: actions.showSourceRow
    Layout.fillWidth: true
    spacing: Style.space(6)

    Button {
      id: sourceButton

      visible: actions.plugin.updatable && actions.repoKnown
      tooltipText: "Open plugin repository"
      text: "SOURCE \uDB85\uDD94"
      bordered: true
      borderSpec: sourceButton.hot ? Border.none()
        : Border.controlSpec("normal", sourceButton.foreground, Color.accent)
      foreground: actions.foreground
      accent: Color.accent
      fontFamily: actions.fontFamily
      fontSize: Style.font.caption
      iconSize: Style.font.caption
      horizontalPadding: Style.space(6)
      verticalPadding: Style.space(3)
      Layout.fillWidth: true
      onClicked: actions.sourceRequested(actions.plugin.sourceKey)
    }
  }
}
