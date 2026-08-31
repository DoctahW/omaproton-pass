import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Proton Pass state for the bar widget.
//
// Everything here is driven by the official `pass-cli`. Each call is a
// short-lived subprocess described as an argv LIST (never a shell string):
// that's the security rule for Omarchy plugins, which run unsandboxed as
// you. The one place a value crosses a shell boundary is the clipboard
// copy, and there it's `Util.shellQuote`-d first.
//
// Marco 1 scope: is the CLI installed, is there a session, and what vaults
// exist (those become the tabs). Item listing and copy land in later marcos.
Item {
  id: root

  // Injected by Panel.qml from the widget's manifest settings.
  property var settings: ({})
  // The panel sets this true/false so we only poll while it's open.
  property bool panelOpen: false

  // ── Observable state the Panel binds to ────────────────────────────────
  property bool installed: false
  property bool checkedInstalled: false
  property bool loggedIn: false
  // `pass-cli info` costs a round-trip, so until the first probe returns we
  // don't know — this stops the panel flashing "signed out" on open.
  property bool sessionProbed: false
  property string account: ""
  property string username: ""
  // A lock-protected session needs `pass-cli unlock` before reads work.
  // We surface it now; the unlock flow lands in a later marco.
  property bool sessionLocked: false

  property var vaults: []
  property bool vaultsLoaded: false

  property string lastError: ""

  // ── Settings helpers (same pattern as the dropbox/VPN plugins) ─────────
  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }
  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 45, 10, 3600)

  readonly property bool busy: infoProcess.running || vaultsProcess.running

  // ── Actions ───────────────────────────────────────────────────────────
  function refresh() {
    probeInstalled()
    if (installed) probeSession()
  }

  function probeInstalled() {
    if (whichProcess.running) return
    whichProcess.command = ["which", "pass-cli"]
    whichProcess.running = true
  }

  function probeSession() {
    if (infoProcess.running) return
    infoProcess.command = ["pass-cli", "info"]
    infoProcess.running = true
  }

  function loadVaults(force) {
    if (!installed || !loggedIn || vaultsProcess.running) return
    if (vaultsLoaded && force !== true) return
    vaultsProcess.command = ["pass-cli", "vault", "list", "--output", "json"]
    vaultsProcess.running = true
  }

  // Sign-in is interactive (password + TOTP), and pass-cli only takes those
  // from a real tty — so open a floating terminal, exactly like the VPN
  // plugin does for `protonvpn signin`. We pass no username; the CLI asks.
  function login() {
    if (!installed) return
    lastError = ""
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      "pass-cli login --interactive"
    ])
    // Poll for a while so the panel flips to signed-in on its own.
    loginWatch.restart()
  }

  function logout() {
    if (!installed || logoutProcess.running) return
    logoutProcess.command = ["pass-cli", "logout"]
    logoutProcess.running = true
  }

  // ── Timers ────────────────────────────────────────────────────────────
  Component.onCompleted: refresh()

  Timer {
    id: sessionTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.installed
    triggeredOnStart: true
    onTriggered: root.probeSession()
  }

  Timer {
    id: loginWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.probeSession()
      if (root.loggedIn || ticks > 40) stop()
    }
  }

  // ── Subprocesses ──────────────────────────────────────────────────────
  Process {
    id: whichProcess
    command: []
    onExited: function(code) {
      root.installed = code === 0
      root.checkedInstalled = true
      if (root.installed) root.probeSession()
    }
  }

  Process {
    id: infoProcess
    command: []
    stdout: StdioCollector { id: infoOut; waitForEnd: true }
    stderr: StdioCollector { id: infoErr; waitForEnd: true }
    onExited: function(code) {
      var was = root.loggedIn
      root.sessionProbed = true
      root.loggedIn = code === 0
      if (!root.loggedIn) {
        root.account = ""
        root.username = ""
        root.sessionLocked = false
        root.vaults = []
        root.vaultsLoaded = false
        return
      }
      var info = Model.parseInfo(String(infoOut.text || ""))
      root.account = info.email
      root.username = info.username
      root.sessionLocked = info.locked
      if (!was || !root.vaultsLoaded) root.loadVaults(true)
    }
  }

  Process {
    id: vaultsProcess
    command: []
    stdout: StdioCollector { id: vaultsOut; waitForEnd: true }
    stderr: StdioCollector { id: vaultsErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.lastError = Model.elide(String(vaultsErr.text || "") || "Could not list vaults")
        return
      }
      root.vaults = Model.parseVaults(String(vaultsOut.text || "[]"))
      root.vaultsLoaded = true
      root.lastError = ""
    }
  }

  Process {
    id: logoutProcess
    command: []
    onExited: function() { root.probeSession() }
  }
}
