readonly BUILD_TYPE="http"
readonly SENDER_SCRIPT="/usr/lib/matrix/matrix_send_http"
readonly DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"

MAIN_PID=""

cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot (HTTP)...\n'

    rm -f -- "/tmp/sync_${$}"* "/tmp/evt_${$}"* "/tmp/enc_check_${$}"* \
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

    PIDS_CURL=$(ps w | awk '/curl/ && /_matrix/ && !/awk/ {print $1}')
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
    sleep 1
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done

    exit 0
}
trap cleanup INT TERM EXIT
