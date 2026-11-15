import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "omaplug"

    // The bar's findPanelWidget (Bar.qml) requires open/close/opened on the
    // bar-widget root, and the popout coordinator compares against
    // slot.activeItem — so the widget, not the nested panel, is the identity.
    readonly property bool opened: panelItem ? panelItem.opened === true : false
    readonly property int pendingUpdateCount: panelItem ? (panelItem.pendingUpdateCount || 0) : 0

    property var panelItem: null
    // Loading Panel.qml at startup freezes the shell for seconds (issue #48),
    // so the first panel call is queued until the loader has the item.
    property string pendingPanelCall: ""

    function withPanel(call) {
        if (panelItem) {
            panelItem[call]()
            return
        }
        pendingPanelCall = call
        panelLoader.active = true
    }

    function open() { withPanel("open") }
    function close() { if (panelItem) panelItem.close() }
    function togglePanel() { withPanel("toggle") }

    // Forwarded so this widget can stand in for the panel as the bar's popout
    // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
    // KeyboardPanel reads popoutSwitchClosing back off its owner.
    readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
    function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

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

    // Built on first use, or shortly after startup for the update badge and the
    // background auto-check timer; building it at login freezes the shell for
    // seconds (issue #48). Every call forwarded to the panel guards on panelItem.
    Timer {
        id: deferredPanelLoad
        interval: 45000
        running: true
        repeat: false
        onTriggered: panelLoader.active = true
    }

    // A plugin action rewrites shell.json and the bar rebuilds this widget, so
    // the panel that wrote the reopen flag is gone. Load it right away (before
    // the 10s flag expiry) instead of waiting for the deferred timer.
    Process {
        id: reopenPending
        command: ["python3", String(Qt.resolvedUrl("runtime-state.py")).replace(/^file:\/\//, ""), "reopen-pending"]
        running: true
        onExited: function(exitCode) { if (exitCode === 0) panelLoader.active = true }
    }

    Loader {
        id: panelLoader
        active: false
        asynchronous: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
            if (root.pendingPanelCall === "") return
            var call = root.pendingPanelCall
            root.pendingPanelCall = ""
            Qt.callLater(function() { root.withPanel(call) })
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
        z: 10

        readonly property string countText: root.pendingUpdateCount > 9 ? "9+" : String(root.pendingUpdateCount)

        implicitWidth: Math.max(Style.space(14), badgeLabel.implicitWidth + Style.space(6))
        implicitHeight: Style.space(14)
        radius: height / 2
        color: Commons.Color.accent
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
