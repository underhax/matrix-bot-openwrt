readonly SEND_RUN_DIR="/tmp/matrix_send_$$.d"

rm -rf -- "$SEND_RUN_DIR" 2>/dev/null
mkdir -m 0700 "$SEND_RUN_DIR" || {
    printf '[Error] Failed to create secure temp directory\n' >&2
    exit 1
}

trap 'trap - INT TERM EXIT; rm -rf -- "$SEND_RUN_DIR" 2>/dev/null' INT TERM EXIT
