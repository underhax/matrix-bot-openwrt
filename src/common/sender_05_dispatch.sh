if [ -n "$RAW_TARGET_ROOM" ]; then
    ROOMS_TO_TRY="$RAW_TARGET_ROOM"
else
    ROOMS_TO_TRY="$MATRIX_ROOM_IDS"
fi

if [ -z "$ROOMS_TO_TRY" ]; then
    printf '[Error] No room ID specified and MATRIX_ROOM_IDS is empty in config\n' >&2
    exit 1
fi

for CURRENT_ROOM in $ROOMS_TO_TRY; do
    TARGET_ROOM=$(sanitize_room_id "$CURRENT_ROOM")
    [ -z "$TARGET_ROOM" ] && continue

    if command -v try_ssh >/dev/null 2>&1; then
        if [ "${MODE:-}" != "http" ]; then
            if try_ssh; then
                debug_echo "Transport: SSH (Success for $TARGET_ROOM)"
                exit 0
            fi

            if [ "${MODE:-}" = "ssh" ]; then
                debug_echo "SSH failed for $TARGET_ROOM, skipping HTTP as per mode"
                continue
            fi
            debug_echo "SSH failed for $TARGET_ROOM, trying fallback to HTTP..."
        fi
    fi

    debug_echo "HTTP -> Room: $TARGET_ROOM"
    ROOM_ID_ESC=$(urlencode_room "$TARGET_ROOM")
    FULL_URL="$MATRIX_URL/_matrix/client/v3/rooms/$ROOM_ID_ESC/send/m.room.message"

    HDR_FILE="$SEND_RUN_DIR/hdr.tmp"
    BODY_FILE="$SEND_RUN_DIR/body.tmp"
    WGET_CONF="$SEND_RUN_DIR/wgetrc.tmp"

    _SUCCESS=0
    if [ "$FORCE_WGET" -eq 0 ] && curl --version >/dev/null 2>&1; then
        debug_echo "Transport: CURL"
        [ -f "$BODY_FILE" ] || (umask 177 && set -C && : >"$BODY_FILE") || {
            printf '[Error] Failed to create temp file in %s\n' "$SEND_RUN_DIR" >&2
            continue
        }
        [ -f "$HDR_FILE" ] || (umask 177 && set -C && : >"$HDR_FILE") || {
            printf '[Error] Failed to create curl config in %s\n' "$SEND_RUN_DIR" >&2
            continue
        }
        printf '%s' "$JSON_PAYLOAD" >"$BODY_FILE"
        printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$HDR_FILE"
        if curl -s -f -X POST "$FULL_URL" \
            -K "$HDR_FILE" \
            -H "Content-Type: application/json" \
            --data-binary @"$BODY_FILE" \
            --connect-timeout 10 \
            --max-time 30 >/dev/null; then
            _SUCCESS=1
        fi
        rm -f -- "$HDR_FILE" "$BODY_FILE"
    elif command -v wget >/dev/null 2>&1; then
        debug_echo "Transport: WGET"
        [ -f "$BODY_FILE" ] || (umask 177 && set -C && : >"$BODY_FILE") || {
            printf '[Error] Failed to create temp file in %s\n' "$SEND_RUN_DIR" >&2
            continue
        }
        [ -f "$WGET_CONF" ] || (umask 177 && set -C && : >"$WGET_CONF") || {
            printf '[Error] Failed to create wget config in %s\n' "$SEND_RUN_DIR" >&2
            continue
        }
        printf '%s' "$JSON_PAYLOAD" >"$BODY_FILE"
        printf 'header = Authorization: Bearer %s\n' "$MATRIX_ACCESS_TOKEN" >"$WGET_CONF"
        if WGETRC="$WGET_CONF" wget -q -O /dev/null \
            --header "Content-Type: application/json" \
            --post-file "$BODY_FILE" \
            --timeout=30 \
            "$FULL_URL"; then
            _SUCCESS=1
        fi
        rm -f -- "$WGET_CONF" "$BODY_FILE"
    fi

    if [ "$_SUCCESS" -eq 1 ]; then
        debug_echo "Transport: HTTP (Success for $TARGET_ROOM)"
        exit 0
    fi

    debug_echo "Failed to send to $TARGET_ROOM via any available transport"
done

printf '[Error] Failed to send message to any of the target rooms\n' >&2
exit 1
