#!/usr/bin/env bats

setup() {
    debug_log() { return 0; }

    source "${BATS_TEST_DIRNAME}/../src/02_helpers.sh"

    reply() {
        REPLY_MSG="$1"
        REPLY_ROOM="$2"
    }

    source "${BATS_TEST_DIRNAME}/../src/06_commands.sh"

    cmd_help() { REPLY_MSG="H: room=$1"; }
    cmd_sysinfo() { REPLY_MSG="S: cmd=$1 room=$2"; }
    cmd_clients() { REPLY_MSG="C: cmd=$1 room=$2"; }
    cmd_service() { REPLY_MSG="SRV: cmd=$1 args=$2 room=$3"; }
    cmd_iface() { REPLY_MSG="I: cmd=$1 args=$2 room=$3"; }
    cmd_wifi() { REPLY_MSG="W: cmd=$1 room=$2"; }
    cmd_wol() { REPLY_MSG="WOL: cmd=$1 args=$2 room=$3"; }

    REPLY_MSG=""
    REPLY_ROOM=""
}

@test "process_command: blocks unauthorized users when MATRIX_ADMIN_USER is strictly set" {
    MATRIX_ADMIN_USER="@admin:matrix.org"
    process_command "@hacker_user:matrix.org" "uptime" "!room_id"
    [ "$REPLY_MSG" = "⚠️ Access Denied" ]
}

@test "process_command: authenticates correctly matching MATRIX_ADMIN_USER" {
    MATRIX_ADMIN_USER="@admin:matrix.org"
    process_command "@admin:matrix.org" "uptime" "!room_id"
    [ "$REPLY_MSG" = "S: cmd=uptime room=!room_id" ]
}

@test "process_command: allows any user if MATRIX_ADMIN_USER is left empty" {
    MATRIX_ADMIN_USER=""
    process_command "@random:matrix.org" "uptime" "!room_id"
    [ "$REPLY_MSG" = "S: cmd=uptime room=!room_id" ]
}

@test "process_command: correctly routes basic parameterless commands" {
    MATRIX_ADMIN_USER=""

    process_command "@user:domain" "help" "!room"
    [ "$REPLY_MSG" = "H: room=!room" ]

    process_command "@user:domain" "wifi_clients" "!room"
    [ "$REPLY_MSG" = "C: cmd=wifi_clients room=!room" ]
}

@test "process_command: correctly handles complex commands with arguments" {
    MATRIX_ADMIN_USER=""
    process_command "@user:domain" "restart openvpn" "!room"
    [ "$REPLY_MSG" = "SRV: cmd=restart args=openvpn room=!room" ]
}

@test "process_command: sanitizes SAFE_ARGS stripping dangerous script sequences" {
    MATRIX_ADMIN_USER=""

    process_command "@user:domain" "restart nginx; rm -rf /" "!room"
    [ "$REPLY_MSG" = "SRV: cmd=restart args=nginx rm -rf  room=!room" ]
}

@test "process_command: handles unknown commands gracefully without crashing" {
    MATRIX_ADMIN_USER=""
    process_command "@user:domain" "some_crazy_command_name" "!room"
    [ "$REPLY_MSG" = "🤖 Unknown: <code>some_crazy_command_name</code>.<br>Try <code>help</code>" ]
}

@test "process_command: HTML-escapes unknown command containing XSS payload" {
    MATRIX_ADMIN_USER=""
    process_command "@user:domain" '<script>alert(1)</script>' "!room"
    echo "$REPLY_MSG" | grep -q '&lt;script&gt;alert(1)&lt;/script&gt;'
    if echo "$REPLY_MSG" | grep -q '<script>'; then false; fi
}
