listen_e2ee() {
    printf 'Starting SSH Listener...\n'
    MC_CMD="matrix-commander-rs --listen forever --output json"
    [ "$DEBUG_MODE" -eq 1 ] && MC_CMD="$MC_CMD --log-level error"
    START_TIME=$(date +%s)
    local CR TAB
    CR=$(printf '\r')
    TAB=$(printf '\t')
    local backoff=5
    local max_backoff=120
    local connected=0
    local _use_jq=0
    command -v jq >/dev/null 2>&1 && _use_jq=1

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

            local _evt TS ROOM_ID SENDER BODY
            if [ "$_use_jq" -eq 1 ]; then
                _evt=$(jq -r '[
                    (.origin_server_ts // 0 | tostring),
                    (.room_id // ""),
                    (.sender // ""),
                    (.body // "")
                ] | @tsv' "$tmp_line" 2>/dev/null)
                IFS="$TAB" read -r TS ROOM_ID SENDER BODY <<EOF
$_evt
EOF
            else
                _evt=$(jsonfilter -i "$tmp_line" \
                    -e '@.origin_server_ts' -e '@.room_id' \
                    -e '@.sender' -e '@.body' 2>/dev/null)
                {
                    read -r TS
                    read -r ROOM_ID
                    read -r SENDER
                    IFS= read -r BODY
                } <<EOF
$_evt
EOF
            fi
            rm -f -- "$tmp_line"

            SEC=${TS%???}
            if [ -n "$SEC" ] && [ "$SEC" -lt "$START_TIME" ]; then
                continue
            fi

            ROOM_ID=$(sanitize_room_id "$ROOM_ID")
            [ -z "$ROOM_ID" ] && continue

            SENDER=$(sanitize_user_id "$SENDER")
            [ -z "$SENDER" ] && continue

            debug_log "Parsed - ROOM: $ROOM_ID | SENDER: $SENDER | BODY: $BODY"

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
