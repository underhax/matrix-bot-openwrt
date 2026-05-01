readonly BUILD_TYPE="e2ee"
readonly SENDER_SCRIPT="/usr/lib/matrix/matrix_send"
readonly DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"
read -r _rand </proc/sys/kernel/random/uuid 2>/dev/null || _rand="fallback"
_rand="${_rand%%-*}"
readonly BOT_RUN_DIR="/tmp/matrix_bot_$$_${_rand}.d"

mkdir -m 0700 "$BOT_RUN_DIR" 2>/dev/null || {
    rm -rf -- "$BOT_RUN_DIR" 2>/dev/null
    mkdir -m 0700 "$BOT_RUN_DIR" || exit 1
}

cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot (E2EE)...\n'

    rm -rf -- "$BOT_RUN_DIR" 2>/dev/null

    for p in $(jobs -p); do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 1
    for p in $(jobs -p); do
        kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
    done

    if [ -n "${SSH_PORT:-}" ]; then
        PIDS_SSH=$(ps | awk -v p="$SSH_PORT" '/ssh/ && $0 ~ p && !/awk/ {print $1}')
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
        sleep 1
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done
    fi

    exit 0
}
trap cleanup INT TERM EXIT
