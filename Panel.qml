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
// Marco 1: install/session/sign-in + a tab per vault.
// Marco 3: the Service loads a vault's items on demand.
// Marco 4: render those items as rows with a two-axis keyboard cursor.
// Marco 4b: the vault picker moved into a compact dropdown pinned to the
//           top-right of the hero, freeing the panel for the item list.
//           Copying a field is Marco 5.
Panel {
  id: root
  moduleName: "io.github.doctahw.omaproton-pass"
  ipcTarget: "io.github.doctahw.omaproton-pass"
  manageIpc: false

  // ── Keyboard cursor: which region has focus, and where inside it ───────
  property string focusSection: "header"
  property int vaultIndex: 0
  property int itemIndex: 0
  // Sub-cursor across the focused row's inline copy icons.
  property int iconIndex: 0
  property bool cursorActive: false

  // The copy icons the focused item offers (also the left/right order).
  readonly property var itemIcons:
    Model.copyIconsFor(pass.items[itemIndex] ? pass.items[itemIndex].type : "")

  onItemIndexChanged: iconIndex = 0

  function itemKey(it) {
    return it ? (String(it.shareId) + "/" + String(it.id)) : ""
  }

  // One click / keypress = copy that field. The Service fetches the item's
  // detail if it isn't cached and copies once it lands.
  function copyItemIcon(it, kind) {
    if (!it || !kind) return
    pass.copyItemField(it.shareId, it.id, kind)
  }

  // The vault whose tab is selected. "" until vaults arrive.
  readonly property string activeShareId:
    pass.vaults[vaultIndex] ? pass.vaults[vaultIndex].shareId : ""
  readonly property string activeVaultName:
    pass.vaults[vaultIndex] ? pass.vaults[vaultIndex].name : ""

  // { value: shareId, label: name } for the Dropdown.
  readonly property var vaultOptions: pass.vaults.map(function(v) {
    return { value: v.shareId, label: v.name }
  })

  function selectVaultByShareId(shareId) {
    for (var i = 0; i < pass.vaults.length; i++) {
      if (pass.vaults[i].shareId === String(shareId)) { vaultIndex = i; return }
    }
  }

  // True once the visible `items` really belong to the selected vault and
  // there's something to show — the gate for the "items" cursor section.
  readonly property bool itemsReady:
    pass.loggedIn && pass.itemsShareId === activeShareId
    && !pass.itemsLoading && pass.items.length > 0

  // Pull the selected vault's items whenever the selection changes (and the
  // panel is open). loadItems() serves its cache instantly on a re-visit.
  onActiveShareIdChanged: {
    itemIndex = 0
    iconIndex = 0
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

  // Which sections exist right now, top to bottom. Keeping this as data
  // (not scattered if-checks) is what makes arrow-key navigation simple.
  // "header" is only used as a fallback while there's nothing else to
  // focus — it has no visible cursor yet, so we never park on it when a
  // real target (the vault tabs) exists.
  function sectionList() {
    if (!pass.installed) return ["install"]
    if (!pass.loggedIn) return ["login"]
    if (pass.vaults.length === 0) return ["header"]
    return itemsReady ? ["vault", "items"] : ["vault"]
  }

  function ensureCursor() {
    var list = sectionList()
    if (list.indexOf(focusSection) === -1) focusSection = list[0]
    if (vaultIndex >= pass.vaults.length) vaultIndex = Math.max(0, pass.vaults.length - 1)
    if (vaultIndex < 0) vaultIndex = 0
    if (itemIndex >= pass.items.length) itemIndex = Math.max(0, pass.items.length - 1)
    if (itemIndex < 0) itemIndex = 0
    if (iconIndex >= itemIcons.length) iconIndex = Math.max(0, itemIcons.length - 1)
    if (iconIndex < 0) iconIndex = 0
  }

  // left/right: on the vault picker, step vaults; on an item row, move
  // across its copy icons. up/down: move between the picker and the list,
  // then through the items.
  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()

    if (dx !== 0 && focusSection === "vault") {
      vaultIndex = Math.max(0, Math.min(pass.vaults.length - 1, vaultIndex + dx))
      return
    }
    if (dx !== 0 && focusSection === "items") {
      iconIndex = Math.max(0, Math.min(itemIcons.length - 1, iconIndex + dx))
      return
    }
    if (dy === 0) return

    if (focusSection === "vault") {
      if (dy > 0 && itemsReady) { focusSection = "items"; itemIndex = 0; scrollCursorIntoView() }
      return
    }
    if (focusSection === "items") {
      if (dy < 0 && itemIndex === 0) { focusSection = "vault"; return }
      itemIndex = Math.max(0, Math.min(pass.items.length - 1, itemIndex + dy))
      scrollCursorIntoView()
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "install") Qt.openUrlExternally("https://proton.me/pass/download/linux")
    else if (focusSection === "login") pass.login()
    else if (focusSection === "vault") vaultPicker.toggle()
    else if (focusSection === "items") {
      var icon = itemIcons[iconIndex]
      if (icon) copyItemIcon(pass.items[itemIndex], icon.kind)
    }
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While the vault dropdown's popup is open it owns the keyboard
      // (its own list handles j/k/Enter/Esc) — same guard the VPN plugin
      // uses for its Mode/Apps popups.
      blocked: vaultPicker.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      // Esc backs out of an expanded item first, then closes the panel.
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

          // Header / hero, with the vault picker pinned to its top-right.
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

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

            Dropdown {
              id: vaultPicker
              visible: pass.loggedIn && pass.vaults.length > 0
              Layout.alignment: Qt.AlignTop
              Layout.preferredWidth: Style.space(150)
              showLabel: false
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: root.vaultOptions
              value: root.activeShareId
              hasCursor: root.cursorActive && root.focusSection === "vault"
              onChanged: function(v) { root.selectVaultByShareId(v) }
              onHovered: function(on) {
                if (on) { root.cursorActive = true; root.focusSection = "vault" }
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

          // Signed in: the selected vault's items.
          Column {
            visible: pass.loggedIn && pass.vaults.length > 0
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: root.activeVaultName.toUpperCase()
                textFormat: Text.PlainText
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }

              // Transient feedback for a copy that hit an empty field.
              Text {
                visible: pass.copyNote !== ""
                text: pass.copyNote
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
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
                if (pass.items.length === 0) return "No items in “" + root.activeVaultName + "”."
                return ""
              }
            }

            // The item rows.
            Column {
              id: itemColumn
              width: parent.width
              spacing: Style.space(4)
              visible: root.itemsReady

              Repeater {
                model: root.itemsReady ? pass.items : []
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
          text: itemRow.item ? Model.typeLabel(itemRow.item.type) : ""
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Inline copy icons (logins only, for now).
      Row {
        spacing: Style.space(2)
        Layout.alignment: Qt.AlignVCenter

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
    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)

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
