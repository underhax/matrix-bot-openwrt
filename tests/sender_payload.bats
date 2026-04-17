#!/usr/bin/env bats

setup() {
    export DEBUG_MODE=0
    export FORCE_AWK_FALLBACK=1
    debug_echo() { :; }
    export -f debug_echo
}

@test "sender_payload: AWK_ESC contains POSIX octal codes and 4-slash escapes" {
    export MSG="test"
    export PLAIN_TEXT="test"

    awk() {
        echo "mocked"
    }
    export -f awk

    source src/common/sender_03_payload.sh

    echo "$AWK_ESC" | grep -q 'gsub(/\\010/, "\\\\\\\\b")'
    echo "$AWK_ESC" | grep -q 'gsub(/\\014/, "\\\\\\\\f")'
    echo "$AWK_ESC" | grep -q 'gsub(/\\015/, "\\\\\\\\r")'
    echo "$AWK_ESC" | grep -q 'gsub(/\\011/, "\\\\\\\\t")'
}
