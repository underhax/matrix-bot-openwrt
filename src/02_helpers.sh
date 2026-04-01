# === SANITIZATION ===

sanitize_room_id() {
    local raw="$1"
    local clean
    clean=$(printf '%s' "$raw" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!#=-')
    [ "$raw" != "$clean" ] && debug_log "SECURITY: Room ID sanitized: '$raw' -> '$clean'"
    printf '%s' "$clean"
}

sanitize_user_id() {
    local raw="$1"
    printf '%s' "$raw" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_@-'
}

# Percent-encode characters that are valid in a Matrix room ID but unsafe in a URL path segment.
# '#' (alias rooms) would be treated as a URL fragment; '!' has no special meaning but is encoded
# for strict RFC 3986 compliance.
urlencode_room() {
    printf '%s' "$1" | sed 's/#/%23/g; s/!/%21/g'
}

# === SENDING ===

reply() {
    local MSG="$1"
    local ROOM_ID="$2"

    debug_log "Executing sender for $ROOM_ID"
    if [ "$DEBUG_MODE" -eq 1 ]; then
        "$SENDER_SCRIPT" -d --room-id "$ROOM_ID" "$MSG" </dev/null >> /tmp/matrix_send.log 2>&1 &
    else
        "$SENDER_SCRIPT" --room-id "$ROOM_ID" "$MSG" </dev/null &
    fi
}

# === BACKGROUND EXECUTION ===
# Executes a command in the background and retries notifying Matrix of the result.
# Usage: background_exec <label> <room_id> <cmd> [args...]
background_exec() {
    local service_name="$1"
    local room_id="$2"
    shift 2

    (
        sleep 2
        "$@"
        ERR_CODE=$?

        # Build the status message once; value cannot change between retry attempts.
        if [ "$ERR_CODE" -eq 0 ]; then
            MSG="✅ <b>$service_name</b>: complete."
        else
            MSG="❌ <b>$service_name</b>: FAILED (Code $ERR_CODE)."
        fi

        i=0
        MAX_ATTEMPTS=30
        while [ $i -lt $MAX_ATTEMPTS ]; do
            sleep 2
            "$SENDER_SCRIPT" --room-id "$room_id" "$MSG" >/dev/null 2>&1 && break
            i=$((i + 1))
        done

        if [ $i -eq $MAX_ATTEMPTS ]; then
            logger -t matrix_bot "Failed to send notification after $MAX_ATTEMPTS attempts: $service_name"
        fi
    ) &
}

# === HELPER FUNCTIONS ===
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

# === JSON PARSER WRAPPER ===
# $1=file $2=jq expression $3=jsonfilter expression
extract_json() {
    if command -v jq >/dev/null 2>&1; then
        jq -r "$2" "$1" 2>/dev/null
    else
        jsonfilter -i "$1" -e "$3" 2>/dev/null
    fi
}
