read -r _rand </proc/sys/kernel/random/uuid 2>/dev/null || _rand="fallback"
_rand="${_rand%%-*}"
readonly SEND_RUN_DIR="/tmp/matrix_send_$$_${_rand}.d"

mkdir -m 0700 "$SEND_RUN_DIR" 2>/dev/null || {
    rm -rf -- "$SEND_RUN_DIR" 2>/dev/null
    mkdir -m 0700 "$SEND_RUN_DIR" || {
        printf '[Error] Failed to create secure temp directory\n' >&2
        exit 1
    }
}

trap 'trap - INT TERM EXIT; rm -rf -- "$SEND_RUN_DIR" 2>/dev/null' INT TERM EXIT
