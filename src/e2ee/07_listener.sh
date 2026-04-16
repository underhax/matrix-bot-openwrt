listen_e2ee() {
    printf 'Starting SSH Listener...\n'
    MC_CMD="matrix-commander-rs --listen forever --output json"
    [ "$DEBUG_MODE" -eq 1 ] && MC_CMD="$MC_CMD --log-level error"
    START_TIME=$(date +%s)
    local CR
    CR=$(printf '\r')

    while true; do
        ssh -i "$SSH_KEY" -p "$SSH_PORT" \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
            -o ConnectTimeout=15 \
            -o BatchMode=yes \
            -tt "$SSH_USER@$SSH_HOST" "$MC_CMD" </dev/null 2>&1 |
            while IFS= read -r line; do
                line="${line%"$CR"}"

                case "$line" in
                \{*)
                    case "$line" in
                    *\"room_id\"* | *\"sender\"*) ;;
                    *) continue ;;
                    esac
                    ;;
                *)
                    debug_log "RUST LOG: $line"
                    continue
                    ;;
                esac

                debug_log "RAW SSH JSON: $line"

                local tmp_line="/tmp/ssh_evt_$$.tmp"
                (umask 177 && set -C && : >"$tmp_line") || continue
                printf '%s\n' "$line" >"$tmp_line"

                TS=$(extract_json "$tmp_line" '.origin_server_ts // empty' '@.origin_server_ts')
                SEC=${TS%???}

                if [ -n "$SEC" ] && [ "$SEC" -lt "$START_TIME" ]; then
                    rm -f -- "$tmp_line"
                    continue
                fi

                ROOM_ID=$(extract_json "$tmp_line" '.room_id // empty' '@.room_id')
                ROOM_ID=$(sanitize_room_id "$ROOM_ID")
                [ -z "$ROOM_ID" ] && {
                    rm -f -- "$tmp_line"
                    continue
                }

                SENDER=$(extract_json "$tmp_line" '.sender // empty' '@.sender')
                SENDER=$(sanitize_user_id "$SENDER")
                [ -z "$SENDER" ] && {
                    rm -f -- "$tmp_line"
                    continue
                }

                BODY=$(extract_json "$tmp_line" '.body // empty' '@.body')

                debug_log "Parsed - ROOM: $ROOM_ID | SENDER: $SENDER | BODY: $BODY"
                rm -f -- "$tmp_line"

                core_handle_event "$ROOM_ID" "$SENDER" "$BODY"
            done

        jobs >/dev/null 2>&1
        sleep 5
    done
}
