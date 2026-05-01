sanitize_user_id() {
    case "$1" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_@-]*)
        printf '%s' "$1" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_@-'
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

html_escape() {
    case "$1" in
    *\&* | *\<* | *\>* | *\"* | *\'*)
        local res="${1//&/&amp;}"
        res="${res//</&lt;}"
        res="${res//>/&gt;}"
        res="${res//\"/&quot;}"
        res="${res//\'/&#39;}"
        printf '%s' "$res"
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

reply() {
    local MSG="$1"
    local ROOM_ID="$2"
    local log_file="$BOT_RUN_DIR/matrix_send.log"

    debug_log "Executing sender for $ROOM_ID"
    if [ "$DEBUG_MODE" -eq 1 ]; then
        [ -f "$log_file" ] || (umask 177 && set -C && : >"$log_file") 2>/dev/null
        if [ "$FORCE_WGET" -eq 1 ]; then
            ("$SENDER_SCRIPT" -d --force-wget --room-id "$ROOM_ID" -- "$MSG" </dev/null >>"$log_file" 2>&1 &) &
        else
            ("$SENDER_SCRIPT" -d --room-id "$ROOM_ID" -- "$MSG" </dev/null >>"$log_file" 2>&1 &) &
        fi
    else
        if [ "$FORCE_WGET" -eq 1 ]; then
            ("$SENDER_SCRIPT" --force-wget --room-id "$ROOM_ID" -- "$MSG" </dev/null &) &
        else
            ("$SENDER_SCRIPT" --room-id "$ROOM_ID" -- "$MSG" </dev/null &) &
        fi
    fi
    wait $!
}

send_with_retry() {
    local room_id="$1"
    local message="$2"
    local log_tag="${3:-matrix_bot}"
    local i=0
    local delay=2

    while [ $i -lt 5 ]; do
        sleep $delay
        "$SENDER_SCRIPT" --room-id "$room_id" -- "$message" >/dev/null 2>&1 && return 0
        i=$((i + 1))
        delay=$((delay * 2))
    done

    logger -t "$log_tag" "Failed to send notification after 5 attempts"
    return 1
}

background_exec() {
    local service_name="$1"
    local room_id="$2"
    shift 2

    ( (
        sleep 2
        "$@"
        ERR_CODE=$?

        if [ "$ERR_CODE" -eq 0 ]; then
            MSG="✅ <b>$service_name</b>: complete."
        else
            MSG="❌ <b>$service_name</b>: FAILED (Code $ERR_CODE)."
        fi

        send_with_retry "$room_id" "$MSG" "matrix_bot"
    ) &) &
    wait $!
}

get_iface_list() {
    uci show network | awk -F. '/=interface$/ && !/loopback/ {split($2,a,"="); print a[1]}' | sort | awk 'NR>1{printf ", "} {printf $0}'
}

get_services_list() {
    local list=""
    local targets="${SVC_WANTED:-$DEFAULT_SERVICES}"

    for s in $targets; do
        [ -x "/etc/init.d/$s" ] && list="${list}$s, "
    done
    printf '%s' "${list%, }"
}

extract_json() {
    if [ "${FORCE_JSONFILTER:-0}" -eq 0 ] && command -v jq >/dev/null 2>&1; then
        jq -r "$2" "$1" 2>/dev/null
    else
        jsonfilter -i "$1" -e "$3" 2>/dev/null
    fi
}
