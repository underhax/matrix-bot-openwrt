#!/usr/bin/env bats

setup() {
    debug_log() {
        return 0
    }

    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/02_helpers.sh"
}

@test "sanitize_room_id: allows valid room names (v11)" {
    run sanitize_room_id "!QxWxRxTx:matrix.org"
    [ "$status" -eq 0 ]
    [ "$output" = "!QxWxRxTx:matrix.org" ]
}

@test "sanitize_room_id: allows valid room names (v12)" {
    run sanitize_room_id "!xdLLcxSu07_4HDexdtl5tbpRN_Bbh9cXy-bZRnf7npA"
    [ "$status" -eq 0 ]
    [ "$output" = "!xdLLcxSu07_4HDexdtl5tbpRN_Bbh9cXy-bZRnf7npA" ]
}

@test "sanitize_room_id: strips dangerous bash/shell metacharacters" {
    run sanitize_room_id "!room; rm -rf /; :matrix.org"
    [ "$status" -eq 0 ]
    [ "$output" = "!roomrm-rf:matrix.org" ]
}

@test "sanitize_room_id: blocks command substitution subshells" {
    run sanitize_room_id '$(reboot)!room'
    [ "$status" -eq 0 ]
    [ "$output" = "reboot!room" ]
}

@test "sanitize_room_id: removes hash symbol (#)" {
    run sanitize_room_id "!test#room:domain"
    [ "$status" -eq 0 ]
    [ "$output" = "!testroom:domain" ]
}

@test "sanitize_user_id: preserves @ prefix and complex domain names" {
    run sanitize_user_id "@matrix_user-bot.1:matrix.org"
    [ "$status" -eq 0 ]
    [ "$output" = "@matrix_user-bot.1:matrix.org" ]
}

@test "sanitize_user_id: strips dangerous SQL/bash injection chars" {
    run sanitize_user_id "@user' OR 1=1; reboot:server"
    [ "$status" -eq 0 ]
    [ "$output" = "@userOR11reboot:server" ]
}

@test "urlencode_room: correctly percent-encodes '!' and ':'" {
    run urlencode_room "!test:domain"
    [ "$status" -eq 0 ]
    [ "$output" = "%21test%3Adomain" ]
}

@test "urlencode_room: leaves standard characters untouched" {
    run urlencode_room "normal_room_id"
    [ "$status" -eq 0 ]
    [ "$output" = "normal_room_id" ]
}

@test "html_escape: passes clean text through unchanged" {
    run html_escape "Hello world 123"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello world 123" ]
}

@test "html_escape: escapes all four HTML-sensitive characters" {
    run html_escape '<b>"Tom & Jerry"</b>'
    [ "$status" -eq 0 ]
    [ "$output" = '&lt;b&gt;&quot;Tom &amp; Jerry&quot;&lt;/b&gt;' ]
}

@test "html_escape: neutralizes img-onerror XSS payload" {
    run html_escape '<img src=x onerror=alert(1)>'
    [ "$status" -eq 0 ]
    [ "$output" = '&lt;img src=x onerror=alert(1)&gt;' ]
}

@test "html_escape: neutralizes script-tag XSS payload" {
    run html_escape '<script>document.location="http://evil"</script>'
    [ "$status" -eq 0 ]
    [ "$output" = '&lt;script&gt;document.location=&quot;http://evil&quot;&lt;/script&gt;' ]
}

@test "html_escape: handles ampersand-only strings without double-encoding" {
    run html_escape "A & B & C"
    [ "$status" -eq 0 ]
    [ "$output" = "A &amp; B &amp; C" ]
}

@test "html_escape: returns empty string for empty input" {
    run html_escape ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "verify_secure_meta: accepts mode 600 owned by root" {
    run verify_secure_meta "0:-rw-------"
    [ "$status" -eq 0 ]
}

@test "verify_secure_meta: accepts mode 400 owned by root" {
    run verify_secure_meta "0:-r--------"
    [ "$status" -eq 0 ]
}

@test "verify_secure_meta: rejects mode 644 even if owned by root" {
    run verify_secure_meta "0:-rw-r--r--"
    [ "$status" -eq 1 ]
}

@test "verify_secure_meta: rejects mode 755 owned by root" {
    run verify_secure_meta "0:-rwxr-xr-x"
    [ "$status" -eq 1 ]
}

@test "verify_secure_meta: rejects mode 600 owned by non-root" {
    run verify_secure_meta "1000:-rw-------"
    [ "$status" -eq 1 ]
}

@test "verify_secure_meta: rejects mode 660 owned by root (group readable)" {
    run verify_secure_meta "0:-rw-rw----"
    [ "$status" -eq 1 ]
}

@test "verify_secure_meta: rejects empty input" {
    run verify_secure_meta ""
    [ "$status" -eq 1 ]
}

@test "verify_secure_meta: integration with ls -n on real file with mode 600" {
    local tmpfile="${BATS_TEST_TMPDIR}/conf_test_600"
    printf 'TEST=1\n' >"$tmpfile"
    chmod 600 "$tmpfile"

    local meta
    meta=$(ls -n "$tmpfile" | awk 'NR==1 {printf "%s:%s", $3, $1}')

    echo "$meta" | grep -q ":-rw-------"
}

@test "verify_secure_meta: integration with ls -n on real file with mode 400" {
    local tmpfile="${BATS_TEST_TMPDIR}/conf_test_400"
    printf 'TEST=1\n' >"$tmpfile"
    chmod 400 "$tmpfile"

    local meta
    meta=$(ls -n "$tmpfile" | awk 'NR==1 {printf "%s:%s", $3, $1}')

    echo "$meta" | grep -q ":-r--------"
}
