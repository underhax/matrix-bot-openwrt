listen_http() {
    printf 'Starting HTTP Listener...\n'
    BATCH_FILE="$BOT_RUN_DIR/matrix_next_batch"
    START_TIME=$(date +%s)

    local sync_tmp="$BOT_RUN_DIR/sync.tmp"
    local evt_tmp="$BOT_RUN_DIR/evt.tmp"
    local hdr_file="$BOT_RUN_DIR/hdr.tmp"

    printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$hdr_file"

    curl -s -m 20 -K "$hdr_file" -o "$sync_tmp" "$MATRIX_URL/_matrix/client/v3/sync?timeout=0"
    NEXT=$(extract_json "$sync_tmp" '.next_batch // empty' '@.next_batch')
    [ -z "$NEXT" ] && [ -f "$BATCH_FILE" ] && NEXT=$(cat "$BATCH_FILE")

    while true; do
        [ -n "$NEXT" ] && (
            rm -f -- "$BATCH_FILE.tmp"
            set -o noclobber
            printf '%s\n' "$NEXT" >"$BATCH_FILE.tmp" && mv -- "$BATCH_FILE.tmp" "$BATCH_FILE"
        ) 2>/dev/null

        local enc_next
        enc_next=$(printf '%s' "$NEXT" | sed 's/%/%25/g; s/+/%2B/g; s/=/%3D/g; s/&/%26/g')

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
