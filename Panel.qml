import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// OmaProton Pass — bar widget + panel, one file (same as the VPN plugin).
//
// Marco 1: the shell of the thing. A bar icon that opens a panel; the panel
// shows whether pass-cli is installed and signed in, offers sign-in, and
// renders one tab (pill) per vault. Item lists and copy actions come next.
Panel {
  id: root
  moduleName: "io.github.doctahw.omaproton-pass"
  ipcTarget: "io.github.doctahw.omaproton-pass"
  manageIpc: false

  // ── Keyboard cursor: which region has focus, and where inside it ───────
  property string focusSection: "header"
  property int vaultIndex: 0
  property bool cursorActive: false

  // The vault whose tab is selected. "" until vaults arrive.
  readonly property string activeShareId:
    pass.vaults[vaultIndex] ? pass.vaults[vaultIndex].shareId : ""
  readonly property string activeVaultName:
    pass.vaults[vaultIndex] ? pass.vaults[vaultIndex].name : ""

  // Pull the selected vault's items whenever the selection changes (and the
  // panel is open). loadItems() serves its cache instantly on a re-visit.
  onActiveShareIdChanged: if (opened && activeShareId !== "") pass.loadItems(activeShareId, false)

  // ── Theme shortcuts (identical to the dropbox/VPN plugins) ────────────
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: pass.loggedIn ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property string heroMeta: {
    if (!pass.checkedInstalled) return "Checking…"
    if (!pass.installed) return "pass-cli not installed"
    if (!pass.sessionProbed) return "Checking…"
    if (!pass.loggedIn) return "Signed out"
    return pass.account !== "" ? pass.account : "Unlocked"
  }

  // Which sections exist right now, top to bottom. Keeping this as data
  // (not scattered if-checks) is what makes arrow-key navigation simple.
  // "header" is only used as a fallback while there's nothing else to
  // focus — it has no visible cursor yet, so we never park on it when a
  // real target (the vault tabs) exists.
  function sectionList() {
    if (!pass.installed) return ["install"]
    if (!pass.loggedIn) return ["login"]
    if (pass.vaults.length > 0) return ["vaults"]
    return ["header"]
  }

  function ensureCursor() {
    var list = sectionList()
    if (list.indexOf(focusSection) === -1) focusSection = list[0]
    if (vaultIndex >= pass.vaults.length) vaultIndex = Math.max(0, pass.vaults.length - 1)
    if (vaultIndex < 0) vaultIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    // One row of pills for now, so either axis nudges the selection. When
    // the item list arrives (Marco 4) this grows a real vertical axis.
    var step = dx !== 0 ? dx : dy
    if (step === 0) return
    if (focusSection === "vaults") {
      vaultIndex = Math.max(0, Math.min(pass.vaults.length - 1, vaultIndex + step))
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "install") Qt.openUrlExternally("https://proton.me/pass/download/linux")
    else if (focusSection === "login") pass.login()
    // "vaults" activation (open the vault's item list) arrives in Marco 4.
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    pass.panelOpen = opened
    if (opened) {
      cursorActive = false
      if (panelFlick) panelFlick.contentY = 0
      pass.refresh()
      pass.loadVaults(false)
      ensureCursor()
      if (activeShareId !== "") pass.loadItems(activeShareId, false)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: pass
    settings: root.settings
  }

  Connections {
    target: pass
    function onLoggedInChanged() { root.ensureCursor() }
    function onVaultsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { pass.refresh(); return "ok" }
    function status(): string { return root.heroMeta }
  }

  // ── The bar icon ──────────────────────────────────────────────────────
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        PassIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: pass.loggedIn ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) pass.refresh()
      else root.toggle()
    }
  }

  // ── The panel ─────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
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
          spacing: Style.space(12)

          // Header / hero
          PanelHero {
            id: hero
            width: parent.width
            title: "Proton Pass"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              PassIcon {
                iconSize: Style.font.display
                color: root.foreground
                opacity: pass.loggedIn ? 1.0 : 0.55
              }
            }
          }

          // Error / status line
          Text {
            visible: pass.lastError !== ""
            width: parent.width
            text: pass.lastError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Not installed
          ActionRow {
            visible: pass.checkedInstalled && !pass.installed
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "install"
            icon: "󰕺"
            title: "Install Proton Pass CLI"
            subtitle: "pass-cli isn't on PATH — opens the download page"
            onClicked: root.activateCursor()
          }

          // Signed out
          ActionRow {
            visible: pass.installed && pass.sessionProbed && !pass.loggedIn
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "login"
            icon: "󰆏"
            title: "Sign in to Proton Pass"
            subtitle: "Opens a terminal for your password and 2FA code"
            onClicked: pass.login()
          }

          // Signed in: one pill per vault
          Column {
            visible: pass.loggedIn && pass.vaults.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "VAULTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Flow {
              id: vaultFlow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: pass.vaults
                Button {
                  required property var modelData
                  required property int index
                  text: modelData.name
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: root.vaultIndex === index
                  hasCursor: root.cursorActive && root.focusSection === "vaults" && root.vaultIndex === index
                  onClicked: {
                    root.cursorActive = true
                    root.focusSection = "vaults"
                    root.vaultIndex = index
                  }
                }
              }
            }

            // Marco 3 proof-of-life: the item pipeline works, shown as a
            // count. The actual list of rows is Marco 4.
            Text {
              width: parent.width
              textFormat: Text.PlainText
              color: pass.itemsError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              text: {
                if (pass.itemsError !== "") return pass.itemsError
                if (pass.itemsLoading) return "Loading items…"
                if (pass.itemsShareId !== root.activeShareId) return ""
                var n = pass.items.length
                return n + (n === 1 ? " item" : " items") + " in “" + root.activeVaultName + "” — list in Marco 4"
              }
            }
          }
        }
      }
    }
  }

  // A clickable row with icon + title + subtitle, same shape the VPN plugin
  // uses for install / sign-in / quick-connect so everything reads alike.
  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    signal clicked()

    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionRow.clicked()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        visible: actionRow.icon !== ""
        text: actionRow.icon
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.title
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          visible: actionRow.subtitle !== ""
          text: actionRow.subtitle
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
