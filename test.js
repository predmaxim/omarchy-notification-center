// node test.js
const fs = require("fs")
const assert = require("assert")
const load = f => fs.readFileSync(__dirname + "/" + f, "utf8").replace(".pragma library", "")
const M = new Function(load("Model.js") + "; return { sourceOf, isImportant, sources, activation, DEFAULT_IMPORTANT }")()

const web = (host, text) => ({ app: "Chromium", summary: "Эхо", body: `<a href="https://${host}/">${host}</a>\n\n${text}` })

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
assert.deepStrictEqual(M.activation(web("telemost.360.yandex.ru", "x"), P),
  ["/omarchy/bin/omarchy-launch-or-focus-webapp", "telemost.360.yandex.ru", "https://telemost.360.yandex.ru/"])
assert.deepStrictEqual(M.activation({ app: "Datebook" }, P), ["omarchy-shell", "predmaxim.datebook", "open"])
assert.deepStrictEqual(M.activation({ app: "Jira" }, P), ["omarchy-shell", "predmaxim.jira", "open"])
assert.deepStrictEqual(M.activation({ app: "omarchy-action", summary: "Reminder" }, P), ["/omarchy/bin/omarchy-reminder", "show"])
assert.deepStrictEqual(M.activation({ app: "Telegram Desktop" }, P), ["open-app", "Telegram Desktop"])
// The app name is the sender's to choose: nothing regex- or option-shaped gets through
assert.strictEqual(M.activation({ app: ".*" }, P), null)
assert.strictEqual(M.activation({ app: "-rf" }, P), null)
assert.strictEqual(M.activation({ app: "omarchy-action", summary: "Time to recharge!" }, P), null)

// Every tr() in the QML has a Russian line
const I = new Function(load("I18n.js") + "; return { TABLES }")()
const qml = ["Panel.qml", "components/NotificationRow.qml"].map(load).join("\n")
for (const m of qml.matchAll(/\btr\("((?:[^"\\]|\\.)*)"/g))
  assert.ok(Object.prototype.hasOwnProperty.call(I.TABLES.ru, JSON.parse(`"${m[1]}"`)), "no ru for: " + m[1])

console.log("ok")
