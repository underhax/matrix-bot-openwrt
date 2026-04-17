verify_conf_meta() {
    case "$1" in
    0:-rw-------* | 0:-r--------*) return 0 ;;
    esac
    return 1
}

sanitize_room_id() {
    case "$1" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!-]*)
        local clean
        clean=$(printf '%s' "$1" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:_!-')
        debug_log "SECURITY: Room ID sanitized: '$1' -> '$clean'"
        printf '%s' "$clean"
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

urlencode_room() {
    printf '%s' "$1" | sed 's/!/%21/g; s/:/%3A/g'
}
