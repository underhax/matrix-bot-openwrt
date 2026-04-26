listen_http() {
    printf 'Starting HTTP Listener...\n'
    BATCH_FILE="$BOT_RUN_DIR/matrix_next_batch"
    START_TIME=$(date +%s)
    local backoff=5
    local max_backoff=120
    local TAB
    TAB="$(printf '\t')"

    local sync_tmp="$BOT_RUN_DIR/sync.tmp"
    local evt_tmp="$BOT_RUN_DIR/evt.tmp"
    local hdr_file="$BOT_RUN_DIR/hdr.tmp"

    printf 'header = "Authorization: Bearer %s"\n' "$MATRIX_ACCESS_TOKEN" >"$hdr_file"

    local use_curl=1
    if ! command -v curl >/dev/null 2>&1; then
        if command -v wget >/dev/null 2>&1; then
            use_curl=0
            local wget_conf="$BOT_RUN_DIR/wgetrc.tmp"
            printf 'header = Authorization: Bearer %s\n' "$MATRIX_ACCESS_TOKEN" >"$wget_conf"
        else
            printf 'FATAL: Neither curl nor wget available\n' >&2
            exit 1
        fi
    fi

    while true; do
        if [ "$use_curl" -eq 1 ]; then
            curl -s -m 20 --retry 2 --retry-delay 3 -K "$hdr_file" -o "$sync_tmp" \
                "$MATRIX_URL/_matrix/client/v3/sync?timeout=0"
            curl_exit=$?
        else
            WGETRC="$wget_conf" wget -q -O "$sync_tmp" --timeout=20 \
                "$MATRIX_URL/_matrix/client/v3/sync?timeout=0"
            wget_exit=$?
            [ $wget_exit -eq 0 ] && curl_exit=0 || curl_exit=1
        fi

        case $curl_exit in
        28) ;;
        0) ;;
        *)
            sleep 5
            continue
            ;;
        esac

        NEXT=$(extract_json "$sync_tmp" '.next_batch // empty' '@.next_batch')
        [ -z "$NEXT" ] && [ -f "$BATCH_FILE" ] && NEXT=$(cat "$BATCH_FILE")

        if [ -z "$NEXT" ]; then
            debug_log "Initial sync failed, backing off for ${backoff}s"
            sleep "$backoff"
            backoff=$((backoff * 2))
            [ "$backoff" -gt "$max_backoff" ] && backoff=$max_backoff
            continue
        fi
        break
    done

    while true; do
        [ -n "$NEXT" ] && (
            rm -f -- "$BATCH_FILE.tmp"
            set -o noclobber
            printf '%s\n' "$NEXT" >"$BATCH_FILE.tmp" && mv -- "$BATCH_FILE.tmp" "$BATCH_FILE"
        ) 2>/dev/null

        local enc_next
        enc_next=$(printf '%s' "$NEXT" | sed 's/%/%25/g; s/+/%2B/g; s/=/%3D/g; s/&/%26/g')

        if [ "$use_curl" -eq 1 ]; then
            curl -s --connect-timeout 10 -m 40 --retry 2 --retry-delay 3 -K "$hdr_file" -o "$sync_tmp" \
                "$MATRIX_URL/_matrix/client/v3/sync?timeout=30000&since=$enc_next"
            curl_exit=$?
        else
            WGETRC="$wget_conf" wget -q -O "$sync_tmp" --timeout=40 \
                "$MATRIX_URL/_matrix/client/v3/sync?timeout=30000&since=$enc_next"
            wget_exit=$?
            [ $wget_exit -eq 0 ] && curl_exit=0 || curl_exit=1
        fi

        case $curl_exit in
        28) ;;
        0) ;;
        *)
            sleep 5
            continue
            ;;
        esac

        if [ ! -s "$sync_tmp" ]; then
            sleep 5
            continue
        fi

        _sync_err=$(extract_json "$sync_tmp" '.errcode // empty' '@.errcode')
        if [ -n "$_sync_err" ]; then
            if [ "$_sync_err" = "M_LIMIT_EXCEEDED" ]; then
                _retry_ms=$(extract_json "$sync_tmp" '.retry_after_ms // 10000' '@.retry_after_ms')
                _retry_sec=$((_retry_ms / 1000))
                _jitter=$(awk 'BEGIN{srand(); print int(rand() * 5)}')
                sleep $((_retry_sec + _jitter))
            else
                debug_log "API error in sync response: $_sync_err, backing off"
                _jitter=$(awk 'BEGIN{srand(); print int(rand() * 5)}')
                sleep $((10 + _jitter))
            fi
            continue
        fi

        NEW_NEXT=$(extract_json "$sync_tmp" '.next_batch // empty' '@.next_batch')
        [ -n "$NEW_NEXT" ] && NEXT="$NEW_NEXT"

        if command -v jq >/dev/null 2>&1; then
            jq -r --argjson st "$START_TIME" '
                .rooms.join // {} | to_entries[] |
                .key as $room |
                (.value.timeline.events // [])[] |
                select(.origin_server_ts >= ($st * 1000)) |
                select(.type == "m.room.message" or .type == "m.room.encrypted") |
                [$room, .type, .sender, (.content.body // "")] | @tsv
            ' "$sync_tmp" 2>/dev/null | while IFS="$TAB" read -r ROOM_ID TYPE SENDER BODY; do
                ROOM_ID=$(sanitize_room_id "$ROOM_ID")
                SENDER=$(sanitize_user_id "$SENDER")
                core_handle_event "$ROOM_ID" "$SENDER" "$BODY"
            done
        else
            ROOM_IDS=$(extract_json "$sync_tmp" '.rooms.join // empty' '@.rooms.join' |
                awk '{ while(match($0, /"![^"]+":/)) { print substr($0, RSTART+1, RLENGTH-3); $0=substr($0, RSTART+RLENGTH) } }')

            for ROOM_ID in $ROOM_IDS; do
                ROOM_ID=$(sanitize_room_id "$ROOM_ID")
                [ -z "$ROOM_ID" ] && continue
                i=0
                while true; do
                    extract_json "$sync_tmp" ".rooms.join[\"$ROOM_ID\"].timeline.events[$i] // empty" "@.rooms.join[\"$ROOM_ID\"].timeline.events[$i]" >"$evt_tmp"
                    [ ! -s "$evt_tmp" ] && break
                    TS=$(extract_json "$evt_tmp" '.origin_server_ts // empty' '@.origin_server_ts')
                    TS=${TS:-0}
                    SEC=$((TS / 1000))
                    [ "$SEC" -lt "$START_TIME" ] && {
                        i=$((i + 1))
                        continue
                    }
                    TYPE=$(extract_json "$evt_tmp" '.type // empty' '@.type')
                    case "$TYPE" in
                    "m.room.message" | "m.room.encrypted") ;;
                    *)
                        i=$((i + 1))
                        continue
                        ;;
                    esac
                    SENDER=$(extract_json "$evt_tmp" '.sender // empty' '@.sender')
                    SENDER=$(sanitize_user_id "$SENDER")
                    BODY=$(extract_json "$evt_tmp" '.content.body // empty' '@.content.body')
                    core_handle_event "$ROOM_ID" "$SENDER" "$BODY"
                    i=$((i + 1))
                done
            done
        fi
        jobs >/dev/null 2>&1
    done
}
