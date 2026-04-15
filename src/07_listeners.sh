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

listen_http() {
    printf 'Starting HTTP Listener...\n'
    BATCH_FILE="/tmp/matrix_next_batch"
    START_TIME=$(date +%s)

    local sync_tmp="/tmp/sync_$$.tmp"
    local evt_tmp="/tmp/evt_$$.tmp"
    local hdr_file="/tmp/mhdr_http_$$.tmp"
    (umask 177 && set -C && : >"$sync_tmp" && : >"$evt_tmp" && : >"$hdr_file") || {
        printf 'Failed to create temp files in /tmp\n' >&2
        exit 1
    }

    printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$hdr_file"

    curl -s -m 20 -K "$hdr_file" -o "$sync_tmp" "$MATRIX_URL/_matrix/client/v3/sync?timeout=0"
    NEXT=$(extract_json "$sync_tmp" '.next_batch // empty' '@.next_batch')
    [ -z "$NEXT" ] && [ -f "$BATCH_FILE" ] && NEXT=$(cat "$BATCH_FILE")

    while true; do
        if [ "$RUN_MODE" = "auto" ] && [ -n "$MAIN_PID" ]; then
            if kill -0 "$MAIN_PID" 2>/dev/null; then
                sleep 5
                continue
            fi
        fi

        [ -n "$NEXT" ] && (
            rm -f -- "$BATCH_FILE.tmp"
            set -o noclobber
            printf '%s\n' "$NEXT" >"$BATCH_FILE.tmp" && mv -- "$BATCH_FILE.tmp" "$BATCH_FILE"
        ) 2>/dev/null

        local enc_next
        enc_next=$(printf '%s' "$NEXT" | sed 's/%/%25/g; s/+/%2B/g; s/=/%3D/g; s/&/%26/g')

        : >"$sync_tmp"
        : >"$evt_tmp"

        curl -s --connect-timeout 10 -m 40 -K "$hdr_file" -o "$sync_tmp" \
            "$MATRIX_URL/_matrix/client/v3/sync?timeout=30000&since=$enc_next"

        if [ ! -s "$sync_tmp" ]; then
            sleep 5
            continue
        fi

        _sync_err=$(extract_json "$sync_tmp" '.errcode // empty' '@.errcode')
        if [ -n "$_sync_err" ]; then
            debug_log "API error in sync response: $_sync_err, backing off"
            sleep 10
            continue
        fi

        NEW_NEXT=$(extract_json "$sync_tmp" '.next_batch // empty' '@.next_batch')
        [ -n "$NEW_NEXT" ] && NEXT="$NEW_NEXT"

        if command -v jq >/dev/null 2>&1; then
            ROOM_IDS=$(jq -r '(.rooms.join // {}) | keys[]' "$sync_tmp" 2>/dev/null)
        else
            ROOM_IDS=$(extract_json "$sync_tmp" '.rooms.join // empty' '@.rooms.join' |
                awk '{ while(match($0, /"![^"]+":/)) { print substr($0, RSTART+1, RLENGTH-3); $0=substr($0, RSTART+RLENGTH) } }')
        fi

        for ROOM_ID in $ROOM_IDS; do
            ROOM_ID=$(sanitize_room_id "$ROOM_ID")
            [ -z "$ROOM_ID" ] && continue
            i=0
            while true; do
                if command -v jq >/dev/null 2>&1; then
                    jq -r --arg rid "$ROOM_ID" --argjson idx "$i" \
                        '.rooms.join[$rid].timeline.events[$idx] // empty' \
                        "$sync_tmp" >"$evt_tmp" 2>/dev/null
                else
                    extract_json "$sync_tmp" \
                        ".rooms.join[\"$ROOM_ID\"].timeline.events[$i] // empty" \
                        "@.rooms.join['$ROOM_ID'].timeline.events[$i]" >"$evt_tmp"
                fi
                [ ! -s "$evt_tmp" ] && break

                TYPE=$(extract_json "$evt_tmp" '.type // empty' '@.type')
                TS=$(extract_json "$evt_tmp" '.origin_server_ts // empty' '@.origin_server_ts')
                SEC=${TS%???}

                if [ -n "$SEC" ] && [ "$SEC" -ge "$START_TIME" ]; then
                    SENDER=$(extract_json "$evt_tmp" '.sender // empty' '@.sender')
                    SENDER=$(sanitize_user_id "$SENDER")

                    BODY=""

                    case "$TYPE" in
                    "m.room.message")
                        BODY=$(extract_json "$evt_tmp" '.content.body // empty' '@.content.body')
                        core_handle_event "$ROOM_ID" "$SENDER" "$BODY"
                        ;;
                    "m.room.encrypted")
                        core_handle_event "$ROOM_ID" "$SENDER" "$BODY"
                        ;;
                    esac
                fi
                i=$((i + 1))
            done
        done
        jobs >/dev/null 2>&1
    done
}
