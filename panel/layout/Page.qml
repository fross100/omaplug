pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Bar-layout board: the three bar sections side by side, each showing its
// widgets in live order. Drag a chip within a column to reorder, or across
// columns to move sections. Every drop calls back with (id, section, index)
// and the owner applies it with `omarchy bar move`, so the bar follows.
Rectangle {
  id: board

  required property bool open
  required property var sections
  required property color foreground
  required property string fontFamily
  required property color panelBackground

  signal closeRequested
  signal dropRequested(string pluginId, string section, int index)

  visible: open
  color: panelBackground

  property bool _stayLoaded: false
  onOpenChanged: {
    if (open) _stayLoaded = true
  }

  // Active drag state, shared across the three columns.
  property string dragId: ""
  property string dragFromSection: ""
  property int dragFromIndex: -1
  property string dropSection: ""
  property int dropIndex: -1

  function startDrag(id, section, index) {
    board.dragId = id
    board.dragFromSection = section
    board.dragFromIndex = index
    board.dropSection = section
    board.dropIndex = index
  }

  function moveDrag(section, index) {
    if (board.dragId === "") return
    board.dropSection = section
    board.dropIndex = index
  }

  function endDrag() {
    if (board.dragId === "") return
    var id = board.dragId
    var section = board.dropSection
    var index = board.dropIndex
    var fromSection = board.dragFromSection
    var fromIndex = board.dragFromIndex
    board.dragId = ""
    board.dragFromSection = ""
    board.dragFromIndex = -1
    board.dropSection = ""
    board.dropIndex = -1
    // No-op when dropped back where it started.
    if (section === fromSection && (index === fromIndex || index === fromIndex + 1)) return
    // Account for the removal shift when moving down within one column.
    var target = (section === fromSection && index > fromIndex) ? index - 1 : index
    board.dropRequested(id, section, target)
  }

  function cancelDrag() {
    board.dragId = ""
    board.dragFromSection = ""
    board.dragFromIndex = -1
    board.dropSection = ""
    board.dropIndex = -1
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Label {
        text: "Bar Layout"
        color: board.foreground
        font.family: board.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        Layout.fillWidth: true
      }

      Button {
        text: "Back"
        tooltipText: "Back to plugin list"
        bordered: true
        foreground: board.foreground
        accent: Color.accent
        fontFamily: board.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(10)
        verticalPadding: Style.space(5)
        onClicked: board.closeRequested()
      }
    }

    Label {
      text: "Drag widgets within or across sections to reorder the bar."
      textFormat: Text.PlainText
      color: Qt.darker(board.foreground, 1.5)
      font.family: board.fontFamily
      font.pixelSize: Style.font.bodySmall
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(8)

      Repeater {
        model: board.sections

        ColumnLayout {
          id: column
          required property var modelData

          readonly property string section: modelData.section
          readonly property var entries: modelData.entries

          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(6)

          Label {
            text: column.section.toUpperCase()
            color: board.foreground
            font.family: board.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
            color: board.dropSection === column.section && board.dragId !== ""
              ? Util.alpha(Color.accent, 0.08)
              : Util.alpha(board.foreground, 0.04)
            border.color: board.dropSection === column.section && board.dragId !== ""
              ? Util.alpha(Color.accent, 0.5)
              : Util.alpha(board.foreground, 0.12)
            border.width: 1

            ListView {
              id: sectionList
              anchors.fill: parent
              anchors.margins: Style.space(6)
              clip: true
              spacing: Style.space(4)
              model: column.entries

              Component.onCompleted: board.registerList(column.section, sectionList)

              delegate: Item {
                id: chip
                required property var modelData
                required property int index

                readonly property string widgetId: modelData.id
                readonly property string widgetName: modelData.name
                readonly property bool isDragged: board.dragId === widgetId
                readonly property bool isDropBefore: board.dragId !== ""
                  && board.dropSection === column.section
                  && board.dropIndex === chip.index
                readonly property bool isDropAfter: board.dragId !== ""
                  && board.dropSection === column.section
                  && board.dropIndex === chip.index + 1
                  && chip.index === sectionList.count - 1

                width: sectionList.width
                height: chipCard.height + (isDropBefore ? Style.space(30) : 0) + (isDropAfter ? Style.space(30) : 0)

                // Drop indicator above the chip.
                Rectangle {
                  visible: chip.isDropBefore
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: Style.space(26)
                  radius: height / 2
                  color: Util.alpha(Color.accent, 0.25)
                }

                Rectangle {
                  id: chipCard
                  anchors.left: parent.left
                  anchors.right: parent.right
                  y: chip.isDropBefore ? Style.space(30) : 0
                  height: Style.space(34)
                  radius: height / 2
                  color: chip.isDragged
                    ? Util.alpha(Color.accent, 0.3)
                    : Style.normalFillFor(board.foreground, Color.accent)
                  border.color: chip.isDragged
                    ? Color.accent
                    : Util.alpha(board.foreground, 0.15)
                  border.width: 1
                  opacity: chip.isDragged ? 0.7 : 1.0

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(6)

                    Text {
                      text: "⋮⋮"
                      color: Qt.darker(board.foreground, 1.4)
                      font.family: board.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                      text: chip.widgetName
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      maximumLineCount: 1
                      color: board.foreground
                      font.family: board.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: chip.isDragged
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    acceptedButtons: Qt.LeftButton
                    drag.target: dragProxy
                    drag.axis: Drag.XAndYAxis

                    property int pressX: 0
                    property int pressY: 0
                    property bool dragging: false

                    onPressed: function(mouse) {
                      pressX = mouse.x
                      pressY = mouse.y
                      dragging = false
                    }
                    onPositionChanged: function(mouse) {
                      if (!dragging
                        && (Math.abs(mouse.x - pressX) > 6 || Math.abs(mouse.y - pressY) > 6)) {
                        dragging = true
                        board.startDrag(chip.widgetId, column.section, chip.index)
                      }
                      if (dragging) {
                        var p = chip.mapToItem(board, mouse.x, mouse.y)
                        board.updateDropTarget(p.x, p.y)
                      }
                    }
                    onReleased: {
                      if (dragging) board.endDrag()
                      dragging = false
                    }
                  }
                }

                // Drop indicator below the last chip.
                Rectangle {
                  visible: chip.isDropAfter
                  anchors.bottom: parent.bottom
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: Style.space(26)
                  radius: height / 2
                  color: Util.alpha(Color.accent, 0.25)
                }
              }

              // Empty column still accepts drops.
              MouseArea {
                anchors.fill: parent
                visible: sectionList.count === 0
                onPressed: function(mouse) {
                  if (board.dragId !== "") board.moveDrag(column.section, 0)
                }
                onReleased: {
                  if (board.dragId !== "") board.endDrag()
                }
              }
            }
          }
        }
      }
    }
  }

  // Floating ghost following the cursor during a drag.
  Rectangle {
    id: dragProxy
    visible: false
    width: 0
    height: 0
  }

  function updateDropTarget(x, y) {
    if (board.dragId === "") return
    var names = ["left", "center", "right"]
    for (var i = 0; i < names.length; i++) {
      var list = board._lists[names[i]]
      if (!list) continue
      var p = board.mapToItem(list, x, y)
      if (p.x < 0 || p.y < -Style.space(40) || p.x > list.width
        || p.y > list.height + Style.space(40)) continue
      var idx = list.indexAt(list.width / 2, Math.max(0, Math.min(list.height - 1, p.y)))
      board.moveDrag(names[i], idx === -1 ? list.count : idx)
      return
    }
  }

  property var _lists: ({})

  function registerList(section, list) {
    var next = {}
    for (var k in board._lists) next[k] = board._lists[k]
    next[section] = list
    board._lists = next
  }
}
