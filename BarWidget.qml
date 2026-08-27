import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.taisau.espanso"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem
    ? panelItem.popoutSwitchClosing === true
    : false

  Service {
    id: service
    settings: root.settings
  }

  function open() {
    if (panelItem) panelItem.open()
  }

  function close() {
    if (panelItem) panelItem.close()
  }

  function toggle() {
    if (panelItem) panelItem.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelItem) panelItem.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = service
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: !service.running
      ? "Espanso: Stopped"
      : (service.enabled ? "Espanso: Active (L: panel, R: search, M: toggle)" : "Espanso: Disabled (Click to resume)")

    iconComponent: Component {
      Item {
        id: iconWrapper
        anchors.fill: parent

        readonly property color iconColor: !service.running
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (service.enabled ? (root.bar ? root.bar.foreground : Color.foreground) : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6))

        Image {
          id: iconImg
          anchors.centerIn: parent
          width: Style.space(11)
          height: Style.space(11)
          source: service.enabled ? Qt.resolvedUrl("assets/espanso-outline.svg") : Qt.resolvedUrl("assets/espanso-disabled.svg")
          sourceSize.width: 32
          sourceSize.height: 32
          fillMode: Image.PreserveAspectFit
          smooth: true
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: iconImg
          source: iconImg
          colorization: 1.0
          colorizationColor: iconWrapper.iconColor
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        service.launchSearch()
      } else if (buttonCode === Qt.MiddleButton) {
        service.toggle()
      } else {
        root.toggle()
      }
    }
  }
}
