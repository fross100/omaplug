pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Presentation.js" as Presentation
import "../plugin" as Plugin

Rectangle {
  id: page

  required property bool open
  required property real topInset
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  required property var rows
  required property var updateStates
  required property var marketplaceMap
  required property var localCommits
  required property var incomingCommits
  required property bool marketplaceFetching
  required property bool marketplaceFetchFailed
  required property bool checking
  required property bool updateRunning
  required property bool updatingAll
  required property int pendingCount
  required property int bulkCount
  required property string bulkLabel
  required property bool bulkReady
  required property string summary

  required property var iconFor
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

  function verificationText(id, sourceKey) {
    if (marketplaceFetching) return "Checking verification…"
    if (marketplaceFetchFailed) return "Verification unavailable"
    var entry = marketplaceMap[String(id)]
    if (updateStates[String(sourceKey)] === "UPDATE")
      return Presentation.commitVerification(entry, incomingCommits[String(sourceKey)])
    if (entry) {
      var local = String((localCommits || {})[String(sourceKey)] || "")
      var snapshot = String(entry.snapshotCommit || "")
      if (entry.verified === true && snapshot !== "" && local !== "" && snapshot === local) return "Verified"
      if (entry.verified === true && snapshot !== "" && local !== "" && snapshot !== local) return "Update Unverified"
      if (entry.snapshotStatus === "update-unverified") return "Update Unverified"
      return "Unverified"
    }
    if (marketplaceFetching) return "Checking verification…"
    if (marketplaceFetchFailed) return "Verification unavailable"
    return "Not listed"
  }

  function verificationColor(id, sourceKey) {
    var entry = marketplaceMap[String(id)]
    var status = verificationText(id, sourceKey)
    if (status === "Verified") return Color.accent
    if (status === "Update Unverified")
      return Qt.hsla(0.12, 0.75, 0.55, 1)
    return Qt.darker(foreground, 2.0)
  }

  // Swallows clicks that land in a gap between controls (margins, spacing,
  // below a short list) so they don't fall through to whatever is rendered
  // behind this page - the main plugin list is still visible/enabled there.
  // Declared before the Loader so its buttons/rows still take priority for
  // clicks that actually land on them; same pattern as the dialogs'
  // full-page MouseArea (panel/dialogs/Confirm.qml, Review.qml).
  MouseArea {
    anchors.fill: parent
    onClicked: {}
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
              height: Math.max(Style.space(72), row.implicitHeight + Style.space(24))
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
                  clip: true
                  color: Presentation.iconColor(updateRow.modelData.name)

                  Plugin.IconGlyph {
                    text: page.iconFor(updateRow.modelData.id) || updateRow.modelData.name.trim().charAt(0).toUpperCase()
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  Layout.minimumWidth: 0
                  Layout.maximumHeight: implicitHeight
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(2)

                  Item {
                    id: updateNameRow
                    Layout.fillWidth: true
                    implicitHeight: Math.max(updateName.implicitHeight, verificationBadge.implicitHeight)

                    Label {
                      id: updateName
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(implicitWidth, Math.max(0, updateNameRow.width - verificationBadge.width - Style.space(8)))
                      text: updateRow.modelData.name
                      textFormat: Text.PlainText
                      color: page.foreground
                      font.family: page.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Label.ElideRight
                    }

                    Rectangle {
                      id: verificationBadge
                      anchors.left: updateName.right
                      anchors.leftMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      readonly property bool verified: page.verificationText(updateRow.modelData.id, updateRow.modelData.sourceKey) === "Verified"
                      readonly property bool updateUnverified: page.verificationText(updateRow.modelData.id, updateRow.modelData.sourceKey) === "Update Unverified"
                      implicitWidth: verificationLabel.implicitWidth + Style.space(10)
                      implicitHeight: Style.space(16)
                      radius: height / 2
                      color: updateUnverified ? Qt.rgba(0.85, 0.65, 0.13, 0.18)
                        : verified ? Util.alpha(Color.accent, 0.18) : Util.alpha(page.foreground, 0.08)

                      Label {
                        id: verificationLabel
                        anchors.centerIn: parent
                        text: (verificationBadge.updateUnverified ? "\uf071 " : verificationBadge.verified ? "\uf058 " : "")
                          + page.verificationText(updateRow.modelData.id, updateRow.modelData.sourceKey)
                        textFormat: Text.PlainText
                        color: page.verificationColor(updateRow.modelData.id, updateRow.modelData.sourceKey)
                        font.family: page.fontFamily
                        font.pixelSize: Style.font.caption - 1
                      }
                    }
                  }

                  Label {
                    text: page.statusText(updateRow.modelData.sourceKey)
                    textFormat: Text.PlainText
                    color: page.statusColor(updateRow.modelData.sourceKey)
                    font.family: page.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.fillWidth: true
                    elide: Label.ElideRight
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
            Layout.maximumHeight: implicitHeight

            Label {
              text: page.checking
                ? (page.pendingCount > 0
                    ? "Checking… " + page.pendingCount + " update" + (page.pendingCount > 1 ? "s" : "") + " found"
                    : "Checking…")
                : (page.pendingCount > 0
                    ? page.pendingCount + " update" + (page.pendingCount > 1 ? "s" : "") + " available"
                    : "No updates available")
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
              text: page.updatingAll ? "Updating…" : page.bulkLabel
              tooltipText: !page.bulkReady ? "Checking verification…"
                : page.bulkCount === 0 ? "No updates match your selected scope"
                : page.bulkCount + " update(s) match your selected scope"
              enabled: page.bulkCount > 0 && page.bulkReady && !page.checking && !page.updateRunning
              // Always rendered. A button that disappears whenever there is
              // nothing to do leaves no trace that the feature exists; the
              // enabled binding above already says when it is actionable.
              visible: true
              foreground: page.foreground
              accent: Color.accent
              fontFamily: page.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(3)
              onClicked: page.updateAllRequested()
            }
          }
        }
      }
    }
  }
}
