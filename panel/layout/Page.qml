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
//
// Interaction notes:
// - The dragged chip stays in place as a dimmed placeholder; a thin accent
//   line marks the exact insertion point. Neither changes delegate heights,
//   so the list never shifts under the cursor mid-drag.
// - Plain hover does nothing — only an active drag shows indicators.
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
    if (open) {
      _stayLoaded = true
      // Never inherit a stale drag/selection look from a previous visit:
      // the board always opens in a clean, unselected state.
      cancelDrag()
    }
  }

  focus: true
  Keys.onEscapePressed: {
    if (board.dragId !== "") board.cancelDrag()
  }

  // Active drag state, shared across the three columns.
  property string dragId: ""
  property string dragName: ""
  property string dragFromSection: ""
  property int dragFromIndex: -1
  property string dropSection: ""
  property int dropIndex: -1
  property real ghostX: 0
  property real ghostY: 0

  function startDrag(id, name, section, index, x, y) {
    board.dragId = id
    board.dragName = name
    board.dragFromSection = section
    board.dragFromIndex = index
    board.dropSection = section
    board.dropIndex = index
    board.ghostX = x
    board.ghostY = y
  }

  function moveDrag(section, index, x, y) {
    if (board.dragId === "") return
    board.dropSection = section
    board.dropIndex = index
    board.ghostX = x
    board.ghostY = y
  }

  function endDrag() {
    if (board.dragId === "") return
    var id = board.dragId
    var section = board.dropSection
    var index = board.dropIndex
    var fromSection = board.dragFromSection
    var fromIndex = board.dragFromIndex
    board.dragId = ""
    board.dragName = ""
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
    board.dragName = ""
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
      text: "Drag a widget to reorder — within its section or across sections."
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
          readonly property bool isDropColumn: board.dragId !== "" && board.dropSection === column.section

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
            color: column.isDropColumn
              ? Util.alpha(Color.accent, 0.08)
              : Util.alpha(board.foreground, 0.04)
            border.color: column.isDropColumn
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
              // The board manages its own drop markers; never show the
              // view's own current-item highlight or keep a selection.
              currentIndex: -1
              highlight: null
              keyNavigationEnabled: false

              Component.onCompleted: board.registerList(column.section, sectionList)

              delegate: Item {
                id: chip
                required property var modelData
                required property int index

                readonly property string widgetId: modelData.id
                readonly property string widgetName: modelData.name
                readonly property bool isDragged: board.dragId === widgetId
                // Insertion line sits above this chip.
                readonly property bool showLineAbove: board.dragId !== ""
                  && board.dropSection === column.section
                  && board.dropIndex === index
                // Insertion line sits below the last chip.
                readonly property bool showLineBelow: board.dragId !== ""
                  && board.dropSection === column.section
                  && board.dropIndex === index + 1
                  && index === sectionList.count - 1

                width: sectionList.width
                // Fixed height: the drop line is an overlay and never
                // changes delegate geometry, so the list stays still.
                height: Style.space(34)

                Rectangle {
                  id: chipCard
                  anchors.fill: parent
                  radius: height / 2
                  color: chip.isDragged
                    ? Util.alpha(Color.accent, 0.25)
                    : Style.normalFillFor(board.foreground, Color.accent)
                  border.color: chip.isDragged
                    ? Color.accent
                    : Util.alpha(board.foreground, 0.15)
                  border.width: 1
                  opacity: chip.isDragged ? 0.55 : 1.0

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
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                    }
                  }

                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // Arrow at rest so chips read as a plain list; the hand
                    // only appears while a drag is actually in flight.
                    cursorShape: chipMouse.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
                    acceptedButtons: Qt.LeftButton

                    property real pressX: 0
                    property real pressY: 0
                    property bool dragging: false

                    onPressed: function(mouse) {
                      pressX = mouse.x
                      pressY = mouse.y
                      dragging = false
                    }
                    onPositionChanged: function(mouse) {
                      // Ignore pure hover: a drag starts only while the left
                      // button is held. Without this gate, the first hover
                      // motion trips the threshold (pressX/pressY start at 0)
                      // and a phantom drag follows the cursor uninvited.
                      if (!(mouse.buttons & Qt.LeftButton)) return
                      if (!dragging
                        && (Math.abs(mouse.x - pressX) > 6 || Math.abs(mouse.y - pressY) > 6)) {
                        dragging = true
                        // NOTE: bare `index` — the Repeater context property.
                        // `chip.index` does not resolve and breaks drop math.
                        var start = board.mapFromItem(chip, mouse.x, mouse.y)
                        board.startDrag(chip.widgetId, chip.widgetName, column.section, index, start.x, start.y)
                      }
                      if (dragging) {
                        var p = board.mapFromItem(chip, mouse.x, mouse.y)
                        board.updateDropTarget(p.x, p.y)
                      }
                    }
                    onReleased: {
                      if (dragging) board.endDrag()
                      dragging = false
                    }
                  }
                }

                // Insertion marker: a thin accent line overlaid at the top
                // edge (or bottom edge for the end-of-list slot). Overlay —
                // never affects layout, never shifts siblings.
                Rectangle {
                  visible: chip.showLineAbove
                  anchors.top: parent.top
                  anchors.topMargin: -Style.space(3)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: Style.space(3)
                  radius: height / 2
                  color: Color.accent
                }

                Rectangle {
                  visible: chip.showLineBelow
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: -Style.space(3)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: Style.space(3)
                  radius: height / 2
                  color: Color.accent
                }
              }

              // Empty column still accepts drops: any motion over it targets
              // index 0, release commits the move.
              MouseArea {
                anchors.fill: parent
                visible: sectionList.count === 0
                onPositionChanged: function(mouse) {
                  if (board.dragId === "") return
                  var p = board.mapFromItem(sectionList, mouse.x, mouse.y)
                  board.moveDrag(column.section, 0, p.x, p.y)
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

  // Ghost chip following the cursor during a drag.
  Rectangle {
    id: ghost
    visible: board.dragId !== ""
    width: Math.min(Style.space(200), board.width / 3 - Style.space(16))
    height: Style.space(34)
    radius: height / 2
    color: Util.alpha(Color.accent, 0.85)
    border.color: Color.accent
    border.width: 1
    x: board.ghostX - width / 2
    y: board.ghostY - height / 2
    z: 100
    opacity: 0.9

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      maximumLineCount: 1
      text: board.dragName
      textFormat: Text.PlainText
      color: Color.background
      font.family: board.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  function updateDropTarget(x, y) {
    if (board.dragId === "") return
    var names = ["left", "center", "right"]
    for (var i = 0; i < names.length; i++) {
      var list = board._lists[names[i]]
      if (!list) continue
      var p = board.mapToItem(list, x, y)
      if (p.x < -Style.space(20) || p.y < -Style.space(40) || p.x > list.width + Style.space(20)
        || p.y > list.height + Style.space(40)) continue
      var idx = list.indexAt(list.width / 2, Math.max(0, Math.min(list.height - 1, p.y)))
      board.moveDrag(names[i], idx === -1 ? list.count : idx, x, y)
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

  // Position tracker covering gaps between chips and column padding.
  // NoButton: tracks motion without stealing press/release from chips.
  // Release always lands on the chip holding the mouse grab, so its own
  // onReleased commits the drop no matter where the cursor ends up.
  MouseArea {
    anchors.fill: parent
    enabled: board.dragId !== ""
    acceptedButtons: Qt.NoButton
    hoverEnabled: true
    z: 50
    onPositionChanged: function(mouse) {
      board.updateDropTarget(mouse.x, mouse.y)
    }
  }
}
