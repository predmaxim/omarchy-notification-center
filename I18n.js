.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("Copied: %1", x) fills in
// %1, %2… after the lookup. The same scheme as predmaxim.datebook: Quickshell
// plugins get no .qm catalogues, so Qt's qsTr isn't used.
var TABLES = {
  ru: {
    // The panel
    "Notifications": "Уведомления", "New": "Новых", "Settings": "Настройки",
    "Search…": "Поиск…", "Clear": "Очистить", "Empty the panel": "Очистить список",
    "Allow notifications": "Включить уведомления", "Silence notifications": "Не беспокоить",
    "Notifications silenced": "Уведомления выключены", "New: %1": "Новых: %1",
    "Reading the archive…": "Чтение архива…", "Nothing matches “%1”": "Ничего не найдено по «%1»",
    "Nothing has come in yet": "Уведомлений пока нет", "Shown %1 of %2": "Показано %1 из %2",
    "Today": "Сегодня", "Yesterday": "Вчера",
    // A notification
    "now": "сейчас", "%1m ago": "%1 мин назад",
    // Settings
    "Only important": "Только важные",
    "Show only the sources ticked below: messengers, mail, calendar, tasks, reminders":
      "Показывать только отмеченные ниже источники: мессенджеры, почту, календарь, задачи, напоминания",
    "SOURCES": "ИСТОЧНИКИ", "Reminders": "Напоминания"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
