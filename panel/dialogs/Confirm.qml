pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
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
  property color borderColor: Style.selectedStateColor(foreground, Commons.Color.accent)
  property color confirmForeground: foreground
  property color confirmAccent: Commons.Color.accent
  property bool confirmBordered: false
  property int titleWrapMode: Text.NoWrap
  property string pluginName: ""
  property string pluginVersion: ""
  property string pluginDescription: ""
  property string pluginIcon: ""
  property string marketplaceStatus: ""
  property bool marketplaceListed: false
  property string sourceUrl: ""
  property string marketplaceUrl: ""
  property bool alreadyInstalled: false
  property bool confirmEnabled: true
  property string versionComparison: ""
  property string reviewNote: ""

  signal cancelRequested
  signal confirmRequested
  signal sourceRequested(string url)
  signal marketplaceRequested(string url)

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
        visible: dialog.pluginName !== ""
        Layout.fillWidth: true
        spacing: Style.space(10)
        Rectangle {
          Layout.preferredWidth: Style.space(36)
          Layout.preferredHeight: Style.space(36)
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.accent, 0.8)
          Text {
            anchors.centerIn: parent
            text: dialog.pluginIcon || dialog.pluginName.trim().charAt(0).toUpperCase()
            color: Commons.Color.background
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.title
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: Style.space(2)
          Item {
            id: nameRow
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: Math.max(pluginTitle.implicitHeight, marketplaceBadge.implicitHeight)
            Text {
              id: pluginTitle
              anchors.verticalCenter: parent.verticalCenter
              text: dialog.pluginName
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              width: Math.max(0, Math.min(implicitWidth, nameRow.width - (marketplaceBadge.visible ? marketplaceBadge.width + Style.space(6) : 0)))
              elide: Text.ElideRight
            }
            Rectangle {
              id: marketplaceBadge
              x: pluginTitle.width + Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: dialog.marketplaceStatus !== ""
              implicitWidth: badgeContent.implicitWidth + Style.space(10)
              implicitHeight: Style.space(16)
              radius: height / 2
              color: dialog.marketplaceStatus === "Verified on marketplace"
                ? Util.alpha(Commons.Color.accent, 0.18)
                : dialog.marketplaceStatus === "Update Unverified"
                  ? Qt.rgba(0.85, 0.65, 0.13, 0.18)
                  : Util.alpha(dialog.foreground, 0.08)
              Row {
                id: badgeContent
                anchors.centerIn: parent
                spacing: Style.space(3)
                Text {
                  visible: dialog.marketplaceStatus === "Verified on marketplace" || dialog.marketplaceStatus === "Update Unverified"
                  text: dialog.marketplaceStatus === "Update Unverified" ? "\uf071" : "\uf058"
                  color: dialog.marketplaceStatus === "Update Unverified" ? Qt.hsla(0.12, 0.75, 0.55, 1) : Commons.Color.accent
                  font.family: dialog.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
                Text {
                  text: dialog.marketplaceStatus === "Verified on marketplace" ? "Verified"
                    : dialog.marketplaceStatus === "Update Unverified" ? "Update Unverified"
                    : dialog.marketplaceStatus
                  color: dialog.marketplaceStatus === "Verified on marketplace" ? Commons.Color.accent
                    : dialog.marketplaceStatus === "Update Unverified" ? Qt.hsla(0.12, 0.75, 0.55, 1)
                    : Qt.darker(dialog.foreground, 2.0)
                  font.family: dialog.fontFamily
                  font.pixelSize: Style.font.caption - 1
                }
              }
            }
          }
          RowLayout {
            spacing: Style.space(6)
            Text {
              text: dialog.pluginVersion
              visible: text !== ""
              color: Qt.darker(dialog.foreground, 1.6)
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            text: dialog.versionComparison
            textFormat: Text.PlainText
            visible: text !== ""
            color: dialog.foreground
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
            wrapMode: Text.WrapAnywhere
            Accessible.name: "Marketplace version, then repository version: " + text
            ToolTip.visible: versionHover.containsMouse
            ToolTip.text: "Marketplace version · GitHub repository version"
            MouseArea {
              id: versionHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
            }
          }
        }
      }
      Text {
        text: dialog.pluginDescription
        textFormat: Text.PlainText
        visible: text !== ""
        color: Qt.darker(dialog.foreground, 1.6)
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
      Rectangle {
        visible: dialog.pluginName !== "" && (dialog.reviewNote !== "" || !dialog.marketplaceListed)
        Layout.fillWidth: true
        height: 1
        color: Qt.darker(dialog.foreground, 1.8)
      }
      Text {
        text: dialog.reviewNote
        textFormat: Text.PlainText
        visible: text !== ""
        color: Commons.Color.urgent
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
          visible: dialog.sourceUrl !== ""
          text: "\uf46c Source"
          foreground: dialog.foreground
          accent: Commons.Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(10)
          verticalPadding: Style.space(6)
          onClicked: dialog.sourceRequested(dialog.sourceUrl)
        }

        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          visible: dialog.marketplaceUrl !== ""
          text: "Marketplace"
          foreground: dialog.foreground
          accent: Commons.Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(10)
          verticalPadding: Style.space(6)
          onClicked: dialog.marketplaceRequested(dialog.marketplaceUrl)
        }
        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: "Cancel"
          foreground: dialog.foreground
          accent: Commons.Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.cancelRequested()
        }

        Button {
          bordered: true
          borderSpec: Border.controlSpec("normal", foreground, accent)
          text: dialog.alreadyInstalled ? "Installed" : dialog.confirmText
          enabled: !dialog.alreadyInstalled && dialog.confirmEnabled
          opacity: dialog.alreadyInstalled ? 0.5 : 1
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
