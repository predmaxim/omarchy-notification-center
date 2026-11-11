#!/bin/bash
# read marks one notification read (clicked on its toast); unread skips it.
# Keys: <timestamp>-<id> (Omarchy before 4.5) or the service's own (4.5).
set -euo pipefail
export NC_STORE=$(mktemp -d)
trap 'rm -rf "$NC_STORE"' EXIT
nc="$(dirname "$0")/bin/notification-center"
{
  for i in 1 2 3; do printf '{"key":"%s-%s","summary":"s","timestamp":%s}\n' "$i" "$i" "$i"; done
  printf '{"key":"nmwbu6d955","summary":"s","timestamp":4}\n'
} > "$NC_STORE/archive.jsonl"
"$nc" read 2-2 >/dev/null
"$nc" read nmwbu6d955 >/dev/null
"$nc" read 'bad key' >/dev/null 2>&1 || true
[[ $(cat "$NC_STORE/read") == $'2-2\nnmwbu6d955' ]] || { echo "FAIL: read file -> $(cat "$NC_STORE/read")"; exit 1; }
[[ $("$nc" unread | jq .unread) == 2 ]] || { echo "FAIL: unread -> $("$nc" unread)"; exit 1; }
# Clicks at once must not lose each other's keys (they share read.tmp).
: > "$NC_STORE/read"
for i in $(seq 1 30); do "$nc" read "k$i" >/dev/null & done; wait
[[ $(wc -l < "$NC_STORE/read") == 30 ]] || { echo "FAIL: concurrent reads -> $(wc -l < "$NC_STORE/read") of 30"; exit 1; }
echo ok
