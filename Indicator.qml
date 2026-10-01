import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "@PLUGIN_DIR@/I18n.js" as I18n

// The notification center among the bar's indicators: shown while something
// new has come in (a green dot on the bell) or notifications are silenced
// (the bell crossed out, red), otherwise only when the group is hovered.
// Click toggles the center (the hidden widget, Panel.qml), right-click
// silences. The count comes from the file the widget keeps it in, DND from
// the notification service's state file.
// keep-custom-widgets.sh copies this file into the predmaxim.indicators clone
// as indicators/Notifications.qml, filling in @PLUGIN_DIR@.
BarIndicator {
  id: root

  property int unread: 0
  property bool dnd: false
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))

  active: unread > 0 || dnd
  // U+F009B (bell-off), U+F009A (bell).
  activeText: dnd ? "󰂛" : "󰂚"
  inactiveText: "󰂚"
  activeTooltipText: dnd ? root.tr("Notifications silenced") : root.tr("New: %1", unread)
  inactiveTooltipText: root.tr("Notifications")
  // The theme's alert colour (urgent), not its "red": themes set that to anything.
  useActiveColor: dnd
  activeColor: Color.urgent

  onPressed: function(button) {
    if (button === Qt.RightButton)
      Quickshell.execDetached(["omarchy-toggle-notification-silencing"])
    else
      Quickshell.execDetached(["omarchy-shell", "jankeesvw.notification-center", "toggle"])
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy-notification-center/unread"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.unread = parseInt(text()) || 0
    onLoadFailed: root.unread = 0
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.dnd = JSON.parse(text()).dnd === true } catch (e) {}
    }
  }

  // Something new: a dot over the bell's top right corner, in the theme's
  // accent.
  Rectangle {
    visible: root.unread > 0 && !root.dnd
    x: root.width / 2 + root.glyphPaintedWidth / 2 - width / 2
    y: root.height / 2 - root.glyphPaintedWidth / 2 - height / 2
    width: Style.space(5)
    height: width
    radius: width / 2
    color: Color.accent
  }
}
