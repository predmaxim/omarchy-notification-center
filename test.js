// node test.js
const fs = require("fs")
const assert = require("assert")
const load = f => fs.readFileSync(__dirname + "/" + f, "utf8").replace(".pragma library", "")
const M = new Function(load("Model.js") + "; return { sourceOf, isImportant, sources, webApp, siteClick, messageBody, siteRow, activation, popupPosition, popupPlacement, desktopIcon, DEFAULT_IMPORTANT }")()

const web = (host, text) => ({ app: "Chromium", summary: "Эхо", body: `<a href="https://${host}/">${host}</a>\n\n${text}` })

// A browser's message without the site link it puts first
assert.strictEqual(M.messageBody(web("telemost.360.yandex.ru", "New message")), "New message")
assert.strictEqual(M.messageBody({ app: "Google Chrome", body: '<a href="https://web.telegram.org/k/">web.telegram.org</a>\n\nПривет' }), "Привет")
assert.strictEqual(M.messageBody({ app: "Chromium", body: "no link" }), "no link")
assert.strictEqual(M.messageBody({ app: "Telegram Desktop", body: '<a href="https://x.org/">x.org</a> look' }), '<a href="https://x.org/">x.org</a> look')
assert.strictEqual(M.messageBody({ app: "Chromium" }), "")

// A site's row: sender (when the site names one first) and the message
assert.deepStrictEqual(M.siteRow(web("telemost.yandex.ru", ""), "Александр Гончаров: Магия в общем"), { sender: "Александр Гончаров", text: "Магия в общем" })
assert.deepStrictEqual(M.siteRow(web("telemost.360.yandex.ru", ""), "New message"), { sender: "", text: "New message" })
assert.deepStrictEqual(M.siteRow(web("telemost.360.yandex.ru", ""), "https://telemost.360.yandex.ru/j/1"), { sender: "", text: "https://telemost.360.yandex.ru/j/1" })
assert.deepStrictEqual(M.siteRow(web("telemost.360.yandex.ru", ""), "Forwarded message:"), { sender: "", text: "Forwarded message:" })
assert.deepStrictEqual(M.siteRow(web("web.telegram.org", ""), "Note: buy milk"), { sender: "", text: "Note: buy milk" })
assert.strictEqual(M.siteRow({ app: "Telegram Desktop", body: "Никита: привет" }, "Никита: привет"), null)
assert.strictEqual(M.siteRow({ app: "Chromium", body: "no link" }, "no link"), null)

// Where a notification came from
assert.strictEqual(M.sourceOf(web("telemost.360.yandex.ru", "New message")), "telemost.360.yandex.ru")
assert.strictEqual(M.sourceOf({ app: "Google Chrome", body: '<a href="https://web.telegram.org/k/">x</a>' }), "web.telegram.org")
assert.strictEqual(M.sourceOf({ app: "Chromium", body: "no link" }), "Chromium")
assert.strictEqual(M.sourceOf({ app: "Telegram Desktop", body: '<a href="https://evil.com/">x</a>' }), "Telegram Desktop")
assert.strictEqual(M.sourceOf({ app: "omarchy-action", summary: "Reminder", body: "Tea" }), "Reminders")
assert.strictEqual(M.sourceOf({ app: "omarchy-action", summary: "Time to recharge!" }), "omarchy-action")
assert.strictEqual(M.sourceOf({ app: "" }), "")

// Only the ticked sources pass
assert.ok(M.isImportant(web("telemost.360.yandex.ru", "hi"), M.DEFAULT_IMPORTANT))
assert.ok(M.isImportant({ app: "Datebook" }, M.DEFAULT_IMPORTANT))
assert.ok(!M.isImportant({ app: "omarchy-action", summary: "Workspace layout set to dwindle" }, M.DEFAULT_IMPORTANT))
assert.ok(!M.isImportant({ app: "Annotate" }, M.DEFAULT_IMPORTANT))
assert.ok(M.isImportant({ app: "Annotate" }, ["Annotate"]))

// The list in the settings: seen sources, then ticked ones not seen yet, no blanks or repeats
assert.deepStrictEqual(M.sources([{ app: "Annotate" }, web("vk.com", "x"), { app: "Annotate" }, { app: "" }], ["Jira", "vk.com"]),
  ["Annotate", "vk.com", "Jira"])

// What a click does
const P = "/omarchy"
// Telemost's web app starts at /chat: its service worker finds the window there
assert.deepStrictEqual(M.activation(web("telemost.360.yandex.ru", "x"), P),
  ["/omarchy/bin/omarchy-launch-or-focus-webapp", "chrome-telemost.360.yandex.ru__chat-Default", "https://telemost.360.yandex.ru/chat"])
assert.deepStrictEqual(M.activation(web("telemost.yandex.ru", "x"), P),
  ["/omarchy/bin/omarchy-launch-or-focus-webapp", "chrome-telemost.360.yandex.ru__chat-Default", "https://telemost.360.yandex.ru/chat"])
assert.deepStrictEqual(M.webApp(web("web.telegram.org", "x"), P),
  ["/omarchy/bin/omarchy-launch-or-focus-webapp", "chrome-web.telegram.org__-Default", "https://web.telegram.org/"])
// A site that opens the chat itself: the window its click needs, else ""
assert.strictEqual(M.siteClick(web("telemost.360.yandex.ru", "x")), "chrome-telemost.360.yandex.ru__chat-Default")
assert.strictEqual(M.siteClick(web("telemost.yandex.ru", "x")), "")
assert.strictEqual(M.siteClick(web("web.telegram.org", "x")), "")
assert.strictEqual(M.siteClick({ app: "Firefox", body: '<a href="https://telemost.360.yandex.ru/">x</a>' }), "")
assert.strictEqual(M.siteClick({ app: "Telegram Desktop" }), "")
assert.strictEqual(M.webApp({ app: "Datebook" }, P), null)
assert.strictEqual(M.webApp({ app: "Chromium", body: "no link" }, P), null)
// A site in another browser is its tab: the click goes to that browser
assert.deepStrictEqual(M.activation({ app: "Yandex", body: '<a href="https://calendar.360.yandex.ru/">calendar.360.yandex.ru</a>' }, P), ["open-app", "Yandex"])
assert.deepStrictEqual(M.activation({ app: "Yandex", body: "Яндекс.Погода" }, P), ["open-app", "Yandex"])
assert.deepStrictEqual(M.activation({ app: "Datebook" }, P), ["omarchy-shell", "predmaxim.datebook", "open"])
assert.deepStrictEqual(M.activation({ app: "Jira" }, P), ["omarchy-shell", "predmaxim.jira", "open"])
assert.deepStrictEqual(M.activation({ app: "omarchy-action", summary: "Reminder" }, P), ["/omarchy/bin/omarchy-reminder", "show"])
assert.deepStrictEqual(M.activation({ app: "Telegram Desktop" }, P), ["open-app", "Telegram Desktop"])
// The app name is the sender's to choose: nothing regex- or option-shaped gets through
assert.strictEqual(M.activation({ app: ".*" }, P), null)
assert.strictEqual(M.activation({ app: "-rf" }, P), null)
assert.strictEqual(M.activation({ app: "omarchy-action", summary: "Time to recharge!" }, P), null)

// Where toasts appear: read from this widget's entry in shell.json, wherever it sits
const cfg = pos => JSON.stringify({ bar: { right: [{ id: "x" }], center: [{ id: "jankeesvw.notification-center", popupPosition: pos }] } })
assert.strictEqual(M.popupPosition(cfg("bottom-left")), "bottom-left")
assert.strictEqual(M.popupPosition(cfg("middle")), "top-right")
assert.strictEqual(M.popupPosition(JSON.stringify({ bar: {} })), "top-right")
assert.strictEqual(M.popupPosition("{broken"), "top-right")
// Edges the toasts touch; the one the bar sits on is kept clear of it
assert.deepStrictEqual(M.popupPlacement("top-center", "top", 40, 10),
  { vertical: "top", horizontal: "center", margins: { top: 40, bottom: 10, left: 10, right: 10 } })
assert.deepStrictEqual(M.popupPlacement("bottom-left", "left", 40, 10),
  { vertical: "bottom", horizontal: "left", margins: { top: 10, bottom: 10, left: 40, right: 10 } })

// The app's own icon when the notification brought none: its .desktop by name, id or window class
const apps = [{ name: "Telegram Desktop", id: "org.telegram.desktop", icon: "telegram", startupClass: "org.telegram.desktop.desktop" },
  { name: "Files", id: "org.gnome.Nautilus", icon: "org.gnome.Nautilus", startupClass: "" },
  { name: "Blank", id: "blank", icon: "", startupClass: "" }]
assert.strictEqual(M.desktopIcon("telegram desktop", apps), "telegram")
assert.strictEqual(M.desktopIcon("org.gnome.Nautilus", apps), "org.gnome.Nautilus")
assert.strictEqual(M.desktopIcon("org.telegram.desktop.desktop", apps), "telegram")
assert.strictEqual(M.desktopIcon("Blank", apps), "")
assert.strictEqual(M.desktopIcon("notify-send", apps), "")
assert.strictEqual(M.desktopIcon("", apps), "")

// Every tr() in the QML has a Russian line
const I = new Function(load("I18n.js") + "; return { TABLES }")()
const qml = ["Panel.qml", "Indicator.qml", "components/NotificationRow.qml"].map(load).join("\n")
for (const m of qml.matchAll(/\btr\("((?:[^"\\]|\\.)*)"/g))
  assert.ok(Object.prototype.hasOwnProperty.call(I.TABLES.ru, JSON.parse(`"${m[1]}"`)), "no ru for: " + m[1])

console.log("ok")
