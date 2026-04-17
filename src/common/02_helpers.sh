sanitize_room_id() {
    case "$1" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!#=-]*)
        local clean
        clean=$(printf '%s' "$1" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!#=-')
        debug_log "SECURITY: Room ID sanitized: '$1' -> '$clean'"
        printf '%s' "$clean"
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

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
        printf '%s' "$1" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

urlencode_room() {
    printf '%s' "$1" | sed 's/#/%23/g; s/!/%21/g'
}

reply() {
    local MSG="$1"
    local ROOM_ID="$2"

    debug_log "Executing sender for $ROOM_ID"
    if [ "$DEBUG_MODE" -eq 1 ]; then
        ("$SENDER_SCRIPT" -d --room-id "$ROOM_ID" -- "$MSG" </dev/null >>/tmp/matrix_send.log 2>&1 &) &
    else
        ("$SENDER_SCRIPT" --room-id "$ROOM_ID" -- "$MSG" </dev/null &) &
    fi
    wait $!
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

        i=0
        MAX_ATTEMPTS=5
        delay=2
        while [ $i -lt $MAX_ATTEMPTS ]; do
            sleep $delay
            "$SENDER_SCRIPT" --room-id "$room_id" -- "$MSG" >/dev/null 2>&1 && break
            i=$((i + 1))
            delay=$((delay * 2))
        done

        if [ $i -eq $MAX_ATTEMPTS ]; then
            logger -t matrix_bot "Failed to send notification after $MAX_ATTEMPTS attempts: $service_name"
        fi
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
    if command -v jq >/dev/null 2>&1; then
        jq -r "$2" "$1" 2>/dev/null
    else
        jsonfilter -i "$1" -e "$3" 2>/dev/null
    fi
}
