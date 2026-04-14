#!/usr/bin/env bats

setup() {
    debug_log() { return 0; }

    source "${BATS_TEST_DIRNAME}/../src/02_helpers.sh"

    reply() {
        REPLY_MSG="$1"
        REPLY_ROOM="$2"
    }

    process_command() {
        LAST_CMD_SENDER="$1"
        LAST_CMD_BODY="$2"
        LAST_CMD_ROOM="$3"
    }

    MATRIX_BOT_USER="@robot:matrix.tld"
    MATRIX_ROOM_IDS="!FnJELSyCNjDcZigcCJ:matrix.tld !0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs"
    MATRIX_ROOM_ADMIN="!admin_room:matrix.tld"
    MATRIX_ADMIN_USER="@admin:matrix.tld"
    RUN_MODE="http"

    REPLY_MSG=""
    REPLY_ROOM=""
    LAST_CMD_SENDER=""
    LAST_CMD_BODY=""

    source "${BATS_TEST_DIRNAME}/../src/05_events.sh"
}

@test "core_handle_event: ignores messages from unknown/unconfigured rooms" {
    core_handle_event "!unknown_room:matrix.tld" "@admin:matrix.tld" "ping"

    [ "$LAST_CMD_SENDER" = "" ]
    [ "$REPLY_MSG" = "" ]
}

@test "core_handle_event: ignores messages from the bot itself (echo protection)" {
    core_handle_event "!FnJELSyCNjDcZigcCJ:matrix.tld" "@robot:matrix.tld" "uptime"

    [ "$LAST_CMD_SENDER" = "" ]
    [ "$REPLY_MSG" = "" ]
}

@test "core_handle_event: processes valid command from normal user in valid room" {
    ENCRYPTED_CACHE=" !0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs "
    RUN_MODE="http"

    core_handle_event "!FnJELSyCNjDcZigcCJ:matrix.tld" "@admin:matrix.tld" "uptime"

    [ "$LAST_CMD_SENDER" = "@admin:matrix.tld" ]
    [ "$LAST_CMD_BODY" = "uptime" ]
    [ "$LAST_CMD_ROOM" = "!FnJELSyCNjDcZigcCJ:matrix.tld" ]
}

@test "core_handle_event: warns admin when strict E2EE is required globally but room is unencrypted" {
    RUN_MODE="e2ee"
    ENCRYPTED_CACHE=" !0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs "

    core_handle_event "!FnJELSyCNjDcZigcCJ:matrix.tld" "@admin:matrix.tld" "uptime"

    [ "$LAST_CMD_SENDER" = "@admin:matrix.tld" ]
    echo "$REPLY_MSG" | grep -q 'Warning:'
    echo "$REPLY_MSG" | grep -q 'strict E2EE mode'
    [ "$REPLY_ROOM" = "!FnJELSyCNjDcZigcCJ:matrix.tld" ]
}

@test "core_handle_event: processes commands when E2EE is required and room is encrypted" {
    RUN_MODE="e2ee"
    ENCRYPTED_CACHE=" !0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs "

    core_handle_event "!0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs" "@admin:matrix.tld" "uptime"

    [ "$LAST_CMD_SENDER" = "@admin:matrix.tld" ]
    [ "$LAST_CMD_BODY" = "uptime" ]
    [ "$LAST_CMD_ROOM" = "!0xUqYq4IIruJEFcCVhkzezUfk5m2InboKUkXe3ZTmPs" ]
}

@test "core_handle_event: security alert HTML-escapes XSS payload from unauthorized user" {
    ENCRYPTED_CACHE=""
    RUN_MODE="http"

    core_handle_event "!FnJELSyCNjDcZigcCJ:matrix.tld" "@evil:matrix.tld" '<img src=x onerror=alert(1)>'

    echo "$REPLY_MSG" | grep -q 'SECURITY WARNING'
    echo "$REPLY_MSG" | grep -q '&lt;img src=x onerror=alert(1)&gt;'
    if echo "$REPLY_MSG" | grep -q '<img'; then false; fi
    [ "$REPLY_ROOM" = "!admin_room:matrix.tld" ]
}
