pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: page

  required property bool open
  required property real topInset
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  required property var rows
  required property var updateStates
  required property bool checking
  required property bool updateRunning
  required property bool updatingAll
  required property int pendingCount
  required property string summary

  required property var iconFor
  required property var iconColorFor
  required property var whatsNewUrlFor

  signal closeRequested
  signal tabRequested(int direction)
  signal openUrlRequested(string url)
  signal updatePluginRequested(string sourceKey)
  signal updateAllRequested

  visible: open
  color: panelBackground

  // Preserve scroll and delegate state after the page has been opened once.
  property bool _stayLoaded: false
  onOpenChanged: {
    if (open) _stayLoaded = true
  }

  function statusText(key) {
    var state = updateStates[key]
    if (!state) return "Pending"
    if (state === "CHECK") return "Checking…"
    if (state === "CURRENT") return "Up to date"
    if (state === "UPDATE") return "Update available"
    if (state === "LOCAL_CHANGES") return "Local changes"
    if (state === "LOCAL") return "Local plugin"
    if (state === "ERROR") return "Error"
    return state
  }

  function statusColor(key) {
    var state = updateStates[key]
    if (state === "UPDATE") return Style.selectedStateColor(foreground, Color.accent)
    if (state === "ERROR") return Color.urgent
    if (state === "CURRENT") return Qt.darker(foreground, 1.6)
    if (state === "LOCAL_CHANGES" || state === "LOCAL") return Qt.darker(foreground, 1.5)
    return Qt.darker(foreground, 1.4)
  }

  Loader {
    anchors.fill: parent
    active: page.open || page._stayLoaded

    sourceComponent: Component {
      Item {
        PanelKeyCatcher {
          anchors.fill: parent
          onCloseRequested: page.closeRequested()
          onTabRequested: function(direction) { page.tabRequested(direction) }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          anchors.topMargin: page.topInset
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Label {
              text: "Check for updates"
              color: page.foreground
              font.family: page.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.fillWidth: true
            }

            Button {
              text: "Back"
              foreground: page.foreground
              accent: Color.accent
              fontFamily: page.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(5)
              onClicked: page.closeRequested()
            }
          }

          Rectangle {
            id: checkProgress
            visible: page.checking
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            radius: 1.5
            color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.15)
            clip: true

            Rectangle {
              id: checkProgressChunk
              width: checkProgress.width * 0.4
              height: checkProgress.height
              radius: checkProgress.radius
              color: Style.selectedStateColor(page.foreground, Color.accent)

              NumberAnimation on x {
                running: page.checking
                loops: Animation.Infinite
                from: -checkProgressChunk.width
                to: checkProgress.width
                duration: 1100
                easing.type: Easing.InOutQuad
              }
            }
          }

          ListView {
            id: updateList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(4)
            model: page.rows
            ScrollBar.vertical: ScrollBar {
              policy: ScrollBar.AsNeeded
              implicitWidth: Style.space(6)
              contentItem: Rectangle {
                implicitWidth: Style.space(6)
                implicitHeight: Style.space(6)
                radius: width / 2
                color: Util.alpha(page.foreground, 0.45)
              }
            }

            delegate: Rectangle {
              id: updateRow

              required property var modelData
              width: updateList.width
              height: Math.max(Style.space(52), row.implicitHeight + Style.space(16))
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
              color: hover.hovered
                ? Style.hoverFillFor(page.foreground, Color.accent)
                : "transparent"

              RowLayout {
                id: row
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.topMargin: Style.space(8)
                anchors.rightMargin: Style.space(10)
                anchors.bottomMargin: Style.space(12)
                spacing: Style.space(10)

                Rectangle {
                  id: updateIcon
                  Layout.preferredWidth: Style.space(28)
                  Layout.preferredHeight: Layout.preferredWidth
                  radius: 6
                  color: page.iconColorFor(updateRow.modelData.name)

                  Text {
                    anchors.centerIn: parent
                    text: page.iconFor(updateRow.modelData.id) || updateRow.modelData.name.trim().charAt(0).toUpperCase()
                    textFormat: Text.PlainText
                    color: "white"
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(2)

                  Label {
                    text: updateRow.modelData.name
                    textFormat: Text.PlainText
                    color: page.foreground
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Label.ElideRight
                  }

                  Label {
                    text: page.statusText(updateRow.modelData.sourceKey)
                    textFormat: Text.PlainText
                    color: page.statusColor(updateRow.modelData.sourceKey)
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: whatsNewLink
                    readonly property string url: page.whatsNewUrlFor(updateRow.modelData.sourceKey, updateRow.modelData.id)
                    visible: page.updateStates[String(updateRow.modelData.sourceKey)] === "UPDATE" && url !== ""
                    text: "What's new ↗"
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: whatsNewLinkHover.hovered
                    ToolTip.text: url
                    ToolTip.visible: whatsNewLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: whatsNewLinkHover
                      cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: page.openUrlRequested(whatsNewLink.url)
                    }
                  }
                }

                Item {
                  id: checkRing
                  visible: page.updateStates[updateRow.modelData.sourceKey] === "CHECK"
                    || page.updateStates[updateRow.modelData.sourceKey] === undefined
                  Layout.alignment: Qt.AlignVCenter
                  Layout.preferredWidth: Style.space(18)
                  Layout.preferredHeight: Style.space(18)

                  Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.18)
                  }

                  Item {
                    id: checkRingArc
                    anchors.fill: parent
                    visible: page.updateStates[updateRow.modelData.sourceKey] === "CHECK"
                      || page.updateStates[updateRow.modelData.sourceKey] === undefined

                    RotationAnimation on rotation {
                      running: checkRingArc.visible
                      loops: Animation.Infinite
                      from: 0
                      to: 360
                      duration: 900
                    }

                    Canvas {
                      anchors.fill: parent
                      onPaint: {
                        var context = getContext("2d")
                        context.reset()
                        context.strokeStyle = Style.selectedStateColor(page.foreground, Color.accent)
                        context.lineWidth = 2
                        context.lineCap = "round"
                        var radius = width / 2 - 2
                        context.beginPath()
                        context.arc(width / 2, height / 2, radius, -Math.PI / 2, Math.PI / 3, false)
                        context.stroke()
                      }
                    }
                  }
                }

                Button {
                  id: statusButton

                  readonly property string updateState: String(page.updateStates[updateRow.modelData.sourceKey] || "")
                  visible: updateState === "CURRENT" || updateState === "UPDATE" || updateState === "LOCAL_CHANGES"
                    || updateState === "LOCAL" || updateState === "ERROR"
                  text: updateState === "UPDATE" ? "\uEAC2 UPDATE" : "\uF00C"
                  enabled: updateState === "UPDATE" && !page.updateRunning
                  onClicked: page.updatePluginRequested(updateRow.modelData.sourceKey)
                  bordered: true
                  borderSpec: statusButton.hot ? Border.none()
                    : Border.controlSpec("normal", statusButton.foreground, Color.accent)
                  foreground: updateState === "ERROR" ? Color.urgent : page.foreground
                  accent: Color.accent
                  fontFamily: page.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(3)
                  Layout.alignment: Qt.AlignVCenter
                }
              }

              HoverHandler {
                id: hover
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                height: 1
                color: Qt.rgba(page.foreground.r, page.foreground.g, page.foreground.b, 0.12)
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Label {
              text: page.pendingCount > 0
                ? page.pendingCount + " update" + (page.pendingCount > 1 ? "s" : "") + " available"
                : (page.checking ? "Checking…" : "No updates available")
              color: Qt.darker(page.foreground, 1.5)
              font.family: page.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Label {
              visible: page.summary !== ""
              text: page.summary
              textFormat: Text.PlainText
              color: Style.selectedStateColor(page.foreground, Color.accent)
              font.family: page.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item {
              Layout.fillWidth: true
            }

            Button {
              text: page.updatingAll ? "Updating all…" : "Update all"
              enabled: page.pendingCount > 0 && !page.checking && !page.updateRunning
              visible: page.pendingCount > 0
              foreground: page.foreground
              accent: Color.accent
              fontFamily: page.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: page.updateAllRequested()
            }
          }
        }
      }
    }
  }
}
