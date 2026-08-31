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
// Layout: hero with a settings gear + sign-out icon on its trailing edge;
// a horizontal carousel of vault badges ("All items" first); a "/" filter;
// then the item list, each login row carrying inline copy icons.
Panel {
  id: root
  moduleName: "io.github.doctahw.omaproton-pass"
  ipcTarget: "io.github.doctahw.omaproton-pass"
  manageIpc: false

  // ── Keyboard cursor: which region has focus, and where inside it ───────
  //   hero     — heroIndex 0=settings gear, 1=sign out
  //   settings — settingsIndex over the settings-strip controls (strip open)
  //   unlock   — the single "Unlock" row (locked session)
  //   vault    — vaultIndex over the badge carousel
  //   items    — itemIndex over rows, iconIndex over a row's copy icons
  property string focusSection: "header"
  property int heroIndex: 0
  property int settingsIndex: 0
  property int vaultIndex: 0
  property int itemIndex: 0
  property int iconIndex: 0
  property bool cursorActive: false

  // The settings strip under the hero (toggled by the gear).
  property bool settingsOpen: false

  // Text typed into the "/" filter. Narrows the vault's item list by title.
  property string filterQuery: ""
  readonly property var filteredItems: Model.filterItems(pass.items, filterQuery)
  // The item the cursor is on, after filtering.
  readonly property var focusedItem: filteredItems[itemIndex] || null

  // The copy icons the focused item offers (also the left/right order).
  readonly property var itemIcons: Model.copyIconsFor(focusedItem ? focusedItem.type : "")

  onItemIndexChanged: iconIndex = 0
  onFilterQueryChanged: { itemIndex = 0; iconIndex = 0; ensureCursor() }

  function itemKey(it) {
    return it ? (String(it.shareId) + "/" + String(it.id)) : ""
  }

  // One click / keypress = copy that field. The Service fetches the item's
  // detail if it isn't cached and copies once it lands.
  function copyItemIcon(it, kind) {
    if (!it || !kind) return
    pass.copyItemField(it.shareId, it.id, kind)
  }

  // The dropdown options: a synthetic "All items" first (only worth it
  // with more than one vault), then one entry per real vault. `vaultIndex`
  // indexes THIS list, not pass.vaults.
  readonly property var vaultOptions: {
    var out = pass.vaults.map(function(v) { return { value: v.shareId, label: v.name } })
    if (pass.vaults.length > 1) out.unshift({ value: pass.allVaultsId, label: "All items" })
    return out
  }

  readonly property string activeShareId:
    vaultOptions[vaultIndex] ? vaultOptions[vaultIndex].value : ""
  readonly property string activeVaultName:
    vaultOptions[vaultIndex] ? vaultOptions[vaultIndex].label : ""
  readonly property bool allView: activeShareId === pass.allVaultsId

  function selectVaultByShareId(shareId) {
    for (var i = 0; i < vaultOptions.length; i++) {
      if (vaultOptions[i].value === String(shareId)) { vaultIndex = i; return }
    }
  }

  function vaultNameFor(shareId) {
    for (var i = 0; i < pass.vaults.length; i++) {
      if (pass.vaults[i].shareId === String(shareId)) return pass.vaults[i].name
    }
    return ""
  }

  // The selected vault's items are loaded and non-empty — gates the filter
  // field and the section header.
  readonly property bool itemsReady:
    pass.loggedIn && pass.itemsShareId === activeShareId
    && !pass.itemsLoading && pass.items.length > 0
  // …and at least one survives the current filter — gates the "items"
  // cursor section and the rows themselves.
  readonly property bool hasVisibleItems: itemsReady && filteredItems.length > 0

  // Pull the selected vault's items whenever the selection changes (and the
  // panel is open). loadItems() serves its cache instantly on a re-visit.
  onActiveShareIdChanged: {
    itemIndex = 0
    iconIndex = 0
    filterQuery = ""
    if (opened && activeShareId !== "") pass.loadItems(activeShareId, false)
  }

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

  // Sign out is destructive (it clears the local session), so it takes two
  // clicks within five seconds — same rule as the VPN plugin.
  property bool signOutArmed: false
  Timer { id: signOutArm; interval: 5000; onTriggered: root.signOutArmed = false }
  function requestSignOut() {
    if (!signOutArmed) { signOutArmed = true; signOutArm.restart(); return }
    signOutArmed = false
    pass.logout()
  }

  // The settings strip as a flat list of controls, left-to-right / top-to-
  // bottom: the four clipboard-clear choices, then the notify off/on pair.
  readonly property var settingsControls: [
    { k: "clear", v: 0 }, { k: "clear", v: 15 }, { k: "clear", v: 30 }, { k: "clear", v: 60 },
    { k: "notify", v: false }, { k: "notify", v: true }
  ]

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (settingsOpen) {
      settingsIndex = Math.max(0, pass.clipboardClearChoices.indexOf(pass.clipboardClearSec))
    } else if (focusSection === "settings") {
      focusSection = "hero"; heroIndex = 0
    }
  }

  function applySettingsControl(i) {
    var c = settingsControls[i]
    if (!c) return
    if (c.k === "clear") pass.setClipboardClearSec(c.v)
    else pass.setNotifyOnCopy(c.v)
  }

  // Which sections exist right now, top to bottom, as data — the arrow-key
  // state machine just walks this list.
  function sectionList() {
    if (!pass.installed) return ["install"]
    if (!pass.loggedIn) return ["login"]
    var head = ["hero"]
    if (settingsOpen) head.push("settings")
    if (pass.sessionLocked) return head.concat(["unlock"])
    if (pass.vaults.length === 0) return head
    return head.concat(hasVisibleItems ? ["vault", "items"] : ["vault"])
  }

  function ensureCursor() {
    var list = sectionList()
    if (list.indexOf(focusSection) === -1) focusSection = list[0]
    heroIndex = Math.max(0, Math.min(1, heroIndex))
    settingsIndex = Math.max(0, Math.min(settingsControls.length - 1, settingsIndex))
    if (vaultIndex >= vaultOptions.length) vaultIndex = Math.max(0, vaultOptions.length - 1)
    if (vaultIndex < 0) vaultIndex = 0
    if (itemIndex >= filteredItems.length) itemIndex = Math.max(0, filteredItems.length - 1)
    if (itemIndex < 0) itemIndex = 0
    if (iconIndex >= itemIcons.length) iconIndex = Math.max(0, itemIcons.length - 1)
    if (iconIndex < 0) iconIndex = 0
  }

  // left/right moves within a section (hero buttons, settings choices,
  // vault badges, a row's copy icons); up/down moves between sections.
  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()

    if (dx !== 0) {
      if (focusSection === "hero") heroIndex = Math.max(0, Math.min(1, heroIndex + dx))
      else if (focusSection === "settings")
        settingsIndex = Math.max(0, Math.min(settingsControls.length - 1, settingsIndex + dx))
      else if (focusSection === "vault") {
        vaultIndex = Math.max(0, Math.min(vaultOptions.length - 1, vaultIndex + dx))
        scrollVaultIntoView()
      } else if (focusSection === "items")
        iconIndex = Math.max(0, Math.min(itemIcons.length - 1, iconIndex + dx))
      return
    }
    if (dy === 0) return

    var list = sectionList()
    var pos = list.indexOf(focusSection)
    var next = pos + (dy > 0 ? 1 : -1)
    if (next < 0 || next >= list.length) return
    focusSection = list[next]
    if (focusSection === "items") { itemIndex = 0; scrollCursorIntoView() }
    if (focusSection === "vault") scrollVaultIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "install") Qt.openUrlExternally("https://proton.me/pass/download/linux")
    else if (focusSection === "login") pass.login()
    else if (focusSection === "unlock") pass.unlock()
    else if (focusSection === "hero") { if (heroIndex === 0) toggleSettings(); else requestSignOut() }
    else if (focusSection === "settings") applySettingsControl(settingsIndex)
    else if (focusSection === "vault") { if (hasVisibleItems) { focusSection = "items"; itemIndex = 0; scrollCursorIntoView() } }
    else if (focusSection === "items") {
      var icon = itemIcons[iconIndex]
      if (icon) copyItemIcon(focusedItem, icon.kind)
    }
  }

  // Scroll the selected vault badge into view horizontally.
  function scrollVaultIntoView() {
    if (focusSection !== "vault" || !vaultRow || !vaultStrip) return
    var badge = vaultRow.children[vaultIndex]
    if (!badge) return
    Qt.callLater(function() {
      if (!badge) return
      var margin = Style.space(8)
      var left = badge.x
      var right = left + badge.width
      var viewLeft = vaultStrip.contentX
      var viewRight = viewLeft + vaultStrip.width
      var maxX = Math.max(0, vaultStrip.contentWidth - vaultStrip.width)
      if (left < viewLeft + margin) vaultStrip.contentX = Math.max(0, left - margin)
      else if (right > viewRight - margin) vaultStrip.contentX = Math.min(maxX, right + margin - vaultStrip.width)
    })
  }

  // Keep the selected row visible as the cursor walks the list (mirrors
  // the dropbox plugin's scrollCursorIntoView).
  function scrollCursorIntoView() {
    if (focusSection !== "items" || !itemColumn) return
    var item = itemColumn.children[itemIndex]
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(8)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    pass.panelOpen = opened
    if (opened) {
      cursorActive = false
      filterQuery = ""
      signOutArmed = false
      settingsOpen = false
      heroIndex = 0
      settingsIndex = 0
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
    // A fresh item list can be shorter than where the cursor sat, and it
    // may add or remove the "items" section entirely.
    function onItemsChanged() { root.ensureCursor() }
    function onItemsLoadingChanged() { root.ensureCursor() }
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
    contentWidth: panel.fittedContentWidth(Style.space(336))
    // Header (hero → filter) is fixed; only the item list scrolls, capped
    // so the panel doesn't grow past `Style.space(560)`.
    contentHeight: panel.fittedContentHeight(
      headerBox.implicitHeight
      + (root.hasVisibleItems ? Style.space(8) + Math.min(itemColumn.implicitHeight, Style.space(320)) : 0),
      Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The filter field owns the keyboard while it has focus — otherwise
      // every letter would drive the cursor instead of the input.
      blocked: filterField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      // Esc closes the settings strip first, then the panel.
      onCloseRequested: root.settingsOpen ? root.toggleSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/" && root.itemsReady) filterField.forceActiveFocus()
      }

      Item {
        anchors.fill: parent

        // Fixed header: hero, settings strip, sign-in/unlock rows, the
        // vault carousel and the filter. Everything down to the filter
        // stays put; only the list below scrolls.
        Column {
          id: headerBox
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(12)

          // Header / hero, with the settings gear + sign-out on its
          // trailing edge.
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            PanelHero {
              id: hero
              Layout.fillWidth: true
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

            HeroButton {
              visible: pass.loggedIn
              Layout.alignment: Qt.AlignTop
              glyph: "󰒓"
              tip: "Settings"
              active: root.settingsOpen
              hasCursor: root.cursorActive && root.focusSection === "hero" && root.heroIndex === 0
              onEntered: { root.cursorActive = true; root.focusSection = "hero"; root.heroIndex = 0 }
              onActivated: root.toggleSettings()
            }

            HeroButton {
              visible: pass.loggedIn
              Layout.alignment: Qt.AlignTop
              glyph: "󰍃"
              tip: root.signOutArmed ? "Click again to sign out" : "Sign out"
              urgentTint: root.signOutArmed
              hasCursor: root.cursorActive && root.focusSection === "hero" && root.heroIndex === 1
              Layout.rightMargin: -Style.space(4)
              onEntered: { root.cursorActive = true; root.focusSection = "hero"; root.heroIndex = 1 }
              onActivated: root.requestSignOut()
            }
          }

          // Settings strip (toggled by the gear).
          Column {
            visible: pass.loggedIn && root.settingsOpen
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: "Clear clipboard after copying a password"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                model: pass.clipboardClearChoices
                Button {
                  required property var modelData
                  required property int index
                  text: modelData === 0 ? "Off" : (modelData + "s")
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: pass.clipboardClearSec === modelData
                  hasCursor: root.cursorActive && root.focusSection === "settings" && root.settingsIndex === index
                  onClicked: {
                    root.cursorActive = true
                    root.focusSection = "settings"
                    root.settingsIndex = index
                    pass.setClipboardClearSec(modelData)
                  }
                }
              }
            }

            Text {
              width: parent.width
              text: "Desktop notification when a field is copied"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              topPadding: Style.space(4)
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                // index 0 → Off, 1 → On; global settingsIndex offset is 4.
                model: [{ label: "Off", on: false }, { label: "On", on: true }]
                Button {
                  required property var modelData
                  required property int index
                  text: modelData.label
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: pass.notifyOnCopy === modelData.on
                  hasCursor: root.cursorActive && root.focusSection === "settings"
                             && root.settingsIndex === 4 + index
                  onClicked: {
                    root.cursorActive = true
                    root.focusSection = "settings"
                    root.settingsIndex = 4 + index
                    pass.setNotifyOnCopy(modelData.on)
                  }
                }
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

          // Signed in but the session is lock-protected — reads fail until
          // `pass-cli unlock`.
          ActionRow {
            visible: pass.loggedIn && pass.sessionLocked
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "unlock"
            icon: "󰌾"
            title: "Unlock Proton Pass"
            subtitle: "Opens a terminal for your unlock password"
            onClicked: pass.unlock()
          }

          // Signed in and unlocked: vault carousel + filter (fixed).
          Column {
            id: listHeader
            visible: pass.loggedIn && !pass.sessionLocked && pass.vaults.length > 0
            width: parent.width
            spacing: Style.space(8)

            // Vault carousel: horizontally scrollable badges, "All items"
            // first. ←/→ walks them and scrolls the selection into view.
            Flickable {
              id: vaultStrip
              width: parent.width
              implicitHeight: vaultRow.implicitHeight
              contentWidth: vaultRow.implicitWidth
              contentHeight: vaultRow.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              interactive: contentWidth > width

              Row {
                id: vaultRow
                spacing: Style.space(6)

                Repeater {
                  model: root.vaultOptions
                  Button {
                    required property var modelData
                    required property int index
                    text: modelData.label
                    bordered: true
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    active: root.vaultIndex === index
                    hasCursor: root.cursorActive && root.focusSection === "vault" && root.vaultIndex === index
                    onClicked: {
                      root.cursorActive = true
                      root.focusSection = "vault"
                      root.vaultIndex = index
                      root.scrollVaultIntoView()
                    }
                  }
                }
              }
            }

            // Transient feedback for a copy that hit an empty field.
            Text {
              visible: pass.copyNote !== ""
              width: parent.width
              text: pass.copyNote
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Loading / empty / error line for the current vault.
            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              color: pass.itemsError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              text: {
                if (pass.itemsError !== "") return pass.itemsError
                if (pass.itemsLoading || pass.itemsShareId !== root.activeShareId) return "Loading items…"
                if (pass.items.length === 0)
                  return root.allView ? "No items yet." : "No items in “" + root.activeVaultName + "”."
                return ""
              }
            }

            // Filter, focused with "/". Same shape as the VPN plugin's
            // country filter.
            TextField {
              id: filterField
              visible: root.itemsReady
              width: parent.width
              foreground: root.foreground
              placeholderText: "Filter items  (press /)"
              text: root.filterQuery
              onTextChanged: root.filterQuery = text
              Keys.onEscapePressed: function(event) {
                if (text !== "") text = ""
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              // Down / Enter jumps into the list.
              Keys.onReturnPressed: function(event) {
                if (root.hasVisibleItems) {
                  root.cursorActive = true
                  root.focusSection = "items"
                  root.itemIndex = 0
                }
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
              Keys.onDownPressed: function(event) {
                if (root.hasVisibleItems) {
                  root.cursorActive = true
                  root.focusSection = "items"
                  root.itemIndex = 0
                }
                keyCatcher.forceActiveFocus()
                event.accepted = true
              }
            }

            Text {
              visible: root.itemsReady && root.filterQuery !== "" && root.filteredItems.length === 0
              width: parent.width
              text: "No items match “" + root.filterQuery + "”."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        // The only scrolling part: the item rows, below the fixed header.
        Flickable {
          id: panelFlick
          anchors.top: headerBox.bottom
          anchors.topMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: itemColumn.implicitHeight
          clip: true
          visible: root.hasVisibleItems
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: itemColumn
            width: panelFlick.width
            spacing: Style.space(4)

            Repeater {
              model: root.hasVisibleItems ? root.filteredItems : []
              ItemRow {
                required property var modelData
                required property int index
                width: itemColumn.width
                item: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  // A small icon button on the hero's trailing edge (settings, sign out).
  component HeroButton: CursorSurface {
    id: heroBtn
    property string glyph: ""
    property string tip: ""
    property bool active: false
    property bool urgentTint: false
    signal entered()
    signal activated()

    foreground: root.foreground
    implicitWidth: Style.space(28)
    implicitHeight: Style.space(28)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: heroBtn.entered()
      onClicked: heroBtn.activated()

      PanelToolTip {
        visible: parent.containsMouse
        text: heroBtn.tip
        fontFamily: root.fontFamily
      }
    }

    Text {
      anchors.centerIn: parent
      text: heroBtn.glyph
      color: heroBtn.urgentTint ? root.urgent
           : (heroBtn.active || heroBtn.hasCursor ? root.foreground : root.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
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

  // One Proton Pass item: type glyph + title + type label, and — for
  // logins — a cluster of inline copy icons on the trailing edge. Click an
  // icon (or ←/→ + Enter) to copy that field straight away.
  component ItemRow: CursorSurface {
    id: itemRow
    property var item: null
    property int rowIndex: 0
    readonly property string rowKey: root.itemKey(item)
    readonly property var icons: Model.copyIconsFor(item ? item.type : "")
    readonly property bool rowFocused:
      root.cursorActive && root.focusSection === "items" && root.itemIndex === rowIndex

    // The row itself only shows the cursor ring when no icon is targeted,
    // so the ring lands on one place at a time.
    hasCursor: rowFocused && icons.length === 0
    foreground: root.foreground
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        root.cursorActive = true
        root.focusSection = "items"
        root.itemIndex = itemRow.rowIndex
      }
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.typeGlyph(itemRow.item ? itemRow.item.type : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: itemRow.item ? itemRow.item.title : ""
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          // In the merged "All items" view, name the vault each item is in.
          text: {
            if (!itemRow.item) return ""
            var label = Model.typeLabel(itemRow.item.type)
            if (root.allView) {
              var v = root.vaultNameFor(itemRow.item.shareId)
              if (v !== "") return v + " · " + label
            }
            return label
          }
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Inline copy icons (logins only, for now).
      Row {
        spacing: Style.space(1)
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: -Style.space(4)

        Repeater {
          model: itemRow.icons
          IconButton {
            required property var modelData
            required property int index
            glyph: modelData.glyph
            tip: modelData.tip
            iconIdx: index
            row: itemRow
          }
        }
      }
    }
  }

  // A single inline copy icon. Copies its field on click; shows a check
  // for a moment after a successful copy of that exact field on this item.
  component IconButton: CursorSurface {
    id: iconBtn
    property string glyph: ""
    property string tip: ""
    property int iconIdx: 0
    property var row: null
    readonly property bool targeted:
      root.cursorActive && root.focusSection === "items"
      && root.itemIndex === row.rowIndex && root.iconIndex === iconIdx
    readonly property var kind: row && row.icons[iconIdx] ? row.icons[iconIdx].kind : ""
    readonly property bool justCopied:
      pass.copiedField === kind && pass.copiedKey === (row ? row.rowKey : "")

    hasCursor: targeted
    foreground: root.foreground
    implicitWidth: Style.space(22)
    implicitHeight: Style.space(24)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "items"
        root.itemIndex = iconBtn.row.rowIndex
        root.iconIndex = iconBtn.iconIdx
      }
      onClicked: {
        root.cursorActive = true
        root.focusSection = "items"
        root.itemIndex = iconBtn.row.rowIndex
        root.iconIndex = iconBtn.iconIdx
        root.copyItemIcon(iconBtn.row.item, iconBtn.kind)
      }

      PanelToolTip {
        visible: parent.containsMouse
        text: iconBtn.tip
        fontFamily: root.fontFamily
      }
    }

    Text {
      anchors.centerIn: parent
      text: iconBtn.justCopied ? "󰄬" : iconBtn.glyph
      color: iconBtn.justCopied || iconBtn.targeted ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
