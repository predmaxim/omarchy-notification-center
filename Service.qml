import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The archive, mounted once for the shell.
//
// Omarchy builds a bar per monitor. If the watcher and the in-memory list
// lived on the widget, each screen would have its own lastSeen and its own
// entries, and marking read or clearing on one would leave the other as it
// was. The on-disk store is already shared; this is the QML owner of the
// processes that talk to it.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  property int keepDays: 30
  property int maxItems: 1000
  property bool showPreview: true
  property int pageSize: 500

  property var entries: []
  property double lastSeen: 0
  // Keys clicked on their toast (`notification-center read`): read, though
  // newer than lastSeen. The toast service writes the file; this follows it.
  property var readKeys: ({})
  property bool loaded: false

  readonly property bool watching: watchProc.running

  readonly property int unread: {
    var count = 0
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].timestamp <= lastSeen) break
      if (!readKeys[entries[i].key]) count++
    }
    return count
  }

  readonly property string script:
    Qt.resolvedUrl("bin/notification-center").toString().replace(/^file:\/\//, "")

  readonly property var storeEnvironment: ({
    "NC_KEEP_DAYS": String(root.keepDays),
    "NC_MAX_ITEMS": String(root.maxItems),
    "NC_PREVIEWS": root.showPreview ? "1" : "0"
  })

  signal entryAdded(var entry)
  signal entriesReset()

  function storeCommand(args) {
    return [root.script].concat(args)
  }

  function differsFrom(data) {
    if (data.length !== entries.length) return true
    if (data.length === 0) return false
    return String(data[0].key) !== String(entries[0].key)
  }

  function load() {
    if (listProc.running) return
    listProc.command = root.storeCommand(["list", String(root.pageSize)])
    listProc.running = true
  }

  function readSeen() {
    if (seenProc.running) return
    seenProc.command = root.storeCommand(["seen"])
    seenProc.running = true
  }

  function markSeen() {
    var stamp = Date.now()
    root.lastSeen = stamp
    if (markProc.running) return
    markProc.command = root.storeCommand(["seen", String(stamp)])
    markProc.running = true
  }

  function remove(key) {
    if (!key) return
    var next = []
    for (var i = 0; i < entries.length; i++)
      if (entries[i].key !== key) next.push(entries[i])
    entries = next
    entriesReset()
    Quickshell.execDetached(root.storeCommand(["remove", String(key)]))
    // Closed at its sender too, if the notifications service still holds it.
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismissKey", String(key)])
  }

  // Detached, like remove and seed above it: a clear that arrives while the
  // previous one is still running used to return early and never happen, so
  // the list came back on the next sync and the button looked broken.
  function clearAll() {
    entries = []
    entriesReset()
    Quickshell.execDetached(root.storeCommand(["clear"]))
    // And every notification the notifications service still holds closes at its sender.
    Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismissEverything"])
  }

  function absorb(line) {
    var entry
    try {
      entry = JSON.parse(line)
    } catch (e) {
      return
    }
    if (!entry || !entry.key) return
    // close_write and moved_to both fire for one popup; the second is dropped
    // by key. One watcher for the shell, so this is no longer a per-screen race.
    for (var i = 0; i < entries.length; i++)
      if (entries[i].key === entry.key) return

    var next = [entry].concat(entries)
    if (next.length > pageSize) next = next.slice(0, pageSize)
    entries = next
    entryAdded(entry)
  }

  Process {
    id: watchProc
    command: root.storeCommand(["watch"])
    environment: root.storeEnvironment
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.absorb(line) }
    }
    onExited: restartWatch.restart()
  }

  Timer {
    id: restartWatch
    interval: 30000
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.load()
  }

  Process {
    id: listProc
    environment: root.storeEnvironment
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text)
        } catch (e) {
          return
        }
        if (!Array.isArray(data)) return
        var wasLoaded = root.loaded
        root.loaded = true
        if (wasLoaded && !root.differsFrom(data)) return
        root.entries = data
        root.entriesReset()
      }
    }
  }

  Process {
    id: seenProc
    environment: root.storeEnvironment
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok === true) root.lastSeen = Number(data.seen) || 0
        } catch (e) {
        }
      }
    }
  }

  Process { id: markProc; environment: root.storeEnvironment }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-notification-center/read"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var keys = {}
      text().split("\n").forEach(function(k) { if (k) keys[k] = true })
      root.readKeys = keys
    }
  }

  // Showing the screen (Telemost, a browser: the Hyprland portal) silences
  // notifications for as long as it lasts. The portal names its video streams
  // xdph-streaming-*; their lifetime is the share, unlike frame activity,
  // which screenshots and VNC have too.
  readonly property var videoSources: Pipewire.nodes.values.filter(function(n) { return n.type === PwNodeType.VideoSource })
  PwObjectTracker { objects: root.videoSources }
  readonly property bool sharing: Pipewire.ready && videoSources.some(function(n) {
    return n.ready && /^xdph-streaming-/.test(n.properties["media.name"] || n.properties["node.name"] || "")
  })
  property bool dnd: false
  // Only a silence the share turned on ends with it: one already on stays,
  // one turned off meanwhile stays off.
  // shortcut: kept in memory, so a shell restart mid-share leaves the
  // silence on after it; upgrade to a state file if that bites.
  property bool sharingSilenced: false

  function setDnd(on) {
    Quickshell.execDetached(["bash", "-c", "omarchy-shell notifications setDnd \"$1\" >/dev/null; omarchy-shell -q omarchy.indicators refresh", "_", on ? "on" : "off"])
  }

  onSharingChanged: {
    if (sharing && !dnd) {
      sharingSilenced = true
      setDnd(true)
    } else if (!sharing && sharingSilenced) {
      sharingSilenced = false
      if (dnd) setDnd(false)
    }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.dnd = JSON.parse(text()).dnd === true } catch (e) {}
    }
  }

  Component.onCompleted: {
    readSeen()
    load()
  }

  IpcHandler {
    target: "jankeesvw.notification-center.test"

    function seed(count: int): string {
      Quickshell.execDetached(root.storeCommand(["seed", String(count > 0 ? count : 25)]))
      reloadAfterSeed.restart()
      return "seeding " + count
    }

    function clear(): string {
      root.clearAll()
      return "cleared"
    }

    function reload(): string {
      root.load()
      return "reloading"
    }

    function state(): string {
      return JSON.stringify({
        entries: root.entries.length,
        newest: root.entries.length > 0 ? root.entries[0].summary : "",
        unread: root.unread,
        watching: watchProc.running,
        loaded: root.loaded,
        lastSeen: root.lastSeen,
        sharing: root.sharing,
        sharingSilenced: root.sharingSilenced,
        dnd: root.dnd
      })
    }
  }

  Timer {
    id: reloadAfterSeed
    interval: 600
    onTriggered: root.load()
  }
}
