.pragma library
// Which notifications are worth keeping, and what a click on one opens.
//
// A notification's "source" is who you would say sent it: the app, except
// that a browser speaks for every site open in it (the site is the link the
// browser puts first in the body), and omarchy-action speaks for the whole
// desktop, of which only fired reminders are worth a second look.

// Ticked on a fresh install: messengers, mail, calendar, tasks, reminders.
// Sources that never show up cost nothing here.
var DEFAULT_IMPORTANT = [
  "Telegram Desktop", "Telegram", "Datebook", "Jira", "Reminders", "Evolution", "Thunderbird",
  "telemost.360.yandex.ru", "messenger.360.yandex.ru", "mail.yandex.ru", "calendar.yandex.ru",
  "web.telegram.org", "web.whatsapp.com", "vk.com", "web.max.ru", "calendar.google.com", "mail.google.com"
]

var BROWSER = /chrom|firefox|brave|vivaldi|opera|edge|yandex/i
var SITE = /^\s*<a href="https?:\/\/([a-z0-9.-]+)[\/:"]/i
// Shell plugins that sent the notification get their own panel back.
var PANELS = { "Datebook": "predmaxim.datebook", "Jira": "predmaxim.jira" }

function sourceOf(entry) {
  var app = String(entry.app || "")
  if (BROWSER.test(app)) {
    var site = SITE.exec(String(entry.body || ""))
    if (site) return site[1].toLowerCase()
  }
  if (app === "omarchy-action" && entry.summary === "Reminder") return "Reminders"
  return app
}

// The message itself: a browser's body without the site link it puts first,
// as the toast shows it (the stock service drops that link too).
function messageBody(entry) {
  var body = String(entry.body || "")
  return BROWSER.test(String(entry.app || "")) ? body.replace(/^\s*<a\b[^>]*>[^<]*<\/a>\s*/i, "") : body
}

// Sites that put the sender first in the message: "Имя: текст".
var SENDER_FIRST = ["telemost.360.yandex.ru", "telemost.yandex.ru"]

// A site's row has the title on top (the browser's name says nothing), then
// the sender when the site names one, then the message without that name.
// text is the message as the row shows it. null for an app's notification,
// whose row keeps the app's name above the title.
function siteRow(entry, text) {
  var app = String(entry.app || ""), source = sourceOf(entry)
  if (!BROWSER.test(app) || source === app) return null
  var named = SENDER_FIRST.indexOf(source) >= 0 ? /^([^:]{1,64}): (.+)$/.exec(text) : null
  return named ? { sender: named[1], text: named[2] } : { sender: "", text: text }
}

function isImportant(entry, important) {
  return important.indexOf(sourceOf(entry)) >= 0
}

// Senders seen in the archive, newest first, then ticked ones not seen yet.
function sources(entries, important) {
  var out = []
  var all = entries.map(sourceOf).concat(important)
  for (var i = 0; i < all.length; i++)
    if (all[i] !== "" && out.indexOf(all[i]) < 0) out.push(all[i])
  return out
}

// Sites whose notifications belong to another site's web app: Telemost's
// meeting pages (telemost.yandex.ru) also send the messenger's messages.
var WEBAPP_OF = { "telemost.yandex.ru": "telemost.360.yandex.ru" }

// Web apps run in Chromium (omarchy-launch-webapp); a site in another browser
// is a tab there, and the click goes to that browser's window.
var WEBAPP_BROWSER = /chrom/i

// Web apps that start at a page other than the site's root (the path is also
// in the window class). Telemost's service worker looks for the messenger
// window by "/chat" in its address, so it can open the right chat there.
var WEBAPP_PATH = { "telemost.360.yandex.ru": "chat" }

// A site's notification opens its web app, or null for anything else. The
// pattern is the app's window class: launch-or-focus wraps it in \b, and in the
// class the domain goes on with "_", so a bare domain never matches.
function webApp(entry, omarchyPath) {
  var source = sourceOf(entry)
  if (!WEBAPP_BROWSER.test(String(entry.app || "")) || source === entry.app || !/^[a-z0-9][a-z0-9.-]*$/.test(source)) return null
  source = WEBAPP_OF[source] || source
  var path = WEBAPP_PATH[source] || ""
  return [omarchyPath + "/bin/omarchy-launch-or-focus-webapp", "chrome-" + source + "__" + path + "-Default", "https://" + source + "/" + path]
}

// Sites that open the right chat in their own web app window when Chromium
// passes the click on to them (its "default" action). Not WEBAPP_OF ones: the
// click goes to the sending site, which then finds no window of its own and
// opens a plain browser window.
var SITE_CLICK = ["telemost.360.yandex.ru"]

// The web app window such a site's click needs, or "" for any other sender.
function siteClick(entry) {
  var app = webApp(entry, "")
  return app && SITE_CLICK.indexOf(sourceOf(entry)) >= 0 ? app[1] : ""
}

// The command a click runs, as argv, or null. "open-app" is the store
// script's subcommand: focus the app's window, or start it from its .desktop.
// Everything here came from the sender, so only name-shaped values pass, and
// they go out as arguments, never through a shell.
function activation(entry, omarchyPath) {
  var site = webApp(entry, omarchyPath)
  if (site) return site
  var source = BROWSER.test(String(entry.app || "")) ? String(entry.app) : sourceOf(entry)
  if (source === "Reminders") return [omarchyPath + "/bin/omarchy-reminder", "show"]
  if (PANELS[source]) return ["omarchy-shell", PANELS[source], "open"]
  if (source === "omarchy-action") return null
  if (/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(source)) return ["open-app", source]
  return null
}

// Where the toasts appear. The toasts are drawn by the notifications service
// (my clone, predmaxim.notifications), which reads the choice from this
// widget's entry in shell.json.
var POSITIONS = ["top-left", "top-center", "top-right", "bottom-left", "bottom-right"]
var ID = "jankeesvw.notification-center"

function popupPosition(shellJson) {
  var found = ""
  function walk(node) {
    if (!node || typeof node !== "object" || found) return
    if (node.id === ID && POSITIONS.indexOf(node.popupPosition) >= 0) found = node.popupPosition
    for (var key in node) walk(node[key])
  }
  try { walk(JSON.parse(shellJson)) } catch (e) {}
  return found || "top-right"
}

// The edges the toast column sticks to and the gap to each screen edge: the
// edge the bar sits on is kept clear of the bar.
function popupPlacement(position, barPosition, barClearance, gapsOut) {
  var parts = String(position).split("-")
  var margins = {}
  ;["top", "bottom", "left", "right"].forEach(function(edge) {
    margins[edge] = edge === barPosition ? barClearance : gapsOut
  })
  return { vertical: parts[0], horizontal: parts[1], margins: margins }
}

// The icon of the app that sent a notification without one: its .desktop,
// found by name, id or window class the way `notification-center open-app`
// finds it. entries are Quickshell DesktopEntry objects. "" when none.
function desktopIcon(app, entries) {
  var key = String(app || "").toLowerCase()
  if (key === "") return ""
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if ([e.name, e.id, e.startupClass].some(function(v) { return String(v || "").toLowerCase() === key }))
      return String(e.icon || "")
  }
  return ""
}
