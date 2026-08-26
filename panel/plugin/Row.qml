pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Presentation.js" as Presentation

Item {
  id: pluginRow

  required property var modelData
  required property int index
  required property int rowCount
  required property var marketplaceEntry
  required property string localCommit
  required property string repoUrl
  required property bool repoKnown
  required property string updateState
  required property bool removeSelectMode
  required property bool selectedForRemoval
  required property bool removingPlugin
  required property bool pluginEnabled
  required property bool updateRunning
  required property string updatingId
  required property string icon
  required property var knownKinds
  required property color foreground
  required property string fontFamily

  signal removalSelectionRequested(string pluginId)
  signal enabledChangeRequested(string pluginId, bool enabled)
  signal openUrlRequested(string url)
  signal sourceRequested(string sourceKey)
  signal updateRequested(string sourceKey)
  signal menuRequested(string pluginId, var sourceItem, real x, real y)

  readonly property bool listed: marketplaceEntry !== null
  readonly property bool verified: listed && marketplaceEntry.verified === true
  readonly property string authorUrl: modelData.firstParty ? "" : Presentation.authorUrl(repoUrl)
  readonly property string kindLabel: Presentation.kindLabel(modelData.kinds, knownKinds)

  height: card.height + Style.space(9)

  Rectangle {
    id: card

    width: parent.width
    height: Math.max(Style.space(56), Math.min(content.implicitHeight + Style.space(22), Style.space(120)))
    clip: true
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
    color: hover.hovered
      ? Style.hoverFillFor(pluginRow.foreground, Color.accent)
      : "transparent"

    RowLayout {
      id: content

      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.topMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.bottomMargin: Style.space(10)
      spacing: Style.space(10)

      Button {
        visible: pluginRow.removeSelectMode
        text: pluginRow.selectedForRemoval ? "\uf14a" : "\uf0c8"
        tooltipText: "Select plugin for removal"
        enabled: !pluginRow.removingPlugin
        Layout.alignment: Qt.AlignVCenter
        foreground: pluginRow.foreground
        accent: Color.accent
        fontFamily: pluginRow.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(3)
        onClicked: pluginRow.removalSelectionRequested(pluginRow.modelData.id)
      }

      Rectangle {
        Layout.preferredWidth: Style.space(28)
        Layout.preferredHeight: Layout.preferredWidth
        radius: 6
        color: Presentation.iconColor(pluginRow.modelData.name)

        Text {
          anchors.centerIn: parent
          text: pluginRow.icon || pluginRow.modelData.name.trim().charAt(0).toUpperCase()
          textFormat: Text.PlainText
          color: "white"
          font.family: pluginRow.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Label {
            text: pluginRow.modelData.name
            textFormat: Text.PlainText
            color: pluginRow.foreground
            font.family: pluginRow.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            // Keep the badge and version adjacent to the name while still
            // letting long names shrink and elide instead of displacing the
            // action column (#4).
            Layout.minimumWidth: 0
            elide: Label.ElideRight
          }

          Rectangle {
            visible: pluginRow.listed
            radius: height / 2
            implicitWidth: badgeContent.implicitWidth + Style.space(10)
            implicitHeight: Style.space(16)
            color: pluginRow.verified
              ? Util.alpha(Color.accent, 0.18)
              : Qt.rgba(pluginRow.foreground.r, pluginRow.foreground.g, pluginRow.foreground.b, 0.08)

            Row {
              id: badgeContent
              anchors.centerIn: parent
              spacing: Style.space(3)

              Text {
                visible: pluginRow.verified
                text: "\uf058"
                textFormat: Text.PlainText
                color: Color.accent
                font.family: pluginRow.fontFamily
                font.pixelSize: Style.font.caption - 1
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: pluginRow.verified ? "Verified" : "Unverified"
                textFormat: Text.PlainText
                color: pluginRow.verified ? Color.accent : Qt.darker(pluginRow.foreground, 2.0)
                font.family: pluginRow.fontFamily
                font.pixelSize: Style.font.caption - 1
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          Label {
            visible: pluginRow.modelData.version !== "unknown"
            text: "v" + pluginRow.modelData.version
            textFormat: Text.PlainText
            color: Qt.darker(pluginRow.foreground, 2.0)
            font.family: pluginRow.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Label {
          text: pluginRow.modelData.description !== "" ? pluginRow.modelData.description : "No description"
          textFormat: Text.PlainText
          color: Qt.darker(pluginRow.foreground, 1.6)
          font.family: pluginRow.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          wrapMode: Label.Wrap
          maximumLineCount: 2
          elide: Label.ElideRight
        }

        RowLayout {
          visible: pluginRow.modelData.author !== ""
          spacing: Style.space(6)
          Layout.fillWidth: true

          Text {
            text: "by " + pluginRow.modelData.author + (pluginRow.authorUrl !== "" ? " ↗" : "")
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: pluginRow.authorUrl !== "" ? Color.accent : Qt.darker(pluginRow.foreground, 2.0)
            font.family: pluginRow.fontFamily
            font.pixelSize: Style.font.caption
            font.underline: authorHover.hovered && pluginRow.authorUrl !== ""

            ToolTip.text: pluginRow.authorUrl !== "" ? pluginRow.authorUrl : ("by " + pluginRow.modelData.author)
            ToolTip.visible: authorHover.hovered
            ToolTip.delay: 400

            HoverHandler {
              id: authorHover
              cursorShape: pluginRow.authorUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            MouseArea {
              anchors.fill: parent
              enabled: pluginRow.authorUrl !== ""
              cursorShape: Qt.PointingHandCursor
              onClicked: pluginRow.openUrlRequested(pluginRow.authorUrl)
            }
          }

          Text {
            visible: pluginRow.kindLabel !== ""
            text: "·"
            textFormat: Text.PlainText
            color: Qt.darker(pluginRow.foreground, 2.0)
            font.family: pluginRow.fontFamily
            font.pixelSize: Style.font.caption
          }

          Label {
            visible: pluginRow.kindLabel !== ""
            text: pluginRow.kindLabel
            textFormat: Text.PlainText
            color: Qt.darker(pluginRow.foreground, 2.0)
            font.family: pluginRow.fontFamily
            font.pixelSize: Style.font.caption
            elide: Label.ElideRight
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignRight
          }

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
          }
        }

        ListingLinks {
          visible: pluginRow.listed
          pluginId: pluginRow.modelData.id
          entry: pluginRow.marketplaceEntry
          localCommit: pluginRow.localCommit
          repoUrl: pluginRow.repoUrl
          foreground: pluginRow.foreground
          fontFamily: pluginRow.fontFamily
          onOpenUrlRequested: function(url) { pluginRow.openUrlRequested(url) }
        }
      }

      Actions {
        plugin: pluginRow.modelData
        pluginEnabled: pluginRow.pluginEnabled
        repoKnown: pluginRow.repoKnown
        updateState: pluginRow.updateState
        updateRunning: pluginRow.updateRunning
        updatingId: pluginRow.updatingId
        foreground: pluginRow.foreground
        fontFamily: pluginRow.fontFamily
        onEnabledChangeRequested: function(enabled) {
          pluginRow.enabledChangeRequested(pluginRow.modelData.id, enabled)
        }
        onSourceRequested: function(sourceKey) { pluginRow.sourceRequested(sourceKey) }
        onUpdateRequested: function(sourceKey) { pluginRow.updateRequested(sourceKey) }
        onMenuRequested: function(sourceItem, x, y) {
          pluginRow.menuRequested(pluginRow.modelData.id, sourceItem, x, y)
        }
      }
    }

    HoverHandler {
      id: hover
    }

    TapHandler {
      id: contextTap
      acceptedButtons: Qt.RightButton
      onTapped: function(eventPoint) {
        pluginRow.menuRequested(
          pluginRow.modelData.id,
          card,
          eventPoint.position.x,
          eventPoint.position.y
        )
      }
    }
  }

  Rectangle {
    visible: pluginRow.index < pluginRow.rowCount - 1
    anchors.top: card.bottom
    anchors.topMargin: Style.space(4)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    height: 1
    color: Qt.rgba(pluginRow.foreground.r, pluginRow.foreground.g, pluginRow.foreground.b, 0.12)
  }
}
