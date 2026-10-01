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
echo ok
