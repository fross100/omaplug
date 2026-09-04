pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Pre-install review: shown between "Install" and `omarchy plugin add`. While
// review-helper.sh runs it reports the stage; afterwards it shows the verdict,
// the summary, and the findings. The user always makes the final call — the
// verdict changes the wording and colour of the install button, never whether
// it exists. A failed review (no claude, timeout, budget) offers an explicit
// "Install without review" so the feature never becomes a lockout.
//
// This is its own layer-shell window rather than a dialog inside the panel:
// the panel is a small popout and a review with findings does not fit in it,
// and a review is worth more screen than a bar popup gets. The window is
// exactly the card, centred on the focused monitor, above everything, and
// takes keyboard focus only when clicked — a review can take minutes, and the
// desktop stays usable underneath it in the meantime.
Item {
  id: dialog

  width: 0
  height: 0
  visible: false

  required property bool open
  required property bool running
  required property bool failed
  required property string stage
  required property string errorText
  required property var review
  required property string url
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  signal cancelRequested
  signal retryRequested
  signal installRequested

  readonly property bool hasReview: review !== null && typeof review === "object"
  readonly property string verdict: hasReview ? String(review.verdict) : ""
  readonly property color cautionColor: Qt.hsla(0.12, 0.75, 0.55, 1)
  readonly property color dimForeground: Qt.darker(foreground, 1.6)

  function verdictColor() {
    if (verdict === "safe") return Color.accent
    if (verdict === "danger") return Color.urgent
    return cautionColor
  }

  function verdictLabel() {
    if (verdict === "safe") return "SAFE"
    if (verdict === "danger") return "DANGER"
    if (verdict === "caution") return "CAUTION"
    return ""
  }

  function severityColor(s) {
    if (s === "critical" || s === "high") return Color.urgent
    if (s === "medium") return cautionColor
    return dimForeground
  }

  function installLabel() {
    if (running) return "Reviewing…"
    if (failed) return "Install without review"
    if (verdict === "safe") return "Install"
    return "Install anyway"
  }

  function metaLine() {
    if (!hasReview) return ""
    var parts = []
    if (review.commit) parts.push("commit " + String(review.commit).substring(0, 7))
    if (review.model) parts.push(String(review.model))
    if (review.files) parts.push(review.files + " files" + (review.truncated ? " (some skipped)" : ""))
    if (review.costUsd > 0) parts.push("$" + Number(review.costUsd).toFixed(2))
    return parts.join(" · ")
  }

  // The monitor the user is looking at, resolved when the window opens.
  property var targetScreen: null
  function focusedScreen() {
    var screens = Quickshell.screens
    var monitor = Hyprland.focusedMonitor
    if (monitor)
      for (var i = 0; i < screens.length; i++)
        if (screens[i] && screens[i].name === monitor.name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  onOpenChanged: if (open) targetScreen = focusedScreen()

  PanelWindow {
    id: win

    visible: dialog.open
    screen: dialog.targetScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omaplug-review"
    WlrLayershell.layer: WlrLayer.Overlay
    // A freshly mapped overlay surface that asks for on-demand focus gets the
    // keyboard at once, and a review can open while the user is mid-sentence
    // somewhere else. So no keyboard until the card is clicked; that is what
    // enables Escape.
    property bool wantsKeys: false
    WlrLayershell.keyboardFocus: dialog.open && wantsKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onVisibleChanged: if (!visible) wantsKeys = false

    // The surface is the card and nothing else, so clicks beside it land on
    // whatever is underneath. Centred explicitly through the margins: an
    // unanchored layer surface is not reliably centred by the compositor.
    readonly property real screenW: screen ? screen.width : 1920
    readonly property real screenH: screen ? screen.height : 1080
    implicitWidth: card.width
    implicitHeight: card.height
    anchors { top: true; left: true }
    margins {
      top: Math.max(0, Math.round((win.screenH - card.height) / 2))
      left: Math.max(0, Math.round((win.screenW - card.width) / 2))
    }

    Rectangle {
      id: card

      // As big as the review needs, up to most of the monitor: a review is
      // the most important thing on screen while it is up. Width is a share
      // of the monitor so a 4K display gets a readable column, not a strip.
      width: Math.round(Math.max(Math.min(win.screenW * 0.42, Style.space(1500)), Math.min(win.screenW - Style.space(80), Style.space(640))))
      height: Math.round(Math.min(content.implicitHeight + Style.space(48), win.screenH * 0.9))
      color: dialog.panelBackground
      radius: Style.cornerRadius
      border.color: dialog.hasReview ? dialog.verdictColor()
        : Style.selectedStateColor(dialog.foreground, Color.accent)
      border.width: 1

      MouseArea {
        anchors.fill: parent
        onClicked: {
          win.wantsKeys = true
          keyCatcher.forceActiveFocus()
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: dialog.cancelRequested()
      }

      ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(12)

        // --------------------------------------------------------- header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: dialog.running ? "Reviewing plugin"
              : (dialog.failed ? "Review unavailable" : "Review result")
            textFormat: Text.PlainText
            color: dialog.foreground
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
          }

          Rectangle {
            visible: dialog.hasReview
            radius: Style.space(9)
            color: Util.alpha(dialog.verdictColor(), 0.18)
            border.color: dialog.verdictColor()
            border.width: 1
            implicitWidth: verdictText.implicitWidth + Style.space(16)
            implicitHeight: verdictText.implicitHeight + Style.space(6)

            Text {
              id: verdictText
              anchors.centerIn: parent
              text: dialog.verdictLabel()
              textFormat: Text.PlainText
              color: dialog.verdictColor()
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Text {
          text: dialog.url
          textFormat: Text.PlainText
          color: dialog.dimForeground
          font.family: dialog.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
          elide: Text.ElideMiddle
        }

        // ----------------------------------------------------------- body
        // Sized to its content; only if a review is taller than the monitor
        // does this become a scroll area, with the buttons still pinned.
        Flickable {
          id: body

          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: bodyColumn.implicitHeight
          Layout.minimumHeight: Math.min(bodyColumn.implicitHeight, Style.space(120))
          implicitHeight: bodyColumn.implicitHeight
          contentWidth: width
          contentHeight: bodyColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          ScrollBar.vertical: ScrollBar {
            policy: body.contentHeight > body.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          }

          ColumnLayout {
            id: bodyColumn
            width: body.width - (body.contentHeight > body.height + 1 ? Style.space(14) : 0)
            spacing: Style.space(10)

            // ------------------------------------------------------- running
            Rectangle {
              visible: dialog.running
              Layout.fillWidth: true
              Layout.preferredHeight: 3
              radius: 1.5
              color: Util.alpha(dialog.foreground, 0.15)
              clip: true

              Rectangle {
                id: sweep
                width: parent.width * 0.3
                height: parent.height
                radius: parent.radius
                color: Color.accent

                SequentialAnimation on x {
                  running: dialog.running && win.visible
                  loops: Animation.Infinite
                  NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1400; easing.type: Easing.InOutQuad }
                }
              }
            }

            Text {
              visible: dialog.running
              text: dialog.stage
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dialog.running
              text: "The reviewer reads the repository with no tools and no ability to act on it, then answers with a verdict. Nothing is installed until you confirm. You can keep working — this window stays on top."
              textFormat: Text.PlainText
              color: dialog.dimForeground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            // -------------------------------------------------------- failed
            Text {
              visible: dialog.failed && !dialog.running
              text: dialog.errorText !== "" ? dialog.errorText : "The review could not run."
              textFormat: Text.PlainText
              color: Color.urgent
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dialog.failed && !dialog.running
              text: "You can retry, or install without a review — in which case read the code yourself before enabling it."
              textFormat: Text.PlainText
              color: dialog.dimForeground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            // -------------------------------------------------------- result
            Text {
              visible: dialog.hasReview
              text: dialog.hasReview ? String(dialog.review.summary) : ""
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.body
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dialog.hasReview && dialog.review.promptInjection === true
              text: "This repository contains text aimed at the reviewer. Treat everything it says about itself as suspect."
              textFormat: Text.PlainText
              color: Color.urgent
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dialog.hasReview && dialog.review.capabilities.length > 0
              text: dialog.hasReview ? "Can: " + dialog.review.capabilities.join(" · ") : ""
              textFormat: Text.PlainText
              color: dialog.dimForeground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }

            Text {
              visible: dialog.hasReview && dialog.review.findings.length > 0
              text: dialog.hasReview ? dialog.review.findings.length + (dialog.review.findings.length === 1 ? " finding" : " findings") : ""
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.topMargin: Style.space(6)
            }

            Repeater {
              model: dialog.hasReview ? dialog.review.findings : []

              delegate: ColumnLayout {
                id: finding
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    text: String(finding.modelData.severity).toUpperCase()
                    textFormat: Text.PlainText
                    color: dialog.severityColor(finding.modelData.severity)
                    font.family: dialog.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    Layout.alignment: Qt.AlignTop
                  }

                  Text {
                    text: String(finding.modelData.title)
                    textFormat: Text.PlainText
                    color: dialog.foreground
                    font.family: dialog.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                  }
                }

                Text {
                  visible: String(finding.modelData.file) !== ""
                  text: String(finding.modelData.file)
                  textFormat: Text.PlainText
                  color: dialog.dimForeground
                  font.family: dialog.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                  elide: Text.ElideMiddle
                }

                Text {
                  text: String(finding.modelData.detail)
                  textFormat: Text.PlainText
                  color: Qt.darker(dialog.foreground, 1.25)
                  font.family: dialog.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              visible: dialog.hasReview
              text: dialog.metaLine()
              textFormat: Text.PlainText
              color: dialog.dimForeground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
              Layout.topMargin: Style.space(6)
              elide: Text.ElideRight
            }

            Text {
              visible: dialog.hasReview
              text: "Installed plugins stay disabled until you enable them. The installed commit is checked against the reviewed one."
              textFormat: Text.PlainText
              color: dialog.dimForeground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.caption
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }
          }
        }

        // -------------------------------------------------------- buttons
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)

          Item { Layout.fillWidth: true }

          Button {
            text: "Cancel"
            foreground: dialog.foreground
            accent: Color.accent
            fontFamily: dialog.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(7)
            onClicked: dialog.cancelRequested()
          }

          Button {
            visible: dialog.failed && !dialog.running
            text: "Retry"
            foreground: dialog.foreground
            accent: Color.accent
            fontFamily: dialog.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(7)
            onClicked: dialog.retryRequested()
          }

          Button {
            text: dialog.installLabel()
            enabled: !dialog.running
            bordered: dialog.failed || dialog.verdict === "danger"
            foreground: dialog.foreground
            accent: dialog.verdict === "danger" ? Color.urgent
              : (dialog.failed || dialog.verdict === "caution" ? dialog.cautionColor : Color.accent)
            fontFamily: dialog.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(14)
            verticalPadding: Style.space(7)
            onClicked: dialog.installRequested()
          }
        }
      }
    }
  }
}
