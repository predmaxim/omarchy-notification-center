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

// The command a click runs, as argv, or null. "open-app" is the store
// script's subcommand: focus the app's window, or start it from its .desktop.
// Everything here came from the sender, so only name-shaped values pass, and
// they go out as arguments, never through a shell.
function activation(entry, omarchyPath) {
  var source = sourceOf(entry)
  if (source !== entry.app && /^[a-z0-9][a-z0-9.-]*$/.test(source))
    return [omarchyPath + "/bin/omarchy-launch-or-focus-webapp", source, "https://" + source + "/"]
  if (source === "Reminders") return [omarchyPath + "/bin/omarchy-reminder", "show"]
  if (PANELS[source]) return ["omarchy-shell", PANELS[source], "open"]
  if (source === "omarchy-action") return null
  if (/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$/.test(source)) return ["open-app", source]
  return null
}
