#!/bin/bash
# list prints one JSON array even when the archive is longer than the limit.
set -euo pipefail
export NC_STORE=$(mktemp -d)
trap 'rm -rf "$NC_STORE"' EXIT
for i in $(seq 1 5000); do printf '{"key":"%s","summary":"s","timestamp":%s}\n' "$i" "$i"; done > "$NC_STORE/archive.jsonl"
out=$("$(dirname "$0")/bin/notification-center" list 10)
[[ $(jq -s 'length' <<<"$out") == 1 && $(jq 'length' <<<"$out") == 10 && $(jq -r '.[0].key' <<<"$out") == 5000 ]] ||
  { echo "FAIL: list 10 -> $(jq -sc 'map(length)' <<<"$out")"; exit 1; }
echo ok
