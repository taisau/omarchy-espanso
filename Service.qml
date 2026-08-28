import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property var settings: null
  property bool installed: true
  property bool running: false
  property bool enabled: true
  property bool busy: false
  property var matches: []
  readonly property int matchCount: matches.length
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: homeDir + "/.config/espanso"
  readonly property string statusText: !installed
    ? "Espanso is not installed"
    : (!running
        ? "Espanso stopped"
        : (enabled ? "Expansions active" : "Expansions disabled"))

  readonly property int pollInterval: settings && settings.pollIntervalSec
    ? settings.pollIntervalSec * 1000
    : 10000

  // Security and DoS protection ceilings
  readonly property int maxJsonBytes: 1048576       // 1 MB max raw output ceiling
  readonly property int maxMatchRecords: 500         // 500 match items ceiling
  readonly property int maxTriggersPerItem: 10       // 10 triggers max per item
  readonly property int maxTriggerLength: 100        // 100 chars max per trigger
  readonly property int maxReplaceLength: 5000       // 5000 chars max per replacement string
  readonly property int maxLabelLength: 200          // 200 chars max per label string

  function refresh() {
    if (!whichProc.running) whichProc.running = true
    if (installed) {
      if (!statusProc.running) statusProc.running = true
      if (!matchesProc.running) matchesProc.running = true
      if (!logCheckProc.running) logCheckProc.running = true
    }
  }

  function toggle() {
    if (!installed) return
    root.enabled = !root.enabled
    runCmd(["/usr/bin/espanso", "cmd", "toggle"])
  }

  function enable() {
    if (!installed) return
    root.enabled = true
    runCmd(["/usr/bin/espanso", "cmd", "enable"])
  }

  function disable() {
    if (!installed) return
    root.enabled = false
    runCmd(["/usr/bin/espanso", "cmd", "disable"])
  }

  function launchSearch() {
    if (!installed) return
    runCmd(["/usr/bin/espanso", "cmd", "search"])
  }

  function openConfigFolder() {
    runCmd(["/usr/bin/xdg-open", root.configPath])
  }

  function editMatches() {
    runCmd(["/usr/bin/xdg-open", root.configPath + "/match/base.yml"])
  }

  function restartService() {
    if (!installed) return
    runCmd(["/usr/bin/systemctl", "--user", "restart", "espanso"])
    Qt.callLater(function() {
      pollTimer.restart()
      root.refresh()
    })
  }

  function installEspanso() {
    var script = (root.homeDir ? root.homeDir : "/home/taisau") + "/.config/omarchy/plugins/io.github.taisau.espanso/scripts/espanso-install.sh"
    runCmd(["/usr/bin/omarchy-launch-floating-terminal", "bash " + script])
  }

  function showLogs() {
    runCmd(["/usr/bin/omarchy-launch-floating-terminal", "journalctl --user -u espanso -f -n 100"])
  }

  function copyMatch(textToCopy) {
    if (!textToCopy) return
    var sanitized = String(textToCopy).slice(0, root.maxReplaceLength)
    copyProc.command = ["/usr/bin/wl-copy", sanitized]
    copyProc.running = true
  }

  function injectMatch(trigger) {
    if (!trigger || !installed) return
    var sanitized = String(trigger).slice(0, root.maxTriggerLength)
    runCmd(["/usr/bin/espanso", "match", "exec", "-t", sanitized])
  }

  function runCmd(args) {
    var proc = cmdProc
    if (proc.running) {
      var dynamicProc = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
      dynamicProc.command = args
      dynamicProc.exited.connect(function() {
        dynamicProc.destroy()
        root.refresh()
      })
      dynamicProc.running = true
    } else {
      proc.command = args
      proc.running = true
    }
  }

  property var timer: Timer {
    id: pollTimer
    interval: root.pollInterval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  property var whichProc: Process {
    id: whichProc
    command: ["/usr/bin/which", "espanso"]
    running: false
    onExited: function(exitCode) {
      root.installed = (exitCode === 0)
      if (!root.installed) {
        root.running = false
        root.matches = []
      }
    }
  }

  property var statusProc: Process {
    id: statusProc
    command: ["/usr/bin/espanso", "status"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.running = (text.indexOf("espanso is running") !== -1)
      }
    }
  }

  property var logCheckProc: Process {
    id: logCheckProc
    command: ["/usr/bin/journalctl", "--user", "-u", "espanso", "-n", "30", "--no-pager"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var maxLogBytes = 65536
        var logText = text.length > maxLogBytes ? text.slice(text.length - maxLogBytes) : text
        var lines = logText.split("\n")
        for (var i = lines.length - 1; i >= 0; i--) {
          var line = lines[i]
          if (line.indexOf("is_enabled = false") !== -1) {
            root.enabled = false
            break
          } else if (line.indexOf("is_enabled = true") !== -1) {
            root.enabled = true
            break
          }
        }
      }
    }
  }

  property var matchesProc: Process {
    id: matchesProc
    command: ["/usr/bin/espanso", "match", "list", "--json"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var trimmed = text.trim()
          if (trimmed.length > 0) {
            if (trimmed.length > root.maxJsonBytes) {
              console.warn("[espanso-plugin] match list exceeded byte ceiling (" + trimmed.length + " bytes), skipping")
              return
            }
            var parsed = JSON.parse(trimmed)
            if (Array.isArray(parsed)) {
              var count = Math.min(parsed.length, root.maxMatchRecords)
              var sanitized = []
              for (var i = 0; i < count; i++) {
                var item = parsed[i]
                if (!item || typeof item !== "object") continue

                var rawTriggers = Array.isArray(item.triggers) ? item.triggers : []
                var cleanTriggers = []
                var trigCount = Math.min(rawTriggers.length, root.maxTriggersPerItem)
                for (var t = 0; t < trigCount; t++) {
                  var trig = String(rawTriggers[t] || "").slice(0, root.maxTriggerLength)
                  if (trig.length > 0) cleanTriggers.push(trig)
                }

                var cleanReplace = String(item.replace || "").slice(0, root.maxReplaceLength)
                var cleanLabel = item.label ? String(item.label).slice(0, root.maxLabelLength) : ""

                sanitized.push({
                  triggers: cleanTriggers,
                  replace: cleanReplace,
                  label: cleanLabel
                })
              }
              root.matches = sanitized
            }
          }
        } catch (e) {
          console.warn("[espanso-plugin] JSON parse error on match list:", e)
        }
      }
    }
  }

  property var cmdProc: Process {
    id: cmdProc
    running: false
    onExited: root.refresh()
  }

  property var copyProc: Process {
    id: copyProc
    running: false
  }

  Component.onCompleted: root.refresh()
}
