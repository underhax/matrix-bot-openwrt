try_ssh() {
    if [ -z "$SSH_HOST" ] || [ -z "$SSH_KEY" ]; then
        debug_echo "SSH not configured (missing SSH_HOST or SSH_KEY)"
        return 1
    fi

    if [ -z "$SSH_USER" ] || [ -z "$SSH_PORT" ]; then
        debug_echo "SSH config incomplete (missing SSH_USER or SSH_PORT)"
        return 1
    fi

    if [ ! -r "$SSH_KEY" ]; then
        debug_echo "SSH key not found or not readable: $SSH_KEY"
        [ "${MODE:-}" = "ssh" ] && printf '[Error] SSH key not accessible: %s\n' "$SSH_KEY" >&2
        return 1
    fi

    debug_echo "Attempting SSH -> Room: $TARGET_ROOM"

    printf "%s" "$MSG" | ssh -i "$SSH_KEY" -p "$SSH_PORT" \
        -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
        -o LogLevel=ERROR \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=5 \
        -o ServerAliveCountMax=2 \
        -T \
        "$SSH_USER@$SSH_HOST" matrix-commander-rs --room "'$TARGET_ROOM'" --html --message - >/dev/null 2>&1

    return $?
}
