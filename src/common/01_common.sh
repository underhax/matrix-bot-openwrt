_HAS_CURL=""
_HAS_JQ=""

has_curl() {
    if [ -z "$_HAS_CURL" ]; then
        if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
            _HAS_CURL=1
        else
            _HAS_CURL=0
        fi
        [ "${DEBUG_MODE:-0}" -eq 1 ] && printf '[DEBUG] has_curl: result=%s\n' "$_HAS_CURL"
    fi
    [ "$_HAS_CURL" -eq 1 ]
}

has_jq() {
    if [ -z "$_HAS_JQ" ]; then
        if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
            _HAS_JQ=1
        else
            _HAS_JQ=0
        fi
        [ "${DEBUG_MODE:-0}" -eq 1 ] && printf '[DEBUG] has_jq: result=%s\n' "$_HAS_JQ"
    fi
    [ "$_HAS_JQ" -eq 1 ]
}

verify_secure_meta() {
    case "$1" in
    0:-rw-------* | 0:-r--------*) return 0 ;;
    esac
    return 1
}

sanitize_room_id() {
    case "$1" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!-]*)
        local clean
        clean=$(printf '%s' "$1" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!-')
        debug_log "SECURITY: Room ID sanitized: '$1' -> '$clean'"
        printf '%s' "$clean"
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

urlencode_room() {
    printf '%s' "$1" | sed 's/!/%21/g; s/:/%3A/g'
}

validate_ipv4() {
    local ip="$1"
    case "$ip" in
    *.*.*.*.*) return 1 ;;
    *.*.*.*) ;;
    *) return 1 ;;
    esac

    local OLD_IFS="$IFS"
    set -f
    IFS=.
    set -- $ip
    IFS="$OLD_IFS"
    set +f

    [ $# -eq 4 ] || return 1
    for octet in "$@"; do
        case "$octet" in
        *[!0-9]*) return 1 ;;
        "") return 1 ;;
        esac
        [ "$octet" -le 255 ] 2>/dev/null || return 1
        case "$octet" in
        0?*) return 1 ;;
        esac
    done
    return 0
}

validate_ipv6() {
    local ip="$1"
    ip="${ip#\[}"
    ip="${ip%\]}"

    case "$ip" in
    *[!a-fA-F0-9:]*) return 1 ;;
    *:::*) return 1 ;;
    :[!:]* | *[!:]:) return 1 ;;
    esac

    local dc="${ip#*::}"
    if [ "$dc" != "$ip" ]; then
        local dc2="${dc#*::}"
        if [ "$dc2" != "$dc" ]; then
            return 1
        fi
    fi

    local OLD_IFS="$IFS"
    set -f
    IFS=:
    set -- $ip
    IFS="$OLD_IFS"
    set +f

    if [ "$dc" = "$ip" ] && [ $# -ne 8 ]; then
        return 1
    fi
    if [ $# -gt 8 ]; then
        return 1
    fi

    for hextet in "$@"; do
        case "${#hextet}" in
        0 | 1 | 2 | 3 | 4) ;;
        *) return 1 ;;
        esac
    done
    return 0
}

validate_domain() {
    local domain="$1"
    case "$domain" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-]*) return 1 ;;
    -*) return 1 ;;
    *-) return 1 ;;
    .*) return 1 ;;
    *.) return 1 ;;
    *..*) return 1 ;;
    esac
    return 0
}

validate_domain_ip() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0

    case "$val" in
    *:*)
        if ! validate_ipv6 "$val"; then
            logger -t "$log_tag" "FATAL: $var_name contains invalid IPv6 structure."
            return 1
        fi
        ;;
    *[!0-9.]*)
        if ! validate_domain "$val"; then
            logger -t "$log_tag" "FATAL: $var_name contains invalid domain structure."
            return 1
        fi
        ;;
    *)
        if ! validate_ipv4 "$val"; then
            logger -t "$log_tag" "FATAL: $var_name contains invalid IPv4 structure."
            return 1
        fi
        ;;
    esac
    return 0
}

validate_port() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    *[!0123456789]*)
        logger -t "$log_tag" "FATAL: $var_name contains non-numeric characters."
        return 1
        ;;
    esac
    if [ "$val" -lt 1 ] 2>/dev/null || [ "$val" -gt 65535 ] 2>/dev/null; then
        logger -t "$log_tag" "FATAL: $var_name must be between 1 and 65535."
        return 1
    fi
    return 0
}

validate_domain_port() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0

    local host=""
    local port=""

    case "$val" in
    \[*\]:*)
        host="${val%%]:*}]"
        port="${val##*:}"
        ;;
    \[*\])
        host="$val"
        ;;
    *:*:*)
        host="$val"
        ;;
    *:*)
        host="${val%%:*}"
        port="${val##*:}"
        ;;
    *)
        host="$val"
        ;;
    esac

    validate_domain_ip "$host" "$var_name" "$log_tag" || return 1

    if [ -n "$port" ]; then
        validate_port "$port" "$var_name port" "$log_tag" || return 1
    fi

    return 0
}

validate_room_id() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    !*)
        local body="${val#!}"
        case "$body" in
        *:*)
            local localpart="${body%%:*}"
            local serverpart="${body#*:}"

            if [ -z "$localpart" ] || [ -z "$serverpart" ]; then
                logger -t "$log_tag" "FATAL: $var_name has empty localpart or domain."
                return 1
            fi

            case "$localpart" in
            *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._=/-]*)
                logger -t "$log_tag" "FATAL: $var_name localpart contains invalid characters."
                return 1
                ;;
            esac

            if ! validate_domain_port "$serverpart" "$var_name domain" "$log_tag"; then
                return 1
            fi
            ;;
        *)
            case "$body" in
            *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._=/-]*)
                logger -t "$log_tag" "FATAL: $var_name contains invalid characters."
                return 1
                ;;
            esac
            ;;
        esac
        ;;
    *)
        logger -t "$log_tag" "FATAL: $var_name must start with '!'."
        return 1
        ;;
    esac
    return 0
}

validate_room_id_list() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0

    set -f
    set -- $val
    set +f

    for room in "$@"; do
        if ! validate_room_id "$room" "$var_name" "$log_tag"; then
            return 1
        fi
    done
    return 0
}

validate_core_config() {
    local invalid=0
    local log_tag="$1"

    local url_body
    case "${MATRIX_URL:-}" in
    http://* | https://*)
        url_body="${MATRIX_URL#*://}"
        if ! validate_domain_port "$url_body" "MATRIX_URL" "$log_tag"; then
            invalid=1
        fi
        ;;
    *)
        logger -t "$log_tag" "FATAL: MATRIX_URL must start with 'http://' or 'https://'."
        invalid=1
        ;;
    esac

    case "${MATRIX_ACCESS_TOKEN:-}" in
    syt_*)
        case "${MATRIX_ACCESS_TOKEN}" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
            logger -t "$log_tag" "FATAL: MATRIX_ACCESS_TOKEN contains invalid characters."
            invalid=1
            ;;
        esac
        ;;
    *)
        logger -t "$log_tag" "FATAL: MATRIX_ACCESS_TOKEN must start with 'syt_'."
        invalid=1
        ;;
    esac

    validate_room_id_list "${MATRIX_ROOM_IDS:-}" "MATRIX_ROOM_IDS" "$log_tag" || invalid=1

    return "$invalid"
}
