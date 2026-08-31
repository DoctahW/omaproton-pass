// Pure helpers for parsing `pass-cli` output. No state, no QML — just
// functions, so they're easy to reason about and test in isolation.
//
// pass-cli speaks JSON with `--output json`, so unlike the VPN plugin we
// don't hand-parse tables. We still stay tolerant: a shape we don't
// recognise returns an empty result instead of throwing.

.pragma library

// `pass-cli info` prints plain lines, not JSON:
//   - Release track: stable
//   - ID: ...
//   - Username: euclides.dev
//   - Email: joao@eucli.dev
//   - Session has lock: no
// Exit code 0 already tells us there's a session; this pulls out the
// details we show, and whether the session is lock-protected.
function parseInfo(raw) {
  var out = { username: "", email: "", locked: false }
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s*-\s*/, "").trim()
    var idx = line.indexOf(":")
    if (idx <= 0) continue
    var key = line.substring(0, idx).trim().toLowerCase()
    var value = line.substring(idx + 1).trim()
    if (key === "username") out.username = value
    else if (key === "email") out.email = value
    else if (key === "session has lock") out.locked = /^yes$/i.test(value)
  }
  return out
}

// `pass-cli vault list --output json`
//   { "vaults": [ { "name", "vault_id", "share_id" }, ... ] }
function parseVaults(raw) {
  var out = []
  try {
    var data = JSON.parse(String(raw || "{}"))
    var list = data && Array.isArray(data.vaults) ? data.vaults : []
    for (var i = 0; i < list.length; i++) {
      var v = list[i] || {}
      var shareId = String(v.share_id || "")
      var name = String(v.name || "")
      if (shareId === "" || name === "") continue
      out.push({ name: name, shareId: shareId, vaultId: String(v.vault_id || "") })
    }
  } catch (e) {
    return []
  }
  return out
}

// `pass-cli item list --output json`
//   { "items": [ { "id", "share_id", "title", "item_type", "state", ... } ] }
// We keep only active items and normalise the fields the panel needs.
function parseItems(raw) {
  var out = []
  try {
    var data = JSON.parse(String(raw || "{}"))
    var list = data && Array.isArray(data.items) ? data.items : []
    for (var i = 0; i < list.length; i++) {
      var it = list[i] || {}
      if (String(it.state || "Active") !== "Active") continue
      var id = String(it.id || "")
      if (id === "") continue
      out.push({
        id: id,
        shareId: String(it.share_id || ""),
        title: String(it.title || "Untitled"),
        type: String(it.item_type || "login")
      })
    }
  } catch (e) {
    return []
  }
  return out
}

// `pass-cli item view "pass://<shareId>/<id>" --output json`
//   { "item": { "content": { "content": { "Login": { email, username,
//     password, urls[], totp_uri } } } } }
// The inner `content.content` is a tagged union keyed by the type name
// ("Login", "Note", "CreditCard", ...). We only dig into Login for now.
function parseItemDetail(raw) {
  var empty = { username: "", email: "", password: "", totpUri: "", urls: [] }
  try {
    var data = JSON.parse(String(raw || "{}"))
    var c = data && data.item && data.item.content ? data.item.content : null
    var inner = c && c.content ? c.content : null
    var login = inner && inner.Login ? inner.Login : null
    if (!login) return empty
    return {
      username: String(login.username || ""),
      email: String(login.email || ""),
      password: String(login.password || ""),
      totpUri: String(login.totp_uri || ""),
      urls: Array.isArray(login.urls) ? login.urls.map(String) : []
    }
  } catch (e) {
    return empty
  }
}

// What we actually put on the clipboard for "copy username": the username
// if there is one, otherwise the email (Proton Pass logins often fill only
// one of the two).
function loginIdentifier(detail) {
  if (!detail) return ""
  return detail.username !== "" ? detail.username : detail.email
}

// A Nerd Font glyph per item type, so the list reads at a glance.
function typeGlyph(type) {
  switch (String(type || "")) {
    case "login": return "󰖏"        // nf-md-key
    case "note": return "󰕰"          // nf-md-note_text
    case "credit_card": return "󰂱"   // nf-md-credit_card
    case "alias": return "󰙙"         // nf-md-at
    case "identity": return "󰄄"      // nf-md-card_account_details
    default: return "󰖏"
  }
}

// Trim a long CLI error to one tidy line for the status row.
function elide(text, max) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  var limit = max || 140
  return value.length > limit ? value.substring(0, limit - 1) + "…" : value
}
