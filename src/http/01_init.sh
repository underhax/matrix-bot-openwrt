readonly BUILD_TYPE="http"
readonly SENDER_SCRIPT="/usr/lib/matrix/matrix_send_http"
readonly DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"
read -r _rand </proc/sys/kernel/random/uuid 2>/dev/null || _rand="fallback"
_rand="${_rand%%-*}"
readonly BOT_RUN_DIR="/tmp/matrix_bot_http_$$_${_rand}.d"

mkdir -m 0700 "$BOT_RUN_DIR" 2>/dev/null || {
    rm -rf -- "$BOT_RUN_DIR" 2>/dev/null
    mkdir -m 0700 "$BOT_RUN_DIR" || exit 1
}

cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot (HTTP)...\n'

    rm -rf -- "$BOT_RUN_DIR" 2>/dev/null

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
