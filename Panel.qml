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
  property bool noticeIsError: false
  property bool editorOpen: false
  property string editingId: ""
  property string editTrigger: ""
  property string editReplacement: ""
  property bool editWord: false
  property string deleteId: ""
  property string deleteTrigger: ""

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

  function handleCopy(replaceText, triggerLabel) {
    if (!service) return
    service.copyMatch(replaceText)
    root.copiedNotice = "Copied \"" + triggerLabel + "\" to clipboard"
    root.noticeIsError = false
    root.noticeVisible = true
    noticeTimer.restart()
  }

  function beginCreate() {
    root.deleteId = ""
    root.editingId = ""
    root.editTrigger = ""
    root.editReplacement = ""
    root.editWord = false
    triggerField.text = ""
    replacementField.text = ""
    root.editorOpen = true
    Qt.callLater(function() { triggerField.forceActiveFocus() })
  }

  function beginEdit(match) {
    root.deleteId = ""
    root.editingId = match.managedId
    root.editTrigger = match.triggers[0]
    root.editReplacement = match.replace
    root.editWord = match.word === true
    triggerField.text = root.editTrigger
    replacementField.text = root.editReplacement
    root.editorOpen = true
    Qt.callLater(function() { triggerField.forceActiveFocus() })
  }

  function beginDelete(match) {
    root.editorOpen = false
    root.deleteId = match.managedId
    root.deleteTrigger = match.triggers[0]
  }

  Connections {
    target: root.service
    function onMutationFinished(success, message) {
      root.copiedNotice = message
      root.noticeIsError = !success
      root.noticeVisible = true
      noticeTimer.restart()
      if (success) {
        root.editorOpen = false
        root.deleteId = ""
      }
    }
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
                    : (root.service.running
                        ? (root.service.enabled ? "Active · " + root.service.matchCount + " snippets" : "Expansions disabled")
                        : "Service stopped"))
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

            Button {
              text: "New"
              iconText: "󰐕"
              bordered: false
              foreground: root.foreground
              accent: root.accent
              enabled: root.service && !root.service.busy
              onClicked: root.beginCreate()
            }
          }

          BorderSurface {
            visible: root.editorOpen
            width: parent.width
            color: Style.selectedFillFor(root.foreground, root.accent)
            radius: Style.cornerRadius
            borderSpec: Border.flat(root.accent, 1)
            implicitHeight: editorColumn.implicitHeight + Style.space(20)

            ColumnLayout {
              id: editorColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(7)

              Text {
                text: root.editingId ? "Edit expansion" : "New expansion"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              TextField {
                id: triggerField
                Layout.fillWidth: true
                placeholderText: "Trigger, e.g. ;email"
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.editTrigger = text
              }

              TextArea {
                id: replacementField
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(86)
                placeholderText: "Replacement text"
                onTextChanged: root.editReplacement = text
                wrapMode: TextEdit.Wrap
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                background: Rectangle {
                  color: Style.selectedFillFor(root.foreground, root.accent)
                  radius: Style.cornerRadius
                  border.color: root.dim
                  border.width: 1
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "Word match"
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                }

                ToggleSwitch {
                  checked: root.editWord
                  foreground: root.foreground
                  accent: root.accent
                  onToggled: root.editWord = !root.editWord
                }
              }

              RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Style.space(6)

                Button {
                  text: "Cancel"
                  bordered: false
                  foreground: root.foreground
                  accent: root.accent
                  onClicked: root.editorOpen = false
                }
                Button {
                  text: "Save"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  enabled: root.service && !root.service.busy
                  onClicked: root.service.changeMatch(root.editingId ? "update" : "create",
                    root.editingId, root.editTrigger, root.editReplacement, root.editWord)
                }
              }
            }
          }

          BorderSurface {
            visible: root.deleteId !== ""
            width: parent.width
            color: Style.selectedFillFor(root.foreground, root.accent)
            radius: Style.cornerRadius
            borderSpec: Border.flat(root.urgent, 1)
            implicitHeight: deleteRow.implicitHeight + Style.space(16)

            RowLayout {
              id: deleteRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(8)

              Text {
                text: "Delete " + root.deleteTrigger + "?"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Button {
                text: "Cancel"
                bordered: false
                foreground: root.foreground
                accent: root.accent
                onClicked: root.deleteId = ""
              }
              Button {
                text: "Delete"
                bordered: true
                foreground: root.foreground
                accent: root.urgent
                enabled: root.service && !root.service.busy
                onClicked: root.service.changeMatch("delete", root.deleteId, "", "")
              }
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
                onEditRequested: root.beginEdit(modelData)
                onDeleteRequested: root.beginDelete(modelData)
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

      Rectangle {
        id: noticeToast
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        height: noticeText.implicitHeight + Style.space(16)
        visible: root.noticeVisible
        z: 1
        color: Color.popups.background
        border.color: root.noticeIsError ? root.urgent : root.accent
        border.width: 1
        radius: Style.cornerRadius

        Text {
          id: noticeText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          text: (root.noticeIsError ? "!  " : "✓  ") + root.copiedNotice
          textFormat: Text.PlainText
          color: root.noticeIsError ? root.urgent : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // Component for individual match card
  component MatchCard: CursorSurface {
    id: card
    property var match: null
    signal copyRequested(string replaceVal, string trigVal)
    signal editRequested()
    signal deleteRequested()

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

      Text {
        visible: card.match && card.match.managedId
        text: "󰏫"
        textFormat: Text.PlainText
        color: editMouse.containsMouse ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: editMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.editRequested()
        }
      }

      Text {
        visible: card.match && card.match.managedId
        text: "󰆴"
        textFormat: Text.PlainText
        color: deleteMouse.containsMouse ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        MouseArea {
          id: deleteMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: card.deleteRequested()
        }
      }
    }
  }
}
