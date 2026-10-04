import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

import "components"
import "Model.js" as Model
import "I18n.js" as I18n

// A notification center for Omarchy: everything you were sent, still there
// when you go back for it.
//
// Omarchy already writes every notification to disk: one JSON file per popup
// under ~/.local/state/omarchy/notifications/, moved into history/ when it
// leaves the screen. That is where these come from, and nothing here writes to
// those directories. What it is not is a history you can read: it holds ten
// files, deletes the eleventh, and deletes the icon it was keeping for it at
// the same time. Ten is the right number for a service whose job is replaying
// the toasts you just missed, and far too few for the question this panel
// exists to answer, which is "what did that say".
//
// So `bin/notification-center` copies each file out of there the moment it
// lands, into an archive kept for as long as you asked for, icon and all. It
// follows the directory with inotify rather than polling it, so a notification
// is in the archive before its toast has finished appearing.
//
// Glyphs are \u escapes rather than literal characters, so the source survives
// editors and patches that mangle private-use codepoints.
Panel {
  id: root

  moduleName: "jankeesvw.notification-center"
  ipcTarget: "jankeesvw.notification-center"

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ----------------------------------------------------------------- settings

  readonly property int panelWidth: setting("panelWidth", 420)
  readonly property int keepDays: setting("keepDays", 30)
  readonly property int maxItems: setting("maxItems", 1000)
  readonly property string clickAction: setting("clickAction", "Auto")
  readonly property bool showBody: setting("showBody", true)
  readonly property bool showPreview: setting("showPreview", true)
  // Only notifications from the ticked sources are shown and counted as new;
  // the archive still keeps everything, so ticking one brings its past back.
  readonly property bool onlyImportant: setting("onlyImportant", true)
  readonly property var important: setting("important", Model.DEFAULT_IMPORTANT)
  // Where the toasts appear; the notifications service reads it from shell.json.
  readonly property string popupPosition: setting("popupPosition", "top-right")

  // Interface text in the system's language (I18n.js).
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))

  // Same write path as the built-in clock: the value lands inline on this
  // widget's shell.json entry and comes back through setting().
  function saveSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleSource(source) {
    var next = important.slice()
    var i = next.indexOf(source)
    if (i >= 0) next.splice(i, 1)
    else next.push(source)
    saveSetting("important", next)
  }

  function sourceLabel(source) {
    if (source === "Reminders") return tr("Reminders")
    if (source === "omarchy-action") return "Omarchy"
    return source
  }

  // ------------------------------------------------------------- the service
  //
  // Only for Do Not Disturb, which belongs to whoever is receiving the
  // notifications rather than to whoever is keeping them. A cloned service is
  // enabled under its own id, so the built-in name has to be resolved to
  // whichever copy is actually running, or the toggle silently does nothing on
  // exactly the machines that cared enough to clone it.
  // Do Not Disturb. The shell hands its notification service only to its
  // own plugins, so the state is read from the file the service keeps it in,
  // and toggled with the same command as Omarchy's key for it.
  property bool dnd: false

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.dnd = JSON.parse(text()).dnd === true } catch (e) {}
    }
  }

  // Silenced: the bell is crossed out and red, on the bar and in the panel.
  // The theme's alert colour (urgent), not its "red": themes set that to anything.
  readonly property color silencedColor: Color.urgent
  function toggleDnd() {
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-toggle-notification-silencing"])
  }

  // ------------------------------------------------------------- the store
  //
  // The archive is a shell service, not a child of this widget. Omarchy
  // builds a bar per monitor, and a Process in here would be one watcher
  // per screen: unread and clear would stick to whichever copy you clicked.
  property var store: null

  function bindStore() {
    if (store) {
      pushSettings()
      return
    }
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("jankeesvw.notification-center")
    if (!s) return
    store = s
    pushSettings()
    rebuild()
  }

  function pushSettings() {
    if (!store) return
    store.keepDays = keepDays
    store.maxItems = maxItems
    store.showPreview = showPreview
  }

  onBarChanged: bindStore()
  onKeepDaysChanged: pushSettings()
  onMaxItemsChanged: pushSettings()
  onShowPreviewChanged: pushSettings()

  Timer {
    interval: 200
    running: root.store === null
    repeat: true
    onTriggered: root.bindStore()
  }

  Connections {
    target: root.store
    function onEntryAdded(entry) { root.handleEntryAdded(entry) }
    function onEntriesReset() { root.rebuild() }
  }

  // -------------------------------------------------------------------- state

  readonly property var entries: store ? store.entries : []
  property string filter: ""
  // What the rows are marked against. Opening the center makes everything in
  // it read, so marking against `lastSeen` would mean the list never once
  // shows you which of these you had not seen, because the marks would be gone by the
  // time it finished drawing. This holds the reading from the moment before
  // you opened it, which is the question you were asking.
  property double readMark: 0
  readonly property bool loaded: store ? store.loaded : false
  property bool settingsOpen: false
  // The row picked with Up/Down, -1 for none.
  property int cursor: -1
  property double now: Date.now()

  // The store counts everything; only what this panel would show is news.
  readonly property int unread: countSince(lastSeen)
  // What was new when the panel opened; opening marks everything read.
  readonly property int freshCount: countSince(readMark)

  function countSince(mark) {
    var count = 0
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].timestamp <= mark) break
      if (passes(entries[i])) count++
    }
    return count
  }
  readonly property double lastSeen: store ? store.lastSeen : 0

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  function moveCursor(step) {
    var next = cursor + step
    if (next < -1 || next >= rows.count) return
    cursor = next
    if (cursor >= 0) list.positionViewAtIndex(cursor, ListView.Contain)
    else list.positionViewAtBeginning()
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (!settingsOpen) Qt.callLater(function() { if (root.opened) search.forceActiveFocus() })
  }

  Process { id: focusProc }

  function remove(key) {
    if (store) store.remove(key)
  }

  function clearAll() {
    if (store) store.clearAll()
  }

  function handleEntryAdded(entry) {
    if (!entry || !entry.key) return
    if (root.opened && store) store.markSeen()
    if (!matches(entry)) return
    rows.insert(0, rowFor(entry))
    if (root.opened && list.atYBeginning) Qt.callLater(function() {
      if (root.opened) list.positionViewAtBeginning()
    })
  }

  // ----------------------------------------------------------------- the list

  ListModel { id: rows }

  function passes(entry) {
    return !onlyImportant || Model.isImportant(entry, important)
  }

  function matches(entry) {
    if (!passes(entry)) return false
    if (filter === "") return true
    var needle = filter.toLowerCase()
    return String(entry.app || "").toLowerCase().indexOf(needle) >= 0
        || String(entry.summary || "").toLowerCase().indexOf(needle) >= 0
        || String(entry.body || "").toLowerCase().indexOf(needle) >= 0
  }

  function rowFor(entry) {
    return {
      key: String(entry.key || ""),
      app: String(entry.app || ""),
      appIcon: String(entry.appIcon || ""),
      summary: String(entry.summary || ""),
      body: String(entry.body || ""),
      image: String(entry.image || ""),
      preview: String(entry.preview || ""),
      file: String(entry.file || ""),
      glyph: String(entry.glyph || ""),
      urgency: Number(entry.urgency || 0),
      timestamp: Number(entry.timestamp || 0),
      day: dayOf(Number(entry.timestamp || 0)),
      time: Qt.formatDateTime(new Date(Number(entry.timestamp || 0)), "HH:mm")
    }
  }

  function rebuild() {
    cursor = -1
    rows.clear()
    for (var i = 0; i < entries.length; i++)
      if (matches(entries[i])) rows.append(rowFor(entries[i]))
  }

  onFilterChanged: rebuild()
  onOnlyImportantChanged: rebuild()
  onImportantChanged: rebuild()

  // The heading a notification is filed under. Days rather than hours, because
  // what you remember about a notification you are hunting for is which day it
  // was, and because a list broken into hours is a list that is mostly
  // headings.
  function dayOf(timestamp) {
    var when = new Date(timestamp)
    var now = new Date()
    var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    if (timestamp >= midnight) return tr("Today")
    if (timestamp >= midnight - 86400000) return tr("Yesterday")
    // Within the week the weekday is the better handle: "Tuesday" is how you
    // remember it, "17 August" is how you would have to work it out.
    if (timestamp >= midnight - 6 * 86400000) return Qt.formatDateTime(when, "dddd")
    if (when.getFullYear() === now.getFullYear()) return Qt.formatDateTime(when, "d MMMM")
    return Qt.formatDateTime(when, "d MMMM yyyy")
  }

  // --------------------------------------------------------------- activating

  // What a click on an old notification should do.
  //
  // Not what the notification asked for. A notification arrives carrying a
  // shell command, chosen by whoever sent it, and anything on this machine can
  // send one. Keeping that command and running it later is an attacker's
  // command waiting for a click, which is worth nothing next to the one thing
  // people actually want back: the picture. So what the store keeps is at most
  // an absolute path to an image, and that is opened by argument rather than
  // through a shell, so a hostile path is a file that fails to open instead of
  // a command that runs.
  function activate(row) {
    if (!row || clickAction === "Nothing") return
    if (clickAction === "Auto" && row.file !== "") {
      Quickshell.execDetached(["xdg-open", row.file])
      root.close()
      return
    }
    // Who sent it decides where to go: a site's web app, a shell plugin's
    // panel, or the app's window (started if it has none). Model.activation
    // only lets name-shaped values through, as arguments.
    var argv = Model.activation(row, root.omarchyPath)
    if (!argv || !root.store) return
    if (argv[0] === "open-app") argv = root.store.storeCommand(argv)
    Quickshell.execDetached(argv)
    root.close()
  }

  // ---------------------------------------------------------------- lifecycle

  Component.onCompleted: bindStore()

  onOpenedChanged: {
    if (!opened) {
      settingsOpen = false
      filter = ""
      search.text = ""
      return
    }
    now = Date.now()
    if (store) store.load()
    readMark = lastSeen
    if (store) store.markSeen()
    Qt.callLater(function() { if (root.opened) search.forceActiveFocus() })
  }

  // --------------------------------------------------------------------- bar

  // The bell is among the bar's indicators (Indicator.qml, copied into the
  // predmaxim.indicators clone by keep-custom-widgets.sh); the widget stays
  // in the bar, hidden, for its settings and IPC. The indicator can't reach
  // this plugin's service, so the count of new important notifications is
  // left for it in a file.
  visible: false
  implicitWidth: 0
  implicitHeight: 0

  FileView {
    id: unreadFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy-notification-center/unread"
    printErrors: false
  }

  onUnreadChanged: if (loaded) unreadFile.setText(String(unread))
  onLoadedChanged: if (loaded) unreadFile.setText(String(unread))

  // ------------------------------------------------------------------- panel

  // A modal in the middle of the screen, like the todo list: a click on the
  // dimmed screen or Esc closes it.
  PanelWindow {
    id: modal
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.opened
    color: Color.menu.scrim
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(root.panelWidth), modal.width - Style.space(80))
      height: Math.min(content.implicitHeight + contentTopInset + contentBottomInset, maxHeight)
      readonly property real maxHeight: modal.height * 0.85
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }   // clicks on the card stay on it

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      // The search field has the keyboard and handles its own keys; this
      // only gets what it leaves.
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(14)

        // -------------------------------------------------------- header

        PanelHero {
          id: header
          width: parent.width
          title: root.settingsOpen ? root.tr("Settings") : root.tr("Notifications")
          meta: root.settingsOpen ? "" : root.tr("New")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Text {
            text: root.dnd ? "\uDB80\uDC9B" : "\uDB80\uDC9A"
            color: root.dnd ? root.silencedColor : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          trailingControl: Row {
            spacing: Style.space(12)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.settingsOpen
              text: root.freshCount
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            // The common header (dotfiles rules.md): icon buttons, square and
            // borderless, then the on/off switch at the right edge; in the
            // settings the gear becomes Back and the switch hides.
            Button {
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.settingsOpen
              // U+F039F, nf-md-notification_clear_all.
              iconText: "\uDB80\uDF9F"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              tooltipText: root.tr("Empty the panel")
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.entries.length > 0
              onClicked: root.clearAll()
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              // U+F004D nf-md-arrow_left, U+F0493 nf-md-cog.
              iconText: root.settingsOpen ? "\uDB80\uDC4D" : "\uDB81\uDC93"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              tooltipText: root.settingsOpen ? root.tr("Back") : root.tr("Settings")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.toggleSettings()
            }

            // On = notifications shown, off = Do Not Disturb.
            ToggleSwitch {
              id: dndSwitch
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.settingsOpen
              checked: !root.dnd
              foreground: root.foreground
              onToggled: root.toggleDnd()
              PanelToolTip { visible: dndSwitch.containsMouse; text: root.dnd ? root.tr("Allow notifications") : root.tr("Silence notifications") }
            }
          }
        }

        // -------------------------------------------------------- search

        // Borderless and always holding the keyboard, like the launcher:
        // typing filters, Up/Down pick a notification, Enter opens it.
        TextField {
          id: search
          width: parent.width
          visible: !root.settingsOpen
          height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
          leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
          background: null
          placeholderText: root.tr("Search…")
          placeholderTextColor: Util.alpha(root.foreground, 0.58)
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          cursorDelegate: Item {}
          onTextChanged: root.filter = text
          onTextEdited: root.cursor = -1
          Keys.onUpPressed: root.moveCursor(-1)
          Keys.onDownPressed: root.moveCursor(1)
          Keys.onReturnPressed: root.activate(root.cursor >= 0 ? rows.get(root.cursor) : null)
          Keys.onEnterPressed: root.activate(root.cursor >= 0 ? rows.get(root.cursor) : null)
          Keys.onDeletePressed: function(event) {
            if (root.cursor < 0) { event.accepted = false; return }
            root.remove(rows.get(root.cursor).key)
          }
          Keys.onEscapePressed: text ? (text = "") : root.close()
        }

        // ---------------------------------------------------------- list

        ListView {
          id: list
          width: parent.width
          // Grows with what it holds and stops at the bottom of the screen,
          // which is where macOS puts the end of its notification column. The
          // ceiling is what is left of the screen once the header, the search
          // field and the footer have had their share, so the panel fills the
          // display without ever being taller than it.
          //
          // Search is counted in whether it is showing or not: opening it must
          // not push the footer out through the bottom of the card.
          // Grows with what it holds, up to what the card has left once the
          // header, the search field and the footer have had their share.
          readonly property int cap: Math.max(Style.space(240), card.maxHeight - card.contentTopInset
            - card.contentBottomInset - header.height - search.height - foot.implicitHeight - content.spacing * 3)

          height: Math.min(contentHeight, cap)
          visible: rows.count > 0 && !root.settingsOpen
          clip: true
          model: rows
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { id: listScroll; policy: ScrollBar.AsNeeded }

          // The scrollbar gets a lane of its own on the right. Sharing one
          // with the cards puts it on top of the dismiss button in the corner
          // of every one of them, and the button you are aiming at is the one
          // you miss.
          readonly property real lane: Style.space(10)

          section.property: "day"
          section.criteria: ViewSection.FullString
          section.delegate: Item {
            id: daySection
            required property string section
            width: list.width - list.lane
            height: dayLabel.implicitHeight + Style.space(14)

            PanelSectionHeader {
              id: dayLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.space(2)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              text: daySection.section.toUpperCase()
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          delegate: NotificationRow {
            id: row
            required property var model
            required property int index

            width: list.width - list.lane
            app: model.app
            appIcon: model.appIcon
            summary: model.summary
            body: model.body
            image: model.image
            preview: model.preview
            glyph: model.glyph
            timestamp: model.timestamp
            now: root.now
            urgency: model.urgency
            unread: model.timestamp > root.readMark
            selected: index === root.cursor
            tr: root.tr
            showBody: root.showBody
            showPreview: root.showPreview
            foreground: root.foreground
            fontFamily: root.fontFamily

            onClicked: root.activate(row.model)
            onRemoveRequested: root.remove(row.model.key)
          }
        }

        // --------------------------------------------------------- empty

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: rows.count === 0 && !root.settingsOpen
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(22)
          bottomPadding: Style.space(22)
          text: !root.loaded ? root.tr("Reading the archive…")
              : root.filter !== "" ? root.tr("Nothing matches “%1”", root.filter)
              : root.tr("Nothing has come in yet")
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.foreground
          opacity: 0.55
        }

        // ---------------------------------------------------------- foot

        Text {
          textFormat: Text.PlainText
          id: foot
          width: parent.width
          visible: rows.count > 0 && root.filter === "" && !root.settingsOpen
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(2)
          text: root.tr("Shown %1 of %2", rows.count, root.entries.length)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.foreground
          opacity: 0.4
        }

        // ------------------------------------------------------ settings

        Column {
          width: parent.width
          visible: root.settingsOpen
          spacing: Style.space(8)

          PanelSectionHeader {
            text: root.tr("WHERE NOTIFICATIONS APPEAR")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Extra room below sets the position apart from the source filter.
          Item {
            width: parent.width
            height: positions.height + Style.space(12)

            ButtonGroup {
              id: positions
              focusable: false
              value: root.popupPosition
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: [
                { value: "top-left", label: "↖", tooltip: root.tr("Top left") },
                { value: "top-center", label: "↑", tooltip: root.tr("Top centre") },
                { value: "top-right", label: "↗", tooltip: root.tr("Top right") },
                { value: "bottom-left", label: "↙", tooltip: root.tr("Bottom left") },
                { value: "bottom-right", label: "↘", tooltip: root.tr("Bottom right") }
              ]
              onChanged: function(value) { root.saveSetting("popupPosition", value) }
            }

            // Shows where the next one lands.
            Button {
              anchors.right: parent.right
              anchors.verticalCenter: positions.verticalCenter
              text: root.tr("Test")
              tooltipText: root.tr("Send a test notification")
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: Quickshell.execDetached(["notify-send", "-a", "Notification Center",
                root.tr("Test notification"), root.tr("Notifications appear here")])
            }
          }

          Toggle {
            width: parent.width
            label: root.tr("Only important")
            description: root.tr("Show only the sources ticked below: messengers, mail, calendar, tasks, reminders")
            checked: root.onlyImportant
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.saveSetting("onlyImportant", !root.onlyImportant)
          }

          PanelSectionHeader {
            visible: root.onlyImportant
            text: root.tr("SOURCES")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Everyone who has sent something, plus the ticked ones yet to.
          ListView {
            width: parent.width
            visible: root.onlyImportant
            height: Math.min(contentHeight, Style.space(360))
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.settingsOpen ? Model.sources(root.entries, root.important) : []
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: CursorSurface {
              id: sourceRow
              required property string modelData
              width: ListView.view.width
              height: Math.max(Style.space(40), sourceName.implicitHeight + Style.spacing.rowPaddingX)
              foreground: root.foreground
              hasCursor: sourceMouse.containsMouse

              Text {
                id: sourceName
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: sourceSwitch.left
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.sourceLabel(sourceRow.modelData)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.foreground
              }

              ToggleSwitch {
                id: sourceSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.important.indexOf(sourceRow.modelData) >= 0
                cursorRing: false
                foreground: root.foreground
                onToggled: root.toggleSource(sourceRow.modelData)
              }

              MouseArea {
                id: sourceMouse
                anchors.fill: parent
                anchors.rightMargin: sourceSwitch.width
                hoverEnabled: true
                onClicked: root.toggleSource(sourceRow.modelData)
              }
            }
          }
        }
      }
    }
  }
  }
}
