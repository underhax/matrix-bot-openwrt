if [ -z "${MATRIX_URL:-}" ] || [ -z "${MATRIX_ACCESS_TOKEN:-}" ]; then
    printf '[Error] MATRIX_URL or MATRIX_ACCESS_TOKEN missing in config\n' >&2
    exit 1
fi

validate_sender_config() {
    local invalid=0

    if ! validate_core_config "matrix_send"; then
        invalid=1
    fi

    return "$invalid"
}

if ! validate_sender_config; then
    printf "[Error] Strict config validation failed. Check syslog.\n" >&2
    exit 1
fi
