DEBUG_MODE=0
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
