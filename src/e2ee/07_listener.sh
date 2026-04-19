listen_e2ee() {
    printf 'Starting SSH Listener...\n'
    MC_CMD="matrix-commander-rs --listen forever --output json"
    [ "$DEBUG_MODE" -eq 1 ] && MC_CMD="$MC_CMD --log-level error"
    START_TIME=$(date +%s)
    local CR
    CR=$(printf '\r')
    local backoff=5
    local max_backoff=120
    local connected=0

    while true; do
        local fifo="$BOT_RUN_DIR/ssh_fifo"
        rm -f -- "$fifo"
        mkfifo "$fifo" || {
            sleep 1
            continue
        }

        ssh_pid=""
        ssh -i "$SSH_KEY" -p "$SSH_PORT" \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
            -o ConnectTimeout=15 \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=2 \
            -o BatchMode=yes \
            -tt "$SSH_USER@$SSH_HOST" "$MC_CMD" </dev/null 2>&1 >"$fifo" &
        ssh_pid=$!

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

            connected=1
            debug_log "RAW SSH JSON: $line"

            local tmp_line="$BOT_RUN_DIR/ssh_evt.tmp"
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
        done <"$fifo"

        kill -0 "$ssh_pid" 2>/dev/null && kill -TERM "$ssh_pid" 2>/dev/null
        wait "$ssh_pid" 2>/dev/null || true

        jobs >/dev/null 2>&1

        if [ "$connected" -eq 1 ]; then
            logger -t matrix_bot "SSH listener reconnected, resetting backoff"
            backoff=5
        else
            logger -t matrix_bot "SSH listener disconnected, backing off for ${backoff}s"
        fi

        sleep "$backoff"
        backoff=$((backoff * 2))
        [ "$backoff" -gt "$max_backoff" ] && backoff=$max_backoff
        connected=0
    done
}
