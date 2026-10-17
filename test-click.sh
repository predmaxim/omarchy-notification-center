#!/bin/bash
# click: the sender's own click while the notifications service holds the
# notification ("ok" from invokeKey); otherwise the center's own command.
set -euo pipefail
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
nc="$(dirname "$0")/bin/notification-center"
cat > "$stubs/omarchy-shell" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUBS/calls"
echo "$ANSWER"
STUB
chmod +x "$stubs/omarchy-shell"
export STUBS=$stubs PATH="$stubs:$PATH"
check() {  # answer key want-output want-calls -- args
  local answer=$1 key=$2 want=$3 calls=$4 out
  shift 5
  : > "$stubs/calls"
  out=$(ANSWER=$answer "$nc" click "$key" "$@" 2>&1) || true
  [[ $out == "$want" ]] || { echo "FAIL: $answer $key $* -> '$out', want '$want'"; exit 1; }
  [[ $(wc -l < "$stubs/calls") == "$calls" ]] || { echo "FAIL: $answer $key $* -> $(wc -l < "$stubs/calls") calls"; exit 1; }
}
check ok   1700000000000-7 ""         1 -- echo fallback   # the sender took the click
check none 1700000000000-7 fallback   1 -- echo fallback   # gone (service restarted, closed): the center's own
check ""   1700000000000-7 fallback   1 -- echo fallback   # no answer (stock service, shell down)
check ok   'bad key'       fallback   0 -- echo fallback   # not a key: never asked
check none 1700000000000-7 ""         1 --                 # nothing else to do
[[ $(ANSWER=ok "$nc" click 1700000000000-7 >/dev/null; cat "$stubs/calls" | tail -n 1) == "notifications invokeKey 1700000000000-7" ]] ||
  { echo "FAIL: invokeKey call -> $(tail -n 1 "$stubs/calls")"; exit 1; }
echo ok
