#!/bin/bash
# read marks one notification read (clicked on its toast); unread skips it.
set -euo pipefail
export NC_STORE=$(mktemp -d)
trap 'rm -rf "$NC_STORE"' EXIT
nc="$(dirname "$0")/bin/notification-center"
for i in 1 2 3; do printf '{"key":"%s-%s","summary":"s","timestamp":%s}\n' "$i" "$i" "$i"; done > "$NC_STORE/archive.jsonl"
"$nc" read 2-2 >/dev/null
"$nc" read 'bad key' >/dev/null || true
[[ $(cat "$NC_STORE/read") == 2-2 ]] || { echo "FAIL: read file -> $(cat "$NC_STORE/read")"; exit 1; }
[[ $("$nc" unread | jq .unread) == 2 ]] || { echo "FAIL: unread -> $("$nc" unread)"; exit 1; }
echo ok
