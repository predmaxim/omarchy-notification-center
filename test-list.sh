#!/bin/bash
# list prints one JSON array even when the archive is longer than the limit.
set -euo pipefail
export NC_STORE=$(mktemp -d)
trap 'rm -rf "$NC_STORE"' EXIT
for i in $(seq 1 5000); do printf '{"key":"%s","summary":"s","timestamp":%s}\n' "$i" "$i"; done > "$NC_STORE/archive.jsonl"
out=$("$(dirname "$0")/bin/notification-center" list 10)
[[ $(jq -s 'length' <<<"$out") == 1 && $(jq 'length' <<<"$out") == 10 && $(jq -r '.[0].key' <<<"$out") == 5000 ]] ||
  { echo "FAIL: list 10 -> $(jq -sc 'map(length)' <<<"$out")"; exit 1; }

# The archive keeps the sender's desktop-entry: a click's fallback opens that .desktop.
src=$(mktemp -d)
trap 'rm -rf "$NC_STORE" "$src"' EXIT
mkdir -p "$src/history"
printf '{"app":"Почта","summary":"s","body":"b","desktopEntry":"omarchy-mail","timestamp":9000000000000}\n' > "$src/history/9000000000000-3.json"
NC_SRC_DIR=$src NC_SRC_HISTORY=$src/history "$(dirname "$0")/bin/notification-center" sync >/dev/null
[[ $(jq -r 'select(.key == "9000000000000-3") | .desktopEntry' "$NC_STORE/archive.jsonl") == omarchy-mail ]] ||
  { echo "FAIL: desktopEntry -> $(grep 9000000000000-3 "$NC_STORE/archive.jsonl")"; exit 1; }

# A crash toast's click command leaves only its PID in the archive; any other command, nothing.
crash() {  # key execArgv-json want-crashPid
  jq -nc --arg exec "$2" '{app:"omarchy-action",summary:"Process crashed: x",execArgv:$exec,timestamp:9000000000001}' > "$src/history/$1.json"
  NC_SRC_DIR=$src NC_SRC_HISTORY=$src/history "$(dirname "$0")/bin/notification-center" sync >/dev/null
  local line; line=$(grep "\"key\":\"$1\"" "$NC_STORE/archive.jsonl")
  [[ $(jq -r '.crashPid' <<<"$line") == "$3" && $line != *cef_server* ]] || { echo "FAIL: crashPid $2 -> $line"; exit 1; }
}
crash 9000000000001-4 '["omarchy-agent-crash","4242","cef_server","/usr/bin/cef_server","SEGV"]' 4242
crash 9000000000001-5 '["omarchy-agent-crash","1; rm -rf ~","cef_server"]' ""
crash 9000000000001-6 '["bash","-c","omarchy-agent-crash 4242"]' ""
crash 9000000000001-7 'omarchy-agent-crash 4242' ""
echo ok
