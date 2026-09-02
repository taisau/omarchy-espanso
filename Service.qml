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
  property bool restarting: false
  property var matches: []

  // Worker health. Espanso's evdev backend drops any keyboard that disconnects
  // (monitor USB hub power-cycling on DPMS off, KVM switches, docks) and never
  // rescans, so the daemon keeps reporting "running" while it no longer sees a
  // single keystroke. Count those log lines for the current worker process.
  property int workerPid: 0
  property int workerUptimeSec: 0
  property int lostDevices: 0
  readonly property bool deaf: running && lostDevices > 0
  readonly property int matchCount: matches.length
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: homeDir + "/.config/espanso"
  readonly property string statusText: !installed
    ? "Espanso is not installed"
    : (restarting
        ? "Restarting…"
        : (!running
            ? "Espanso stopped"
            : (deaf
                ? "Lost input devices"
                : (enabled ? "Expansions active" : "Expansions disabled"))))

  readonly property int pollInterval: settings && settings.pollIntervalSec
    ? settings.pollIntervalSec * 1000
    : 10000

  // Security, bounded stream, and DoS protection ceilings
  readonly property int maxJsonBytes: 1048576       // 1 MiB hard stream buffer ceiling
  readonly property int maxLogBytes: 65536          // 64 KiB log buffer ceiling
  readonly property int maxStatusBytes: 4096        // 4 KiB status buffer ceiling
  readonly property int maxHealthBytes: 256         // 256 B worker health line ceiling
  readonly property int maxMatchRecords: 500        // 500 match items ceiling
  readonly property int maxTriggersPerItem: 10      // 10 triggers max per item
  readonly property int maxTriggerLength: 100       // 100 chars max per trigger
  readonly property int maxReplaceLength: 5000      // 5000 chars max per replacement string
  readonly property int maxLabelLength: 200         // 200 chars max per label string

  property string _rawMatchBuffer: ""
  property string _rawLogBuffer: ""
  property string _rawStatusBuffer: ""
  property string _rawHealthBuffer: ""

  function refresh() {
    if (!whichProc.running) whichProc.running = true
    if (installed) {
      if (!statusProc.running) statusProc.running = true
      if (!matchesProc.running) matchesProc.running = true
      if (!logCheckProc.running) logCheckProc.running = true
      if (!healthProc.running) healthProc.running = true
    }
  }

  function formatUptime(sec) {
    sec = Math.max(0, Math.floor(sec))
    var d = Math.floor(sec / 86400)
    var h = Math.floor((sec % 86400) / 3600)
    var m = Math.floor((sec % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return sec + "s"
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
    if (!installed || restarting) return
    root.restarting = true
    root.lostDevices = 0
    runCmd(["/usr/bin/systemctl", "--user", "restart", "espanso"])
    settleTimer.ticks = 0
    settleTimer.restart()
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
          root.matches = sanitized
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

  // The worker takes a couple of seconds to come back after a restart, so
  // re-poll a few times instead of waiting for the next periodic refresh.
  property var settleTimer: Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.running = false
        root.restarting = false
        pollTimer.restart()
      }
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

  // Bounded worker health check: prints "<pid> <uptime-seconds> <lost-device-count>"
  // for the current espanso worker, or nothing when no worker is running. The
  // journal is filtered to that PID so a restart naturally resets the count.
  property var healthProc: Process {
    id: healthProc
    command: ["/bin/sh", "-c",
      "exec timeout 3 /bin/sh -c '" +
      "pid=$(pgrep -o -f \"^(/usr/bin/)?espanso worker\" 2>/dev/null) || exit 0; " +
      "up=$(ps -o etimes= -p \"$pid\" 2>/dev/null | tr -d \" \"); " +
      "lost=$(journalctl --user -u espanso \"_PID=$pid\" -o cat --no-pager 2>/dev/null | grep -c \"removing from epoll\"); " +
      "echo \"$pid ${up:-0} ${lost:-0}\"' | head -c 256"]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (root._rawHealthBuffer.length < root.maxHealthBytes) {
          var remaining = root.maxHealthBytes - root._rawHealthBuffer.length
          root._rawHealthBuffer += String(line || "").slice(0, remaining)
        }
      }
    }
    onStarted: {
      root._rawHealthBuffer = ""
    }
    onExited: function(exitCode) {
      var parts = root._rawHealthBuffer.trim().split(/\s+/)
      root._rawHealthBuffer = ""
      if (parts.length >= 3 && parts[0] !== "") {
        root.workerPid = parseInt(parts[0], 10) || 0
        root.workerUptimeSec = parseInt(parts[1], 10) || 0
        root.lostDevices = parseInt(parts[2], 10) || 0
      } else {
        root.workerPid = 0
        root.workerUptimeSec = 0
        root.lostDevices = 0
      }
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
