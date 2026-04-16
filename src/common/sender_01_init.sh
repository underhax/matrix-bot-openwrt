readonly CONF_FILE="/etc/config/bot.conf"

if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC2012
    _conf_meta=$(ls -n "$CONF_FILE" 2>/dev/null | awk 'NR==1 {printf "%s:%s", $3, $1}')
    if [ -z "$_conf_meta" ]; then
        printf 'FATAL: Cannot read metadata of %s\n' "$CONF_FILE" >&2
        exit 1
    fi
    if ! verify_conf_meta "$_conf_meta"; then
        printf 'FATAL: %s must be owned by root (uid 0) with mode 600 or 400 (got %s)\n' "$CONF_FILE" "$_conf_meta" >&2
        exit 1
    fi

    . "$CONF_FILE" || {
        printf '[Error] Failed to source config\n' >&2
        exit 1
    }

    MATRIX_URL="${MATRIX_URL:-}"
    MATRIX_URL="${MATRIX_URL%/}"
    MATRIX_ACCESS_TOKEN="${MATRIX_ACCESS_TOKEN:-}"
    MATRIX_ROOM_IDS="${MATRIX_ROOM_IDS:-}"
