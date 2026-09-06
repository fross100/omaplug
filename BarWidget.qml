import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "omaplug"

    // The bar's findPanelWidget (Bar.qml) requires open/close/opened on the
    // bar-widget root, and the popout coordinator compares against
    // slot.activeItem — so the widget, not the nested panel, is the identity.
    readonly property bool opened: panelItem ? panelItem.opened === true : false
    readonly property int pendingUpdateCount: panelItem ? (panelItem.pendingUpdateCount || 0) : 0

    function open() { if (panelItem) panelItem.open() }
    function close() { if (panelItem) panelItem.close() }
    function togglePanel() { if (panelItem) panelItem.toggle() }

    // Forwarded so this widget can stand in for the panel as the bar's popout
    // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
    // KeyboardPanel reads popoutSwitchClosing back off its owner.
    readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
    function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

    property var panelItem: null

    function injectPanel() {
        var target = panelLoader.item
        if (!target) return
        panelItem = target
        if ("bar" in target) target.bar = root.bar
        if ("settings" in target) target.settings = root.settings
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    IpcHandler {
        target: "omaplug"

        function refresh(): void { root.broadcast("refresh") }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.opened ? "\udb85\udcd3" : "\udb85\udcd9"
        tooltipText: root.opened ? "Close Plugin Manager" : "Plugin Manager"

        onPressed: function(b) {
            if (b === Qt.LeftButton) root.togglePanel()
        }
    }

    // Small pending-update indicator, independent of the manager's own
    // open/close state so it stays visible whether or not the panel is open.
    Rectangle {
        id: updateBadge
        visible: root.pendingUpdateCount > 0
        anchors.top: button.top
        anchors.right: button.right
        anchors.topMargin: -Style.space(2)
        anchors.rightMargin: -Style.space(2)
        z: 10

        readonly property string countText: root.pendingUpdateCount > 9 ? "9+" : String(root.pendingUpdateCount)

        implicitWidth: Math.max(Style.space(14), badgeLabel.implicitWidth + Style.space(6))
        implicitHeight: Style.space(14)
        radius: height / 2
        color: Color.accent
        border.width: 1
        border.color: root.bar ? root.bar.background : "transparent"

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: updateBadge.countText
            color: "white"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
        }
    }
}
