import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property var settings: null
  property bool running: false
  property bool enabled: true
  property bool busy: false
  property var matches: []
  readonly property int matchCount: matches.length
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: homeDir + "/.config/espanso"
  readonly property string statusText: !running
    ? "Espanso stopped"
    : (enabled ? "Expansions active" : "Expansions disabled")

  readonly property int pollInterval: settings && settings.pollIntervalSec
    ? settings.pollIntervalSec * 1000
    : 10000

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!matchesProc.running) matchesProc.running = true
    if (!logCheckProc.running) logCheckProc.running = true
  }

  function toggle() {
    root.enabled = !root.enabled
    runCmd(["/usr/bin/espanso", "cmd", "toggle"])
  }

  function enable() {
    root.enabled = true
    runCmd(["/usr/bin/espanso", "cmd", "enable"])
  }

  function disable() {
    root.enabled = false
    runCmd(["/usr/bin/espanso", "cmd", "disable"])
  }

  function launchSearch() {
    runCmd(["/usr/bin/espanso", "cmd", "search"])
  }

  function openConfigFolder() {
    runCmd(["/usr/bin/xdg-open", root.configPath])
  }

  function editMatches() {
    runCmd(["/usr/bin/xdg-open", root.configPath + "/match/base.yml"])
  }

  function restartService() {
    runCmd(["/usr/bin/systemctl", "--user", "restart", "espanso"])
    Qt.callLater(function() {
      pollTimer.restart()
      root.refresh()
    })
  }

  function showLogs() {
    runCmd(["/usr/bin/omarchy-launch-floating-terminal", "journalctl --user -u espanso -f -n 100"])
  }

  function copyMatch(textToCopy) {
    if (!textToCopy) return
    copyProc.command = ["/usr/bin/wl-copy", String(textToCopy)]
    copyProc.running = true
  }

  function injectMatch(trigger) {
    if (!trigger) return
    runCmd(["/usr/bin/espanso", "match", "exec", "-t", String(trigger)])
  }

  function runCmd(args) {
    var proc = cmdProc
    if (proc.running) {
      var dynamicProc = Qt.createQmlObject('import Quickshell.Io 1.0; Process {}', root)
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
        var lines = text.split("\n")
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
            var parsed = JSON.parse(trimmed)
            if (Array.isArray(parsed)) {
              root.matches = parsed
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
