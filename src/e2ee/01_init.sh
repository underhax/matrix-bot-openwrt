readonly BUILD_TYPE="e2ee"
readonly SENDER_SCRIPT="/usr/lib/matrix/matrix_send"
readonly DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"

MAIN_PID=""

cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot (E2EE)...\n'

    rm -f -- "/tmp/ssh_evt_${$}"* "/tmp/enc_check_${$}"* \
        "/tmp/mhdr_${$}"* "/tmp/mbody_${$}"* "/tmp/mwgetrc_${$}"*

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

    if [ -n "${SSH_PORT:-}" ]; then
        PIDS_SSH=$(ps | awk -v p="$SSH_PORT" '/ssh/ && $0 ~ p && !/awk/ {print $1}')
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
        sleep 1
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done
    fi

    exit 0
}
trap cleanup INT TERM EXIT
