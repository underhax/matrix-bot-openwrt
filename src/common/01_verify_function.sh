verify_conf_meta() {
    case "$1" in
    0:-rw-------* | 0:-r--------*) return 0 ;;
    esac
    return 1
}
