MATRIX_URL="${MATRIX_URL:-}"
MATRIX_URL="${MATRIX_URL%/}"
MATRIX_ACCESS_TOKEN="${MATRIX_ACCESS_TOKEN:-}"
MATRIX_ROOM_IDS="${MATRIX_ROOM_IDS:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"
readonly MATRIX_URL MATRIX_ACCESS_TOKEN MATRIX_ROOM_IDS \
    SSH_HOST SSH_PORT SSH_USER SSH_KEY

MODE="auto"

parse_mode_arg() {
    case "$1" in
    --ssh-only)
        MODE="ssh"
        return 0
        ;;
    --http-only)
        MODE="http"
        return 0
        ;;
    esac
    return 1
}
