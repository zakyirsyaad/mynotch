#!/bin/sh

umask 077

if [ "$#" -ne 2 ]; then
    exit 0
fi

source="$1"
event="$2"

is_valid_token() {
    case "$1" in
        ""|*[!A-Za-z0-9_-]*)
            return 1
            ;;
    esac
    if [ "${#1}" -gt 64 ]; then
        return 1
    fi
    return 0
}

if ! is_valid_token "$source" || ! is_valid_token "$event"; then
    exit 0
fi

inbox="$HOME/.mynotch/inbox"
mkdir -p "$inbox" 2>/dev/null || exit 0

payload=$(head -c 262144 2>/dev/null)
trimmed=$(printf '%s' "$payload" | tr -d ' \t\r\n')
if [ -z "$trimmed" ]; then
    payload="null"
fi

ts=$(date +%s 2>/dev/null || echo 0)
rand_hex=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
rand="$$-${rand_hex:-0}"

tmp_file="$inbox/.tmp-$ts-$PPID-$rand"
final_file="$inbox/$ts-$PPID-$rand.json"

if printf '{"v":1,"source":"%s","event":"%s","pid":%s,"ts":%s,"payload":%s}\n' \
    "$source" "$event" "$PPID" "$ts" "$payload" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$final_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
else
    rm -f "$tmp_file" 2>/dev/null
fi

exit 0
