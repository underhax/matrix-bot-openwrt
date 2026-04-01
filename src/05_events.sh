# === INITIALIZATION ===
# Queries the Matrix state API to determine which configured rooms have encryption enabled.
# Populates the global ENCRYPTED_CACHE variable (space-padded room ID list).
init_encryption_cache() {
    local raw_targets="$MATRIX_ROOM_ID $MATRIX_ROOM_E2EE_ID $MATRIX_ROOM_ADMIN"
    local targets
    targets=$(printf '%s' "$raw_targets" | awk '{for(i=1;i<=NF;i++) {gsub(/[\r"]/, "", $i); if(!seen[$i]++ && $i!="") printf "%s ", $i}}')

    printf 'Initializing: Checking room encryption status via API...\n'
    debug_log "Targets for check: $targets"

    ENCRYPTED_CACHE=""

    # BusyBox mktemp behaviour is inconsistent across OpenWrt versions (some ignore /tmp/ prefix,
    # some create in CWD). Use deterministic paths based on PID to avoid any mktemp ambiguity.
    local tmp_file="/tmp/enc_check_$$.tmp"
    local hdr_file="/tmp/mhdr_enc_$$.tmp"
    # Create files and immediately restrict permissions before writing any sensitive data.
    ( umask 177 && : > "$tmp_file" && : > "$hdr_file" ) || {
        printf 'Failed to create temp files in /tmp\n' >&2; exit 1
    }

    # Write the Bearer token to a private temp file to keep it out of ps output.
    printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" > "$hdr_file"

    for room in $targets; do
        room=$(sanitize_room_id "$room")
        [ -z "$room" ] && continue

        local enc_room
        enc_room=$(urlencode_room "$room")

        curl -s -m 5 -K "$hdr_file" \
            -o "$tmp_file" \
            "$MATRIX_URL/_matrix/client/v3/rooms/$enc_room/state/m.room.encryption"

        local algo
        algo=$(extract_json "$tmp_file" '.algorithm // empty' '@.algorithm')

        if [ "$algo" = "m.megolm.v1.aes-sha2" ]; then
            ENCRYPTED_CACHE="$ENCRYPTED_CACHE $room "
            debug_log "Room State [$room]: 🔒 ENCRYPTED"
        else
            debug_log "Room State [$room]: 🔓 PLAINTEXT"
        fi
    done

    rm -f "$tmp_file" "$hdr_file"
}

# === CORE EVENT HANDLER ===
# $1=room_id  $2=sender  $3=message body
# Central router: validates room whitelist, checks encryption context, enforces ACL.
core_handle_event() {
    local room_id="$1"
    local sender="$2"
    local body="$3"

    # Only process events from rooms explicitly listed in config
    case " $MATRIX_ROOM_ID $MATRIX_ROOM_E2EE_ID " in
        *" $room_id "*) ;;
        *) return ;;
    esac

    local is_room_encrypted=0
    case " $ENCRYPTED_CACHE " in
        *" $room_id "*) is_room_encrypted=1 ;;
    esac

    case "$sender" in
        "$MATRIX_BOT_USER")
            # Ignore own messages to prevent feedback loops
            ;;

        "$MATRIX_ADMIN_USER")
            case "$RUN_MODE:$is_room_encrypted" in
                "http:1")
                    if [ -z "$body" ]; then
                        debug_log "Encrypted message from Admin in HTTP mode. Room: $room_id"
                        reply "⛔ In HTTP/NO-E2EE mode, I cannot process messages in this encrypted room." "$room_id"
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

            local alert_dst="${MATRIX_ROOM_ADMIN:-${MATRIX_ROOM_E2EE_ID:-$MATRIX_ROOM_ID}}"

            local display_payload="${body:-[Empty/Unknown]}"
            if [ -z "$body" ] && [ "$RUN_MODE" = "http" ] && [ "$is_room_encrypted" -eq 1 ]; then
                display_payload="[Encrypted Message - Content Hidden]"
            fi

            if [ -n "$alert_dst" ]; then
                reply "⚠️ <b>SECURITY WARNING!</b><br><br><b>Unauthorized user:</b> $sender<br><b>Room:</b> <a href=\"https://matrix.to/#/$room_id\">room</a><br><b>Attempted Payload:</b> <code>$display_payload</code>" "$alert_dst"
            fi
            ;;
    esac
}
