pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: page
  required property bool open
  required property real topInset
  required property color foreground
  required property string fontFamily
  required property string pluginVersion
  required property color panelBackground
  required property bool menuEnabled
  required property bool menuBusy
  required property string menuStatus
  required property bool autoCheckEnabled
  required property real autoCheckIntervalHours
  required property bool settingsBusy
  required property string bulkUpdateScope

  signal closeRequested
  signal menuEnabledRequested(bool value)
  signal autoCheckEnabledRequested(bool value)
  signal autoCheckIntervalRequested(int hours)
  signal bulkUpdateScopeRequested(string value)
  signal openUrlRequested(string url)

  visible: open
  onOpenChanged: if (open) settingsKeys.forceActiveFocus()

  MouseArea { anchors.fill: parent }
  PanelKeyCatcher {
    id: settingsKeys
    blocked: updateScopeDropdown.popupOpen
    anchors.fill: parent
    onCloseRequested: page.closeRequested()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    anchors.topMargin: page.topInset
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      Label {
        text: "Settings"
        Layout.fillWidth: true
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Button {
        text: "Back"
        foreground: page.foreground
        accent: Commons.Color.accent
        fontFamily: page.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: page.closeRequested()
      }
    }

    Toggle {
      Layout.fillWidth: true
      label: "Show Plugin Manager in Omarchy menu"
      description: "Find Omaplug in the Omarchy menu. Keep the plugin enabled to open it."
      checked: page.menuEnabled
      enabled: !page.menuBusy
      foreground: page.foreground
      accent: Commons.Color.accent
      fontFamily: page.fontFamily
      onClicked: page.menuEnabledRequested(!page.menuEnabled)
    }
    Label {
      Layout.fillWidth: true
      visible: text !== ""
      text: page.menuBusy ? "Updating menu setting…" : page.menuStatus
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: page.foreground
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }
    Toggle {
      Layout.fillWidth: true
      label: "Auto-check for updates"
      description: "Check for plugin updates in the background."
      checked: page.autoCheckEnabled
      enabled: !page.settingsBusy
      foreground: page.foreground
      accent: Commons.Color.accent
      fontFamily: page.fontFamily
      onClicked: page.autoCheckEnabledRequested(!page.autoCheckEnabled)
    }
    ButtonGroup {
      visible: page.autoCheckEnabled
      enabled: !page.settingsBusy
      options: [1, 3, 6, 12, 24].map(function(h) {
        return { value: String(h), label: "Every " + h + "h" }
      })
      value: String(page.autoCheckIntervalHours)
      foreground: page.foreground
      accent: Commons.Color.accent
      fontFamily: page.fontFamily
      fontSize: Style.font.caption
      onChanged: function(value) { page.autoCheckIntervalRequested(Number(value)) }
    }
    Dropdown {
      id: updateScopeDropdown
      Layout.fillWidth: true
      enabled: !page.settingsBusy
      label: "Update scope"
      value: page.bulkUpdateScope
      options: [
        { value: "verified", label: "Verified only" },
        { value: "pending", label: "Verified + Update Unverified" },
        { value: "all", label: "All plugins" }
      ]
      foreground: page.foreground
      background: page.panelBackground
      popupBorder: Util.alpha(page.foreground, 0.2)
      accent: Commons.Color.accent
      fontFamily: page.fontFamily
      onChanged: function(value) { page.bulkUpdateScopeRequested(value) }
    }
    Label {
      Layout.fillWidth: true
      text: "Choose which plugins are included in bulk updates. Individual updates are unchanged."
      wrapMode: Text.WordWrap
      color: page.foreground
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }
    Item { Layout.fillHeight: true }
    RowLayout {
      Layout.fillWidth: true
      Text {
        text: "Omaplug v" + page.pluginVersion + " ·"
        textFormat: Text.PlainText
        color: page.foreground
        font.family: page.fontFamily
        font.pixelSize: Style.font.caption
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
      }
      Button {
        text: "Release notes"
        foreground: page.foreground
        accent: Commons.Color.accent
        fontFamily: page.fontFamily
        fontSize: Style.font.caption
        onClicked: page.openUrlRequested("https://github.com/fross100/omaplug/releases/tag/v" + encodeURIComponent(page.pluginVersion))
      }
    }
  }
}
