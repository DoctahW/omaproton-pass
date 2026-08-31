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
// Marco 1: installed? session? which vaults (the tabs)?
// Marco 3: list the items of one vault on demand — `pass-cli item list
//          --share-id <id> --output json` — cached per vault so flipping
//          between tabs doesn't re-shell every time. Rendering the list is
//          Marco 4; copy is Marco 5.
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

  // Items of the vault the panel is currently showing. Same shape as the
  // VPN plugin's server drill: one visible list plus which vault it's for.
  property var items: []
  property string itemsShareId: ""
  property bool itemsLoading: false
  property string itemsError: ""
  // shareId -> item[]  (a plain map; not bound, just a lookup so we don't
  // re-run the CLI every time the user toggles between two tabs).
  property var _itemCache: ({})
  // A request that arrived while another `item list` was still running.
  property string _pendingItemsShareId: ""

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

  readonly property bool busy: infoProcess.running || vaultsProcess.running || itemsProcess.running

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

  // Load one vault's items. Serves the cache immediately when we have it;
  // `force` (a manual refresh) skips the cache. If another `item list` is
  // already in flight, this one is remembered and run when it finishes.
  function loadItems(shareId, force) {
    var id = String(shareId || "")
    if (!installed || !loggedIn || id === "") return

    if (!force && _itemCache[id] !== undefined) {
      items = _itemCache[id]
      itemsShareId = id
      itemsLoading = false
      itemsError = ""
      return
    }
    if (itemsProcess.running) { _pendingItemsShareId = id; return }

    itemsShareId = id
    itemsLoading = true
    itemsError = ""
    itemsProcess.command = ["pass-cli", "item", "list", "--share-id", id, "--output", "json"]
    itemsProcess.running = true
  }

  function clearItemCache() { _itemCache = ({}) }

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
        root.items = []
        root.itemsShareId = ""
        root.clearItemCache()
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
    id: itemsProcess
    command: []
    stdout: StdioCollector { id: itemsOut; waitForEnd: true }
    stderr: StdioCollector { id: itemsErr; waitForEnd: true }
    onExited: function(code) {
      root.itemsLoading = false
      var id = root.itemsShareId
      if (code !== 0) {
        root.itemsError = Model.elide(String(itemsErr.text || "") || "Could not list items")
        root.items = []
      } else {
        var list = Model.parseItems(String(itemsOut.text || "[]"))
        root.items = list
        root.itemsError = ""
        // Cache under the vault we asked for. Mutating the object is fine —
        // nothing binds to _itemCache, we only ever look things up in it.
        var cache = root._itemCache
        cache[id] = list
        root._itemCache = cache
      }
      // Pick up a request that landed while we were busy.
      if (root._pendingItemsShareId !== "" && root._pendingItemsShareId !== id) {
        var next = root._pendingItemsShareId
        root._pendingItemsShareId = ""
        root.loadItems(next, false)
      } else {
        root._pendingItemsShareId = ""
      }
    }
  }

  Process {
    id: logoutProcess
    command: []
    onExited: function() { root.probeSession() }
  }
}
