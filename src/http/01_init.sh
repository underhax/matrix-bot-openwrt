readonly BUILD_TYPE="http"
readonly CONF_FILE="/etc/config/bot.conf"
readonly SENDER_SCRIPT="/usr/lib/matrix/matrix_send_http"

DEBUG_MODE=0

readonly DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"

MAIN_PID=""

cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot (HTTP)...\n'

    rm -f -- /tmp/sync_* /tmp/evt_* /tmp/enc_check_* \
        /tmp/mhdr_* /tmp/mbody_* /tmp/mwgetrc_*

    if [ -n "$MAIN_PID" ]; then
        kill -TERM "$MAIN_PID" 2>/dev/null
        sleep 1
        kill -0 "$MAIN_PID" 2>/dev/null && kill -KILL "$MAIN_PID" 2>/dev/null
    fi

    for p in $(jobs -p); do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 1
    for p in $(jobs -p); do
        kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
    done

    PIDS_CURL=$(ps w | awk '/curl/ && /_matrix/ && !/awk/ {print $1}')
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
    sleep 1
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done

    exit 0
}
trap cleanup INT TERM EXIT

while [ $# -gt 0 ]; do
    case "$1" in
    -d)
        DEBUG_MODE=1
        printf "DEBUG ON\n"
        ;;
    esac
    shift
done

readonly DEBUG_MODE

debug_log() { [ "$DEBUG_MODE" -eq 1 ] && printf "[DEBUG] %s\n" "$1"; }

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
        printf "Error: Failed to source config file\n" >&2
        exit 1
    }

    MATRIX_URL="${MATRIX_URL:-}"
    MATRIX_URL="${MATRIX_URL%/}"
    MATRIX_ACCESS_TOKEN="${MATRIX_ACCESS_TOKEN:-}"
    MATRIX_BOT_USER="${MATRIX_BOT_USER:-}"
    MATRIX_ROOM_IDS="${MATRIX_ROOM_IDS:-}"
    MATRIX_ROOM_ADMIN="${MATRIX_ROOM_ADMIN:-}"
    MATRIX_ADMIN_USER="${MATRIX_ADMIN_USER:-}"
    MAC_PC="${MAC_PC:-}"
    SVC_WANTED="${SVC_WANTED:-}"
    WIFI_DETAILED="${WIFI_DETAILED:-0}"
    readonly MATRIX_URL MATRIX_ACCESS_TOKEN MATRIX_BOT_USER \
        MATRIX_ROOM_IDS MATRIX_ROOM_ADMIN MATRIX_ADMIN_USER \
        MAC_PC SVC_WANTED WIFI_DETAILED

    if [ -z "$MATRIX_URL" ] || [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_BOT_USER" ]; then
        printf "Error: Required Matrix configuration missing\n" >&2
        exit 1
    fi
else
    printf "Config not found\n" >&2
    exit 1
fi
