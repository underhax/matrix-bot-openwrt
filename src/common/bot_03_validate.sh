if [ -z "$MATRIX_URL" ] || [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_BOT_USER" ]; then
    printf "Error: Required Matrix configuration missing\n" >&2
    exit 1
fi

validate_bool() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    *[!01]*)
        logger -t "$log_tag" "FATAL: $var_name contains invalid characters."
        return 1
        ;;
    esac
    return 0
}

validate_user_id() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    @*)
        local body="${val#@}"
        case "$body" in
        *:*)
            local localpart="${body%%:*}"
            local serverpart="${body#*:}"

            if [ "${#val}" -gt 255 ]; then
                logger -t "$log_tag" "FATAL: $var_name exceeds 255 characters."
                return 1
            fi

            if [ -z "$localpart" ] || [ -z "$serverpart" ]; then
                logger -t "$log_tag" "FATAL: $var_name must have localpart and domain."
                return 1
            fi

            case "$localpart" in
            *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._=/+-]*)
                logger -t "$log_tag" "FATAL: $var_name localpart contains invalid characters."
                return 1
                ;;
            esac

            if ! validate_domain_port "$serverpart" "$var_name domain" "$log_tag"; then
                return 1
            fi
            ;;
        *)
            logger -t "$log_tag" "FATAL: $var_name must be in format @user:domain."
            return 1
            ;;
        esac
        ;;
    *)
        logger -t "$log_tag" "FATAL: $var_name must start with '@'."
        return 1
        ;;
    esac
    return 0
}

validate_path_list() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./\ -]*)
        logger -t "$log_tag" "FATAL: $var_name contains invalid characters."
        return 1
        ;;
    esac
    return 0
}

validate_bot_config() {
    local invalid=0

    validate_core_config "matrix_bot" || invalid=1
    validate_user_id "$MATRIX_BOT_USER" "MATRIX_BOT_USER" "matrix_bot" || invalid=1
    validate_user_id "${MATRIX_ADMIN_USER:-}" "MATRIX_ADMIN_USER" "matrix_bot" || invalid=1
    validate_room_id "${MATRIX_ROOM_ADMIN:-}" "MATRIX_ROOM_ADMIN" "matrix_bot" || invalid=1
    validate_bool "${WIFI_DETAILED:-}" "WIFI_DETAILED" "matrix_bot" || invalid=1
    validate_bool "${WIFI_SHOW_KEY:-}" "WIFI_SHOW_KEY" "matrix_bot" || invalid=1
    validate_path_list "${SVC_WANTED:-}" "SVC_WANTED" "matrix_bot" || invalid=1
    validate_path_list "${WOL_INTERFACES:-}" "WOL_INTERFACES" "matrix_bot" || invalid=1

    if [ -n "${MAC_PC:-}" ]; then
        case "$MAC_PC" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:-]*)
            logger -t matrix_bot "FATAL: MAC_PC contains invalid characters."
            invalid=1
            ;;
        esac
    fi

    return "$invalid"
}

if ! validate_bot_config; then
    printf "FATAL: Config validation failed. Check syslog.\n" >&2
    exit 1
fi
