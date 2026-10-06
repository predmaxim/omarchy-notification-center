#!/bin/bash
# watch takes its inotifywait with it even when it is killed with SIGKILL,
# which is how the shell stops it on a plugin reload.
set -euo pipefail
d=$(mktemp -d)
trap 'pkill -f "inotifywait.*$d" || true; rm -rf "$d"' EXIT
mkdir -p "$d/src/history"
NC_STORE=$d/store NC_SRC_DIR=$d/src NC_SRC_HISTORY=$d/src/history "$(dirname "$0")/bin/notification-center" watch &
sleep 1
kill -KILL $!
sleep 0.5
! pgrep -f "inotifywait.*$d" >/dev/null || { echo "FAIL: inotifywait outlived watch"; exit 1; }
echo ok
