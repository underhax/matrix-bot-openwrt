DEBUG_MODE=0
RAW_TARGET_ROOM=""
FORCE_WGET=0
FORCE_AWK_FALLBACK=0

while [ $# -gt 0 ]; do
    case "$1" in
    -d | --debug)
        DEBUG_MODE=1
        shift
        ;;
    --force-wget)
        FORCE_WGET=1
        shift
        ;;
    --force-awk-fallback)
        FORCE_AWK_FALLBACK=1
        shift
        ;;

    --room-id)
        if [ -n "$2" ] && [ "${2#-}" = "$2" ]; then
            RAW_TARGET_ROOM="$2"
            shift 2
        else
            printf '[Error] --room-id requires an argument\n' >&2
            exit 1
        fi
        ;;
    --)
        shift
        break
        ;;
    -*)
        printf "Unknown option: %s\n" "$1" >&2
        exit 1
        ;;
    *) break ;;
    esac
done

MSG="$*"

if [ -z "$MSG" ]; then
    printf '[Error] No message provided\n' >&2
    exit 1
fi

debug_echo() { [ "$DEBUG_MODE" -eq 1 ] && printf "[Debug] %s\n" "$1"; }
