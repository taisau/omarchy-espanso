import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.taisau.espanso"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  property string filterText: ""
  property string copiedNotice: ""
  property bool noticeVisible: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function filteredMatches() {
    if (!service || !service.matches) return []
    var list = service.matches.slice()
    var q = filterText ? filterText.trim().toLowerCase() : ""

    if (q !== "") {
      list = list.filter(function(m) {
        var trig = (m.triggers || []).join(" ").toLowerCase()
        var repl = (m.replace || "").toLowerCase()
        var lab = (m.label || "").toLowerCase()
        return trig.indexOf(q) !== -1 || repl.indexOf(q) !== -1 || lab.indexOf(q) !== -1
      })
    }

    list.sort(function(a, b) {
      var fullA = (a.triggers && a.triggers.length > 0) ? String(a.triggers[0]) : ""
      var fullB = (b.triggers && b.triggers.length > 0) ? String(b.triggers[0]) : ""
      var normA = fullA.replace(/^[\\\/:\.;,]+/, "").toLowerCase()
      var normB = fullB.replace(/^[\\\/:\.;,]+/, "").toLowerCase()
      var cmp = normA.localeCompare(normB)
      return cmp !== 0 ? cmp : fullA.localeCompare(fullB)
    })

    return list
  }

  function showNotice(text) {
    root.copiedNotice = text
    root.noticeVisible = true
    noticeTimer.restart()
  }

  function handleCopy(replaceText, triggerLabel) {
    if (!service) return
    service.copyMatch(replaceText)
    showNotice("Copied \"" + triggerLabel + "\" to clipboard")
  }

  function handleRestart() {
    if (!service || !service.installed || service.restarting) return
    service.restartService()
    showNotice("Restarting espanso…")
  }

  onOpenedChanged: {
    if (opened) {
      if (service) service.refresh()
      root.filterText = ""
      if (searchField && service && service.installed) {
        Qt.callLater(function() { searchField.forceActiveFocus() })
      }
    }
  }

  Timer {
    id: noticeTimer
    interval: 2200
    onTriggered: root.noticeVisible = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // 1. Hero Header
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: "Espanso"
              meta: root.service
                ? (!root.service.installed
                    ? "Not installed"
                    : (root.service.restarting
                        ? "Restarting…"
                        : (root.service.running
                            ? (root.service.deaf
                                ? "Lost input devices · restart needed"
                                : (root.service.enabled ? "Active · " + root.service.matchCount + " snippets" : "Expansions disabled"))
                            : "Service stopped")))
                : "Loading…"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.service && root.service.installed && root.service.running && root.service.enabled ? 1.0 : 0.5

              iconComponent: Component {
                Image {
                  width: hero.iconSize
                  height: hero.iconSize
                  source: (root.service && root.service.installed && root.service.enabled)
                    ? Qt.resolvedUrl("assets/espanso-outline.svg")
                    : Qt.resolvedUrl("assets/espanso-disabled.svg")
                  sourceSize.width: 48
                  sourceSize.height: 48
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: root.service && root.service.installed && root.service.running
                  checked: root.service ? root.service.enabled : false
                  foreground: hero.foreground
                  onToggled: {
                    if (root.service) root.service.toggle()
                  }

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.service && root.service.enabled ? "Disable expansions" : "Enable expansions"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // 2. Install Banner (Shown only when Espanso is not installed)
          BorderSurface {
            visible: root.service && !root.service.installed
            width: parent.width
            color: Style.selectedFillFor(root.foreground, root.accent)
            radius: Style.cornerRadius
            borderSpec: Border.flat(root.accent, 1)

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              RowLayout {
                spacing: Style.space(8)

                Text {
                  text: "󰏓"
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Install Espanso"
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: "Installs espanso-wayland and starts the background service."
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }
              }

              Button {
                Layout.fillWidth: true
                text: "Install in Terminal"
                iconText: "󰐕"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                onClicked: {
                  if (root.service) root.service.installEspanso()
                  root.close()
                }
              }
            }
          }

          // 2b. Health Banner (Shown when the worker has lost its input devices)
          BorderSurface {
            visible: root.service && root.service.deaf
            width: parent.width
            implicitHeight: healthLayout.implicitHeight + Style.space(24)
            color: Style.selectedFillFor(root.urgent, root.urgent)
            radius: Style.cornerRadius
            borderSpec: Border.flat(root.urgent, 1)

            ColumnLayout {
              id: healthLayout
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              RowLayout {
                spacing: Style.space(8)

                Text {
                  text: "󰌌"
                  textFormat: Text.PlainText
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    text: "Espanso stopped seeing your keyboard"
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    text: "The worker dropped " + (root.service ? root.service.lostDevices : 0)
                      + " input device(s) after a disconnect (monitor hub, KVM, dock) and does not rescan. Restart to pick them up."
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }
              }

              Button {
                Layout.fillWidth: true
                text: "Restart Espanso"
                iconText: "󰑓"
                bordered: true
                foreground: root.foreground
                accent: root.urgent
                enabled: root.service && !root.service.restarting
                onClicked: root.handleRestart()
              }
            }
          }

          // 2c. Service row: worker uptime plus restart and log actions
          RowLayout {
            visible: root.service && root.service.installed
            width: parent.width
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              text: root.service && root.service.workerPid > 0
                ? "Worker up " + root.service.formatUptime(root.service.workerUptimeSec) + " · pid " + root.service.workerPid
                : "Worker not running"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              iconText: "󰌱"
              tooltipText: "Show service logs"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.service) root.service.showLogs()
                root.close()
              }
            }

            PanelActionButton {
              iconText: "󰑓"
              tooltipText: "Restart espanso service"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.service && !root.service.restarting
              onClicked: root.handleRestart()
            }
          }

          // 3. Search Filter Field (Only shown when installed)
          TextField {
            id: searchField
            visible: root.service && root.service.installed
            width: parent.width
            placeholderText: "Filter snippets (e.g. \\aad, email, code)…"
            foreground: root.foreground
            accent: root.accent
            text: root.filterText
            onTextChanged: root.filterText = text
          }

          // 4. Copied Notification Toast
          Text {
            visible: root.noticeVisible
            width: parent.width
            text: "✓  " + root.copiedNotice
            textFormat: Text.PlainText
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSeparator {
            visible: root.service && root.service.installed
            width: parent.width
            foreground: root.foreground
          }

          // 5. Snippets Section Header
          RowLayout {
            visible: root.service && root.service.installed
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SNIPPETS"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
            }

            Text {
              text: (root.service ? String(root.filteredMatches().length) : "0") + " matches"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // 6. Match List
          Column {
            id: matchColumn
            visible: root.service && root.service.installed
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.filteredMatches()

              MatchCard {
                required property var modelData
                required property int index
                width: matchColumn.width
                match: modelData
                onCopyRequested: function(replaceVal, trigVal) {
                  root.handleCopy(replaceVal, trigVal)
                }
              }
            }

            Text {
              visible: root.filteredMatches().length === 0
              width: parent.width
              text: "No matching snippets found."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(12)
              bottomPadding: Style.space(12)
            }
          }
        }
      }
    }
  }

  // Component for individual match card
  component MatchCard: CursorSurface {
    id: card
    property var match: null
    signal copyRequested(string replaceVal, string trigVal)

    readonly property string triggerStr: match && match.triggers ? match.triggers.join(", ") : ""
    readonly property string replaceStr: match && match.replace ? String(match.replace) : ""
    readonly property string labelStr: match && match.label ? String(match.label) : ""

    width: parent.width
    implicitHeight: cardLayout.implicitHeight + Style.space(10)
    foreground: root.foreground
    accent: root.accent
    hasCursor: cardMouse.containsMouse

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: card.copyRequested(card.replaceStr, card.triggerStr)
    }

    RowLayout {
      id: cardLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)

      // Trigger Badge / Label
      Text {
        text: card.triggerStr
        textFormat: Text.PlainText
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        Layout.preferredWidth: Style.space(64)
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignVCenter
      }

      // Snippet Preview
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Layout.alignment: Qt.AlignVCenter

        Text {
          visible: card.labelStr !== ""
          text: card.labelStr
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          text: card.replaceStr.replace(/\n/g, " ↵ ")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Copy Action Icon
      Text {
        text: "󰆏"
        textFormat: Text.PlainText
        color: cardMouse.containsMouse ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
