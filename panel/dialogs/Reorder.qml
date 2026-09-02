pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Drag-and-drop bar reorder popup. Widgets are grouped into the three bar
// sections (left/center/right); a row can be dragged within its column to
// reorder, or across columns to relocate. Nothing touches the registry while
// dragging — leftItems/centerItems/rightItems only get reassigned once, on
// drop, so a mid-gesture reassignment never destroys the delegate whose
// MouseArea is holding the mouse grab. Save hands the final per-section id
// order up to Panel.qml, which is the only thing that talks to the registry.
Rectangle {
  id: dialog

  required property bool open
  required property var layout // { left: [{widgetId,label,icon}], center: [...], right: [...] }
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  signal closeRequested
  signal saveRequested(var order)

  readonly property real rowHeight: Style.space(34)

  property var leftItems: []
  property var centerItems: []
  property var rightItems: []

  property bool dragActive: false
  property string dragWidgetId: ""
  property string dragLabel: ""
  property string dragIcon: ""
  property string dragFromSection: ""
  property int dragFromIndex: -1
  property string dragTargetSection: ""
  property int dragTargetIndex: -1

  visible: open
  color: Util.alpha(panelBackground, 0.7)
  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onEscapePressed: dialog.closeRequested()

  function itemsFor(section) {
    if (section === "left") return dialog.leftItems
    if (section === "center") return dialog.centerItems
    return dialog.rightItems
  }

  function setItemsFor(section, arr) {
    if (section === "left") dialog.leftItems = arr
    else if (section === "center") dialog.centerItems = arr
    else dialog.rightItems = arr
  }

  function resetFromLayout() {
    var src = dialog.layout || {}
    dialog.leftItems = Array.isArray(src.left) ? src.left.slice() : []
    dialog.centerItems = Array.isArray(src.center) ? src.center.slice() : []
    dialog.rightItems = Array.isArray(src.right) ? src.right.slice() : []
  }

  onOpenChanged: {
    if (open) {
      dialog.resetFromLayout()
    } else {
      dialog.dragActive = false
      dialog.dragWidgetId = ""
    }
  }

  function columnAt(x) {
    var cols = [
      { name: "left", item: leftColumn },
      { name: "center", item: centerColumn },
      { name: "right", item: rightColumn }
    ]
    for (var i = 0; i < cols.length; i++) {
      var it = cols[i].item
      if (x >= it.x && x < it.x + it.width) return cols[i].name
    }
    return x < centerColumn.x ? "left" : "right"
  }

  function indexAt(section, y) {
    var listItem = section === "left" ? leftRowsList : (section === "center" ? centerRowsList : rightRowsList)
    var origin = listItem.mapToItem(columnsRow, 0, 0)
    var arr = dialog.itemsFor(section)
    var virtualLength = arr.length - (section === dialog.dragFromSection ? 1 : 0)
    var localY = y - origin.y
    var idx = Math.round(localY / dialog.rowHeight)
    return Math.max(0, Math.min(virtualLength, idx))
  }

  // Visual slot for a row that is NOT the one being dragged: its index
  // within "the array with the dragged item removed from its origin and
  // reinserted at the current drag target", computed analytically so other
  // rows only need their own (section, index) — no array rebuild per frame.
  function previewY(section, index, widgetId) {
    var base = index * dialog.rowHeight
    if (!dialog.dragActive || widgetId === dialog.dragWidgetId) return base
    var v = index
    if (section === dialog.dragFromSection && index > dialog.dragFromIndex) v -= 1
    if (section === dialog.dragTargetSection && v >= dialog.dragTargetIndex) v += 1
    return v * dialog.rowHeight
  }

  function startDrag(section, index, widgetId, label, icon, pos) {
    dialog.dragActive = true
    dialog.dragWidgetId = widgetId
    dialog.dragLabel = label
    dialog.dragIcon = icon
    dialog.dragFromSection = section
    dialog.dragFromIndex = index
    dialog.dragTargetSection = section
    dialog.dragTargetIndex = index
    ghost.x = pos.x - ghost.width / 2
    ghost.y = pos.y - ghost.height / 2
  }

  function updateDrag(pos) {
    if (!dialog.dragActive) return
    ghost.x = pos.x - ghost.width / 2
    ghost.y = pos.y - ghost.height / 2
    var section = dialog.columnAt(pos.x)
    dialog.dragTargetSection = section
    dialog.dragTargetIndex = dialog.indexAt(section, pos.y)
  }

  function endDrag() {
    if (dialog.dragActive && dialog.dragWidgetId !== "") {
      var fromArr = dialog.itemsFor(dialog.dragFromSection).slice()
      var draggedItem = fromArr.splice(dialog.dragFromIndex, 1)[0]
      if (draggedItem) {
        if (dialog.dragTargetSection === dialog.dragFromSection) {
          fromArr.splice(dialog.dragTargetIndex, 0, draggedItem)
          dialog.setItemsFor(dialog.dragFromSection, fromArr)
        } else {
          dialog.setItemsFor(dialog.dragFromSection, fromArr)
          var targetArr = dialog.itemsFor(dialog.dragTargetSection).slice()
          targetArr.splice(dialog.dragTargetIndex, 0, draggedItem)
          dialog.setItemsFor(dialog.dragTargetSection, targetArr)
        }
      }
    }
    dialog.dragActive = false
    dialog.dragWidgetId = ""
    dialog.dragFromSection = ""
    dialog.dragFromIndex = -1
    dialog.dragTargetSection = ""
    dialog.dragTargetIndex = -1
  }

  function collectOrder() {
    return {
      left: dialog.leftItems.map(function(it) { return it.widgetId }),
      center: dialog.centerItems.map(function(it) { return it.widgetId }),
      right: dialog.rightItems.map(function(it) { return it.widgetId })
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: dialog.closeRequested()
  }

  Rectangle {
    id: card

    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), Style.space(640))
    height: Math.min(parent.height - Style.space(64), cardContent.implicitHeight + Style.space(36))
    color: dialog.panelBackground
    radius: Style.cornerRadius
    border.color: Style.selectedStateColor(dialog.foreground, Color.accent)
    border.width: 1

    ColumnLayout {
      id: cardContent

      anchors.fill: parent
      anchors.margins: Style.space(18)
      spacing: Style.space(12)

      Text {
        text: "Reorder the bar"
        textFormat: Text.PlainText
        color: dialog.foreground
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        Layout.fillWidth: true
      }

      Text {
        text: "Drag a widget to reorder it, or drag it into another column to move it there. Nothing changes on the bar until you save."
        textFormat: Text.PlainText
        color: Qt.darker(dialog.foreground, 1.6)
        font.family: dialog.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
      }

      Item {
        id: columnsRow
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(
          dialog.leftItems.length, dialog.centerItems.length, dialog.rightItems.length, 1
        ) * dialog.rowHeight + Style.space(28)

        readonly property real columnSpacing: Style.space(10)
        readonly property real columnWidth: (columnsRow.width - columnSpacing * 2) / 3

        ColumnLayout {
          id: leftColumn
          x: 0
          width: columnsRow.columnWidth
          height: parent.height
          spacing: Style.space(6)

          Label {
            text: "Left"
            color: Qt.darker(dialog.foreground, 1.4)
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item {
            id: leftRowsList
            Layout.fillWidth: true
            Layout.preferredHeight: dialog.leftItems.length * dialog.rowHeight

            Repeater {
              model: dialog.leftItems
              delegate: ReorderRow {
                required property var modelData
                required property int index
                width: leftRowsList.width
                height: dialog.rowHeight
                y: dialog.previewY("left", index, modelData.widgetId)
                widgetId: modelData.widgetId
                label: modelData.label
                icon: modelData.icon
                dragging: dialog.dragActive && dialog.dragWidgetId === modelData.widgetId
                foreground: dialog.foreground
                fontFamily: dialog.fontFamily
                onDragPressed: function(pos) {
                  dialog.startDrag("left", index, modelData.widgetId, modelData.label, modelData.icon, pos)
                }
                onDragMoved: function(pos) { dialog.updateDrag(pos) }
                onDragEnded: dialog.endDrag()
                mapTarget: columnsRow
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        ColumnLayout {
          id: centerColumn
          x: leftColumn.width + columnsRow.columnSpacing
          width: columnsRow.columnWidth
          height: parent.height
          spacing: Style.space(6)

          Label {
            text: "Center"
            color: Qt.darker(dialog.foreground, 1.4)
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item {
            id: centerRowsList
            Layout.fillWidth: true
            Layout.preferredHeight: dialog.centerItems.length * dialog.rowHeight

            Repeater {
              model: dialog.centerItems
              delegate: ReorderRow {
                required property var modelData
                required property int index
                width: centerRowsList.width
                height: dialog.rowHeight
                y: dialog.previewY("center", index, modelData.widgetId)
                widgetId: modelData.widgetId
                label: modelData.label
                icon: modelData.icon
                dragging: dialog.dragActive && dialog.dragWidgetId === modelData.widgetId
                foreground: dialog.foreground
                fontFamily: dialog.fontFamily
                onDragPressed: function(pos) {
                  dialog.startDrag("center", index, modelData.widgetId, modelData.label, modelData.icon, pos)
                }
                onDragMoved: function(pos) { dialog.updateDrag(pos) }
                onDragEnded: dialog.endDrag()
                mapTarget: columnsRow
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        ColumnLayout {
          id: rightColumn
          x: (leftColumn.width + columnsRow.columnSpacing) * 2
          width: columnsRow.columnWidth
          height: parent.height
          spacing: Style.space(6)

          Label {
            text: "Right"
            color: Qt.darker(dialog.foreground, 1.4)
            font.family: dialog.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item {
            id: rightRowsList
            Layout.fillWidth: true
            Layout.preferredHeight: dialog.rightItems.length * dialog.rowHeight

            Repeater {
              model: dialog.rightItems
              delegate: ReorderRow {
                required property var modelData
                required property int index
                width: rightRowsList.width
                height: dialog.rowHeight
                y: dialog.previewY("right", index, modelData.widgetId)
                widgetId: modelData.widgetId
                label: modelData.label
                icon: modelData.icon
                dragging: dialog.dragActive && dialog.dragWidgetId === modelData.widgetId
                foreground: dialog.foreground
                fontFamily: dialog.fontFamily
                onDragPressed: function(pos) {
                  dialog.startDrag("right", index, modelData.widgetId, modelData.label, modelData.icon, pos)
                }
                onDragMoved: function(pos) { dialog.updateDrag(pos) }
                onDragEnded: dialog.endDrag()
                mapTarget: columnsRow
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        Rectangle {
          id: ghost
          visible: dialog.dragActive
          z: 10000
          width: Style.space(160)
          height: dialog.rowHeight
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
          color: Style.hoverFillFor(dialog.foreground, Color.accent)
          border.color: Color.accent
          border.width: 1
          opacity: 0.92

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(6)

            Text {
              text: dialog.dragIcon
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              visible: dialog.dragIcon !== ""
            }

            Label {
              text: dialog.dragLabel
              textFormat: Text.PlainText
              color: dialog.foreground
              font.family: dialog.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Label.ElideRight
              Layout.fillWidth: true
            }
          }
        }
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
          onClicked: dialog.closeRequested()
        }

        Button {
          text: "Save"
          foreground: dialog.foreground
          accent: Color.accent
          fontFamily: dialog.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(12)
          verticalPadding: Style.space(6)
          onClicked: dialog.saveRequested(dialog.collectOrder())
        }
      }
    }
  }
}
