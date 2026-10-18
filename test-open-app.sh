#!/bin/bash
# open-app finds the window by name, not by a regex anywhere in its class.
set -euo pipefail
source <(sed -n '/^window_of()/,/^}/p' "$(dirname "$0")/bin/notification-center")
W='[{"class":"chrome-telemost.360.yandex.ru__-Default","address":"T"},{"class":"yandex-browser","address":"Y"},
{"class":"org.omarchy.agent","initialClass":"org.omarchy.agent","initialTitle":"claude","address":"C"},{"class":"Agent","address":"A"}]'
check() { [[ $(window_of "$1" <<<"$W") == "$2" ]] || { echo "FAIL: $1 -> want '$2'"; exit 1; }; }
check Yandex Y      # yandex-browser, not the yandex.ru web app
check Agent A       # Ideco's Agent, not org.omarchy.agent
check claude C      # agent terminal by its launch-time title
check Test ""

# open-app NAME [DESKTOP]: the sender's desktop-entry first, its window by
# StartupWMClass, else it starts; then the .desktop by Name=, as before.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/applications" "$d/bin"
printf '[Desktop Entry]\nName=Zz Test Mail\nName[ru]=Почта\nStartupWMClass=zz-mail-window\n' > "$d/applications/zz-test-mail.desktop"
printf '#!/bin/bash\necho "start $*"\n' > "$d/bin/setsid"
chmod +x "$d/bin/setsid"
source <(sed -n '/^cmd_open_app()/,/^}/p' "$(dirname "$0")/bin/notification-center")
focus_window() { [[ $1 == "$WINDOW" ]] && echo "focus $1"; }
open() { (WINDOW=$1; shift; XDG_DATA_HOME=$d PATH="$d/bin:$PATH" cmd_open_app "$@") || true; }
want() { [[ $2 == "$3" ]] || { echo "FAIL: $1 -> '$2', want '$3'"; exit 1; }; }
want "entry, its window"   "$(open zz-mail-window "" zz-test-mail)"     "focus zz-mail-window"
want "entry, no window"    "$(open none Почта zz-test-mail)"            "start uwsm-app -- zz-test-mail.desktop"
want "by Name="            "$(open none "Zz Test Mail")"                "start uwsm-app -- zz-test-mail.desktop"
want "entry missing, name" "$(open none "Zz Test Mail" no-such-entry)"  "start uwsm-app -- zz-test-mail.desktop"
want "entry no id"         "$(open none "" ../applications/zz-test-mail)" ""
echo ok
