validate_ssh_config() {
    local invalid=0
    local log_tag="matrix_bot"
    [ -z "${MATRIX_BOT_USER:-}" ] && log_tag="matrix_send"

    if [ -n "${SSH_HOST:-}" ]; then
        if ! validate_domain_ip "$SSH_HOST" "SSH_HOST" "$log_tag"; then
            invalid=1
        fi
    fi

    if [ -n "${SSH_PORT:-}" ]; then
        if ! validate_port "$SSH_PORT" "SSH_PORT" "$log_tag"; then
            invalid=1
        fi
    fi

    if [ -n "${SSH_USER:-}" ]; then
        case "$SSH_USER" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-]*)
            logger -t "$log_tag" "FATAL: SSH_USER contains invalid characters."
            invalid=1
            ;;
        esac
    fi

    if [ -n "${SSH_KEY:-}" ]; then
        case "$SSH_KEY" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./~-]*)
            logger -t "$log_tag" "FATAL: SSH_KEY contains invalid characters."
            invalid=1
            ;;
        esac

        local _key_meta
        _key_meta=$(ls -n "$SSH_KEY" 2>/dev/null | awk 'NR==1 {printf "%s:%s", $3, $1}')
        if [ -z "$_key_meta" ] || ! verify_secure_meta "$_key_meta"; then
            logger -t "$log_tag" "FATAL: SSH_KEY ($SSH_KEY) must be owned by root with mode 600 or 400"
            invalid=1
        fi
    fi

    if [ -n "${SSH_HOST:-}" ]; then
        local _hosts_file="/etc/matrix_bot_known_hosts"
        local _hosts_meta
        _hosts_meta=$(ls -n "$_hosts_file" 2>/dev/null | awk 'NR==1 {printf "%s:%s", $3, $1}')
        if [ -z "$_hosts_meta" ] || ! verify_secure_meta "$_hosts_meta"; then
            logger -t "$log_tag" "FATAL: $_hosts_file must be owned by root with mode 600 or 400"
            invalid=1
        fi
    fi

    return "$invalid"
}

if ! validate_ssh_config; then
    printf "FATAL: SSH Config validation failed. Check syslog.\n" >&2
    exit 1
fi
