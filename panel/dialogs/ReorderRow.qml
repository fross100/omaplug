pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One draggable row inside the Reorder popup. Reports press/move/release in
// `mapTarget`-local coordinates and lets the popup own all reorder state —
// this row never mutates a model itself, so it can be safely left alone
// mid-drag (see Reorder.qml's header comment for why that matters).
Item {
  id: row

  required property string widgetId
  required property string label
  required property string icon
  required property bool dragging
  required property color foreground
  required property string fontFamily
  required property Item mapTarget

  signal dragPressed(var pos)
  signal dragMoved(var pos)
  signal dragEnded

  // Fully hidden (not just dimmed) while dragging: it stays parked at its
  // original index for the duration of the gesture (see Reorder.qml's
  // previewY), and other rows sliding into "the gap it left" during the
  // live preview can land on that exact slot — dimming would show both
  // texts overlapping there. The floating ghost plus the gap in the list
  // are enough feedback without it being visible too.
  opacity: dragging ? 0 : 1
  Behavior on y { enabled: !row.dragging; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
    color: hover.hovered ? Style.hoverFillFor(row.foreground, Color.accent) : "transparent"

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(6)

      Text {
        text: row.icon
        textFormat: Text.PlainText
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        visible: row.icon !== ""
        Layout.preferredWidth: Style.space(18)
      }

      Label {
        text: row.label
        textFormat: Text.PlainText
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Label.ElideRight
        Layout.fillWidth: true
      }
    }

    HoverHandler { id: hover }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      preventStealing: true
      cursorShape: row.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      onPressed: function(mouse) {
        row.dragPressed(mouseArea.mapToItem(row.mapTarget, mouse.x, mouse.y))
      }
      onPositionChanged: function(mouse) {
        if (row.dragging) row.dragMoved(mouseArea.mapToItem(row.mapTarget, mouse.x, mouse.y))
      }
      onReleased: row.dragEnded()
      onCanceled: row.dragEnded()
    }
  }
}
