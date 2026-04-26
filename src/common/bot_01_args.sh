DEBUG_MODE=0
FORCE_WGET=0

while [ $# -gt 0 ]; do
    case "$1" in
    -d)
        DEBUG_MODE=1
        printf "DEBUG ON\n"
        ;;
    --force-wget)
        FORCE_WGET=1
        ;;
    esac
    shift
done

readonly DEBUG_MODE FORCE_WGET
debug_log() { [ "$DEBUG_MODE" -eq 1 ] && printf "[DEBUG] %s\n" "$1"; }
