debug_echo "HTTP -> Room: $TARGET_ROOM"

FULL_URL="$MATRIX_URL/_matrix/client/v3/rooms/$ROOM_ID_ESC/send/m.room.message"

HDR_FILE="/tmp/mhdr_$$.tmp"
BODY_FILE="/tmp/mbody_$$.tmp"
WGET_CONF="/tmp/mwgetrc_$$.tmp"

(umask 177 && set -C && : >"$HDR_FILE" && : >"$BODY_FILE" && : >"$WGET_CONF") || {
    printf '[Error] Failed to create temp files in /tmp\n' >&2
    exit 1
}
printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$HDR_FILE"
printf '%s' "$JSON_PAYLOAD" >"$BODY_FILE"
printf 'header = Authorization: Bearer %s\n' "$MATRIX_ACCESS_TOKEN" >"$WGET_CONF"

_SUCCESS=0
if [ "$FORCE_WGET" -eq 0 ] && command -v curl >/dev/null 2>&1; then
    debug_echo "Transport: CURL"
    if curl -s -f -X POST "$FULL_URL" \
        -K "$HDR_FILE" \
        -H "Content-Type: application/json" \
        --data-binary @"$BODY_FILE" \
        --connect-timeout 10 \
        --max-time 30 >/dev/null; then
        _SUCCESS=1
    fi
elif command -v wget >/dev/null 2>&1; then
    debug_echo "Transport: WGET"
    if WGETRC="$WGET_CONF" wget -q -O /dev/null \
        --header "Content-Type: application/json" \
        --post-file "$BODY_FILE" \
        --timeout=30 \
        "$FULL_URL"; then
        _SUCCESS=1
    fi
fi

rm -f -- "$HDR_FILE" "$BODY_FILE" "$WGET_CONF"

if [ "$_SUCCESS" -eq 1 ]; then
    debug_echo "Transport: HTTP (Success for $TARGET_ROOM)"
    exit 0
fi

debug_echo "Failed to send to $TARGET_ROOM via any available transport"
done

printf '[Error] Failed to send message to any of the target rooms\n' >&2
exit 1
