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
  property var espansoMatches: []
  property var managedMatches: []
  signal mutationFinished(bool success, string message)
  readonly property int matchCount: matches.length
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: homeDir + "/.config/espanso"
  readonly property string helperPath: homeDir + "/.config/omarchy/plugins/io.github.taisau.espanso/scripts/espanso-matches.py"
  readonly property string statusText: !installed
    ? "Espanso is not installed"
    : (!running
        ? "Espanso stopped"
        : (enabled ? "Expansions active" : "Expansions disabled"))

  readonly property int pollInterval: settings && settings.pollIntervalSec
    ? settings.pollIntervalSec * 1000
    : 10000

  // Security, bounded stream, and DoS protection ceilings
  readonly property int maxJsonBytes: 1048576       // 1 MiB hard stream buffer ceiling
  readonly property int maxLogBytes: 65536          // 64 KiB log buffer ceiling
  readonly property int maxStatusBytes: 4096        // 4 KiB status buffer ceiling
  readonly property int maxMatchRecords: 500        // 500 match items ceiling
  readonly property int maxTriggersPerItem: 10      // 10 triggers max per item
  readonly property int maxTriggerLength: 100       // 100 chars max per trigger
  readonly property int maxReplaceLength: 5000      // 5000 chars max per replacement string
  readonly property int maxLabelLength: 200         // 200 chars max per label string

  property string _rawMatchBuffer: ""
  property string _rawLogBuffer: ""
  property string _rawStatusBuffer: ""

  function refresh() {
    if (!whichProc.running) whichProc.running = true
    if (installed) {
      if (!statusProc.running) statusProc.running = true
      if (!matchesProc.running) matchesProc.running = true
      if (!managedProc.running) managedProc.running = true
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

  function rebuildMatches() {
    var rows = root.espansoMatches.map(function(item) {
      return { triggers: item.triggers, replace: item.replace, label: item.label, managedId: "", word: false }
    })
    for (var i = 0; i < root.managedMatches.length; i++) {
      var managed = root.managedMatches[i]
      var found = false
      for (var j = 0; j < rows.length; j++) {
        if (!rows[j].managedId && rows[j].triggers.length === 1
            && rows[j].triggers[0] === managed.trigger
            && rows[j].replace === managed.replace) {
          rows[j].managedId = managed.id
          rows[j].word = managed.word === true
          found = true
          break
        }
      }
      if (!found) rows.push({ triggers: [managed.trigger], replace: managed.replace, label: "", managedId: managed.id, word: managed.word === true })
    }
    root.matches = rows
  }

  function changeMatch(action, matchId, trigger, replacement, word) {
    if (root.busy || !root.installed) return
    if (action === "create" || action === "update") {
      trigger = String(trigger || "").trim()
      replacement = String(replacement || "")
      if (!trigger || !replacement) {
        root.mutationFinished(false, "Enter a trigger and replacement")
        return
      }
      for (var i = 0; i < root.matches.length; i++) {
        var match = root.matches[i]
        if (match.managedId !== matchId && match.triggers.indexOf(trigger) !== -1) {
          root.mutationFinished(false, "That trigger is already in use")
          return
        }
      }
    }
    var args = ["/usr/bin/python3", root.helperPath, action]
    if (action !== "create") args.push(matchId)
    if (action !== "delete") {
      args.push(trigger, replacement)
      if (word) args.push("--word")
    }
    root._mutationError = ""
    mutationProc.command = args
    root.busy = true
    mutationProc.running = true
  }

  function parseMatches(rawJson) {
    try {
      var trimmed = (rawJson || "").trim()
      if (trimmed.length > 0) {
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
          root.espansoMatches = sanitized
          root.rebuildMatches()
        }
      }
    } catch (e) {
      console.warn("[espanso-plugin] JSON parse error on match list:", e)
    }
  }

  function parseLog(rawLogs) {
    var lines = (rawLogs || "").split("\n")
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

  // Binary detection with timeout
  property var whichProc: Process {
    id: whichProc
    command: ["/bin/sh", "-c", "exec timeout 2 /usr/bin/which espanso 2>/dev/null | head -c 256"]
    running: false
    onExited: function(exitCode) {
      root.installed = (exitCode === 0)
      if (!root.installed) {
        root.running = false
        root.matches = []
      }
    }
  }

  // Bounded status check: OS timeout + OS head + incremental stream bounding
  property var statusProc: Process {
    id: statusProc
    command: ["/bin/sh", "-c", "exec timeout 3 /usr/bin/espanso status 2>/dev/null | head -c 4096"]
    running: false
    stdout: SplitParser {
      onRead: function(chunk) {
        if (root._rawStatusBuffer.length < root.maxStatusBytes) {
          var remaining = root.maxStatusBytes - root._rawStatusBuffer.length
          root._rawStatusBuffer += String(chunk || "").slice(0, remaining)
        } else if (statusProc.running) {
          statusProc.running = false
        }
      }
    }
    onStarted: {
      root._rawStatusBuffer = ""
    }
    onExited: function(exitCode) {
      root.running = (root._rawStatusBuffer.indexOf("espanso is running") !== -1)
      root._rawStatusBuffer = ""
    }
  }

  // Bounded log check: OS timeout + OS head + incremental stream bounding
  property var logCheckProc: Process {
    id: logCheckProc
    command: ["/bin/sh", "-c", "exec timeout 3 /usr/bin/journalctl --user -u espanso -n 30 --no-pager 2>/dev/null | head -c 65536"]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root._rawLogBuffer.length < root.maxLogBytes) {
          var remaining = root.maxLogBytes - root._rawLogBuffer.length
          root._rawLogBuffer += (String(line || "") + "\n").slice(0, remaining)
        } else if (logCheckProc.running) {
          logCheckProc.running = false
        }
      }
    }
    onStarted: {
      root._rawLogBuffer = ""
    }
    onExited: function(exitCode) {
      root.parseLog(root._rawLogBuffer)
      root._rawLogBuffer = ""
    }
  }

  // Bounded match collection: OS timeout + OS head + incremental stream bounding + item limits
  property var matchesProc: Process {
    id: matchesProc
    command: ["/bin/sh", "-c", "exec timeout 5 /usr/bin/espanso match list --json 2>/dev/null | head -c 1048576"]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root._rawMatchBuffer.length < root.maxJsonBytes) {
          var remaining = root.maxJsonBytes - root._rawMatchBuffer.length
          root._rawMatchBuffer += (String(line || "") + "\n").slice(0, remaining)
        } else if (matchesProc.running) {
          matchesProc.running = false
        }
      }
    }
    onStarted: {
      root._rawMatchBuffer = ""
    }
    onExited: function(exitCode) {
      root.parseMatches(root._rawMatchBuffer)
      root._rawMatchBuffer = ""
    }
  }

  property var managedProc: Process {
    id: managedProc
    command: ["/usr/bin/python3", root.helperPath, "list"]
    running: false
    stdout: SplitParser {
      onRead: function(chunk) {
        if (root._rawManagedBuffer.length < root.maxJsonBytes) {
          var remaining = root.maxJsonBytes - root._rawManagedBuffer.length
          root._rawManagedBuffer += (String(chunk || "") + "\n").slice(0, remaining)
        } else if (managedProc.running) {
          managedProc.running = false
        }
      }
    }
    onStarted: root._rawManagedBuffer = ""
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(root._rawManagedBuffer)
          if (Array.isArray(parsed)) {
            root.managedMatches = parsed.slice(0, root.maxMatchRecords)
            root.rebuildMatches()
          }
        } catch (e) {
          console.warn("[espanso-plugin] Managed match JSON parse error:", e)
        }
      }
      root._rawManagedBuffer = ""
    }
  }

  property string _rawManagedBuffer: ""
  property string _mutationError: ""

  property var mutationProc: Process {
    id: mutationProc
    running: false
    stderr: SplitParser {
      onRead: function(chunk) { root._mutationError += String(chunk || "") + "\n" }
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.refresh()
        root.mutationFinished(true, "Expansion saved")
      } else {
        root.mutationFinished(false, root._mutationError.trim() || "Could not save expansion")
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
