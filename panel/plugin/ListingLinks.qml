pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../Presentation.js" as Presentation

RowLayout {
  id: links

  required property string pluginId
  required property var entry
  required property string localCommit
  required property string repoUrl
  required property color foreground
  required property string fontFamily

  signal openUrlRequested(string url)

  readonly property string snapshotCommit: entry && typeof entry.snapshotCommit === "string"
    ? entry.snapshotCommit : ""
  readonly property bool commitKnown: snapshotCommit !== "" && localCommit !== ""
  readonly property bool commitMatches: commitKnown && snapshotCommit === localCommit
  readonly property string compareUrl: Presentation.compareUrl(repoUrl, snapshotCommit, localCommit)
  readonly property string snapshotUrl: Presentation.commitUrl(repoUrl, snapshotCommit)
  readonly property string localUrl: Presentation.commitUrl(repoUrl, localCommit)
  readonly property string marketplaceUrl: Presentation.marketplaceUrl(pluginId)
  readonly property string checksUrl: Presentation.listingChecksUrl(pluginId)

  spacing: Style.space(6)
  Layout.fillWidth: true

  // Every link can shrink or elide so this row never displaces the plugin
  // actions at the right edge.
  Item {
    id: marketplaceLink

    readonly property int gap: 2
    Layout.preferredWidth: marketplaceIcon.width + marketplaceArrow.implicitWidth + gap
    Layout.preferredHeight: Math.max(marketplaceIcon.height, marketplaceArrow.implicitHeight)
    Layout.alignment: Qt.AlignVCenter

    // Omarchy Plugins favicon, based on Lucide's ISC-licensed cable icon.
    Image {
      id: marketplaceIcon
      anchors.verticalCenter: parent.verticalCenter
      source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABmJLR0QA/wD/AP+gvaeTAAADb0lEQVRYhe2WTWhcVRTHf+fNNAmh1tFQsISUErMSwUicSbOpLTSLiEUTECaTEl2JKEVU6MKvjboRFAu6cCNB7CNS0SKxWbQqtJCYSYsR6spa1Cgu2spYQup85P1d3DfT92YyHcTpqv3D4557vt+599x74TZudVg9Q08Npih1PA922vylbwGUG94H2kNH6YjNrBQabfZ2UVo/gPGAY/AD5cScHVu81iqBZAOn1Pki6DVQAbgrDPE5kKLUmQBejwWfSqcprc8A96GIYMvGqnLpg+Yvn/5vCYiesC4p5dL7Q26qJouq5tL9yL4Btm7iuw9sXrnhQfOXfmqWgBdzOD20E9PUdY6ddF91qoPKpvsi8o/C4AJ7AzruppzocRVEQDfow2bBob4CFe8wcOcN9Lfh2WHgkLK7d0HwcJj6jPn56NK8qcnMAMaTwD5ND+20j8/9tplDr27a7/zpEmIcNAoaRYwjLoV/fa8bgv6amezLTXwfr1HlxECzP2rcAwBmBfPzx6Ms5TJvA9uv5xp0Iq9KFxt8eEExIu9slkC8AtI/bqRbkRYVGKI7ptMm1FXAVkDjGL3kMnMSdzi2rYF6Ha3vb14CFe99tmw8A+wAHonVwOFPyskP2plAbAns2OJfkBxBfAZcjYiuOl5yxOm0Dw2b0PyFX4EnNPXQGPJOOGaQNf/sfDsDV+G1Vrm52LwN/weU3b0LT++4M6QK71Plhk8S2Es2+90vUf22VkDTmR4SwSJogmoHAY7WBF6woOlM7D5p7xKU7TnEPQAYXyHOIM4AJ0KNHVT0bNSkzUugQTfwB37+gIX9KzAmM6sYvcgejFq0twJmXW5k3SKHh4Ew1mM6IZpXIPCKtYMo8DY5y72umG4UIqXJzOOY1tzctiJSje+vGyVgyZ+hEtIaI3q7AQQ8VnMohQ+O4CIYGNuBL2rXSTSw6UIsTNMEAOUyC8AIbhnfIqn3ANjgBcTLof3X5uf3Ayib7sOz88C2Ji7/xux+O7r0e5XRYg/YIeCaC6RXqXCZCpcRr4TB10BP17Rnl1eRfRL5hdHYeSA7Gg3eMgHzl84RsAf4sUEozoPtNX/5YtyIKyFVMH/5lPnLp4BCnayGlm1os/mzGhsYItXzKEa1zVYoXJmz+QuND5GO4ruUOjbAIq9hm3DP+uKRVvFu49bDv15cMTlnbnc+AAAAAElFTkSuQmCC"
      width: 14
      height: 14
      fillMode: Image.PreserveAspectFit
      cache: false
    }

    Text {
      id: marketplaceArrow
      x: marketplaceIcon.width + marketplaceLink.gap
      anchors.verticalCenter: parent.verticalCenter
      text: "↗"
      textFormat: Text.PlainText
      color: Color.accent
      font.family: links.fontFamily
      font.pixelSize: Style.font.caption
    }

    HoverHandler {
      id: marketplaceHover
      cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
      onTapped: links.openUrlRequested(links.marketplaceUrl)
    }

    ToolTip.text: links.marketplaceUrl
    ToolTip.visible: marketplaceHover.hovered
    ToolTip.delay: 400
  }

  Text {
    text: "|"
    textFormat: Text.PlainText
    color: Qt.darker(links.foreground, 2.4)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: links.snapshotCommit !== ""
    text: "\uDB81\uDF91 " + Presentation.shortSha(links.snapshotCommit)
    textFormat: Text.PlainText
    color: links.commitMatches ? Color.accent : Qt.darker(links.foreground, 1.6)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: snapshotHover.hovered && links.snapshotUrl !== ""

    ToolTip.text: links.snapshotUrl !== "" ? links.snapshotUrl : links.snapshotCommit
    ToolTip.visible: snapshotHover.hovered
    ToolTip.delay: 400

    HoverHandler {
      id: snapshotHover
      cursorShape: links.snapshotUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
      anchors.fill: parent
      enabled: links.snapshotUrl !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrlRequested(links.snapshotUrl)
    }
  }

  Text {
    visible: links.snapshotCommit === "" && links.localCommit !== ""
    text: "\uDB81\uDF91 " + Presentation.shortSha(links.localCommit) + (links.localUrl !== "" ? " ↗" : "")
    textFormat: Text.PlainText
    color: Qt.darker(links.foreground, 1.6)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: localOnlyHover.hovered && links.localUrl !== ""

    HoverHandler {
      id: localOnlyHover
      cursorShape: links.localUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
      anchors.fill: parent
      enabled: links.localUrl !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrlRequested(links.localUrl)
    }
  }

  Text {
    visible: links.snapshotCommit !== "" && links.localCommit !== "" && !links.commitMatches
    text: "→"
    textFormat: Text.PlainText
    color: Qt.darker(links.foreground, 2.0)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: links.snapshotCommit !== "" && links.localCommit !== "" && !links.commitMatches
    text: Presentation.shortSha(links.localCommit) + (links.localUrl !== "" ? " ↗" : "")
    textFormat: Text.PlainText
    color: Color.accent
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: localHover.hovered && links.localUrl !== ""

    ToolTip.text: links.localUrl !== "" ? links.localUrl : links.localCommit
    ToolTip.visible: localHover.hovered
    ToolTip.delay: 400

    HoverHandler {
      id: localHover
      cursorShape: links.localUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
      anchors.fill: parent
      enabled: links.localUrl !== ""
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrlRequested(links.localUrl)
    }
  }

  Text {
    visible: links.compareUrl !== ""
    text: "|"
    textFormat: Text.PlainText
    color: Qt.darker(links.foreground, 2.4)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: links.compareUrl !== ""
    text: "view changes ↗"
    textFormat: Text.PlainText
    color: Color.accent
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: compareHover.hovered
    elide: Text.ElideRight
    ToolTip.text: links.compareUrl
    ToolTip.visible: compareHover.hovered
    ToolTip.delay: 400

    HoverHandler {
      id: compareHover
      cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrlRequested(links.compareUrl)
    }
  }

  Text {
    text: "|"
    textFormat: Text.PlainText
    color: Qt.darker(links.foreground, 2.4)
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    text: "Listing checks ↗"
    textFormat: Text.PlainText
    color: Color.accent
    font.family: links.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: checksHover.hovered
    elide: Text.ElideRight
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    ToolTip.text: links.checksUrl
    ToolTip.visible: checksHover.hovered
    ToolTip.delay: 400

    HoverHandler {
      id: checksHover
      cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: links.openUrlRequested(links.checksUrl)
    }
  }
}
