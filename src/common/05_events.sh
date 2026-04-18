init_encryption_cache() {
    local raw_targets="$MATRIX_ROOM_IDS $MATRIX_ROOM_ADMIN"
    local targets
    targets=$(printf '%s' "$raw_targets" | awk '{for(i=1;i<=NF;i++) {gsub(/[\r"]/, "", $i); if(!seen[$i]++ && $i!="") printf "%s ", $i}}')

    printf 'Initializing: Checking room encryption status via API...\n'
    debug_log "Targets for check: $targets"

    ENCRYPTED_CACHE=""

    local tmp_file="$BOT_RUN_DIR/enc_check.tmp"
    local hdr_file="$BOT_RUN_DIR/mhdr_enc.tmp"
    (umask 177 && set -C && : >"$tmp_file" && : >"$hdr_file") || {
        printf 'Failed to create temp files in %s\n' "$BOT_RUN_DIR" >&2
        exit 1
    }

    printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$hdr_file"

    local enc_room algo attempt errcode
    for room in $targets; do
        room=$(sanitize_room_id "$room")
        [ -z "$room" ] && continue

        enc_room=$(urlencode_room "$room")

        algo=""
        attempt=0
        while [ "$attempt" -lt 3 ]; do
            : >"$tmp_file"
            curl -s -m 15 -K "$hdr_file" \
                -o "$tmp_file" \
                "$MATRIX_URL/_matrix/client/v3/rooms/$enc_room/state/m.room.encryption"

            errcode=$(extract_json "$tmp_file" '.errcode // empty' '@.errcode')

            if [ "$errcode" = "M_NOT_FOUND" ]; then
                break
            fi

            if [ -n "$errcode" ]; then
                debug_log "API error for $room (attempt $attempt): $errcode"
                attempt=$((attempt + 1))
                [ "$attempt" -lt 3 ] && sleep 3
                continue
            fi

            algo=$(extract_json "$tmp_file" '.algorithm // empty' '@.algorithm')
            break
        done

        if [ "$algo" = "m.megolm.v1.aes-sha2" ]; then
            ENCRYPTED_CACHE="$ENCRYPTED_CACHE $room "
            debug_log "Room State [$room]: 🔒 ENCRYPTED"
        else
            debug_log "Room State [$room]: 🔓 PLAINTEXT (algo: ${algo:-none})"
        fi
    done

    rm -f -- "$tmp_file" "$hdr_file"
}

core_handle_event() {
    local room_id="$1"
    local sender="$2"
    local body="$3"

    case " $MATRIX_ROOM_IDS " in
    *" $room_id "*) ;;
    *) return ;;
    esac

    local is_room_encrypted=0
    case " $ENCRYPTED_CACHE " in
    *" $room_id "*) is_room_encrypted=1 ;;
    esac

    case "$sender" in
    "$MATRIX_BOT_USER")
        :
        ;;

    "$MATRIX_ADMIN_USER")
        case "$BUILD_TYPE:$is_room_encrypted" in
        "http:1")
            if [ -z "$body" ]; then
                debug_log "Encrypted message from Admin in HTTP mode. Room: $room_id"
                reply "⛔ In HTTP mode, I cannot process messages in this encrypted room." "$room_id"
                return
            fi
            ;;
        "e2ee:0")
            if [ -n "$body" ]; then
                debug_log "PLAINTEXT from Admin in E2EE mode. Room: $room_id"
                reply "⚠️ <b>Warning:</b> The bot is in strict E2EE mode. Please enable encryption for this room." "$room_id"
            fi
            ;;
        esac

        if [ -n "$body" ]; then
            process_command "$sender" "$body" "$room_id"
        fi
        ;;

    *)
        debug_log "SECURITY ALERT: Unauthorized access from $sender to $room_id"

        local alert_dst="$MATRIX_ROOM_ADMIN"

        local display_payload="${body:-[Empty/Unknown]}"
        if [ -z "$body" ] && [ "$BUILD_TYPE" = "http" ] && [ "$is_room_encrypted" -eq 1 ]; then
            display_payload="[Encrypted Message - Content Hidden]"
        fi
        display_payload=$(html_escape "$display_payload")
        local safe_sender
        safe_sender=$(html_escape "$sender")

        if [ -n "$alert_dst" ]; then
            reply "⚠️ <b>SECURITY WARNING!</b><br><br><b>Unauthorized user:</b> $safe_sender<br><b>Room:</b> <a href=\"https://matrix.to/#/$room_id\">room</a><br><b>Attempted Payload:</b> <code>$display_payload</code>" "$alert_dst"
        fi
        ;;
    esac
}
