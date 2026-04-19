#!/usr/bin/env bats

setup() {
    logger() {
        echo "LOGGER: $*"
    }
    export -f logger

    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
}

@test "validate_core_config: accepts valid MATRIX_URL" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_ValidToken123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 0 ]
}

@test "validate_core_config: rejects MATRIX_URL without http/https" {
    export MATRIX_URL="matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_ValidToken123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "MATRIX_URL must start with"
}

@test "validate_core_config: rejects MATRIX_URL with trailing slash or path" {
    export MATRIX_URL="https://matrix.org/"
    export MATRIX_ACCESS_TOKEN="syt_ValidToken123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid domain structure"
}
@test "validate_core_config: accepts valid MATRIX_URL with port" {
    export MATRIX_URL="http://192.168.1.1:8008"
    export MATRIX_ACCESS_TOKEN="syt_ValidToken123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 0 ]
}

@test "validate_core_config: accepts valid MATRIX_ACCESS_TOKEN" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_Token_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 0 ]
}

@test "validate_core_config: rejects MATRIX_ACCESS_TOKEN without syt_ prefix" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="Token_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "MATRIX_ACCESS_TOKEN must start with 'syt_'"
}

@test "validate_core_config: rejects MATRIX_ACCESS_TOKEN with invalid characters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_Token=123"
    export MATRIX_ROOM_IDS="!room:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "MATRIX_ACCESS_TOKEN contains invalid characters"
}

@test "validate_core_config: accepts valid MATRIX_ROOM_IDS with multiple rooms" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_Token123"
    export MATRIX_ROOM_IDS="!room1:matrix.org !room2:matrix.org"

    run validate_core_config "test_bot"
    [ "$status" -eq 0 ]
}

@test "validate_core_config: rejects MATRIX_ROOM_IDS with command injection characters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_Token123"
    export MATRIX_ROOM_IDS="!room1:matrix.org;rm -rf /"

    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid domain structure"
}
@test "validate_ssh_config: accepts valid SSH config" {
    export SSH_HOST="192.168.1.1"
    export SSH_PORT="22"
    export SSH_USER="user-name_1"
    export SSH_KEY="/root/.ssh/id_rsa"

    source "${BATS_TEST_DIRNAME}/../src/e2ee/03_validate.sh"
    run validate_ssh_config
    [ "$status" -eq 0 ]
    [ -z "$LOG_OUTPUT" ]
}

@test "validate_room_id_list: accepts multiple rooms separated by space" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id_list "!room1:example.com !room2:example.com" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: rejects single room with space" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room1:example.com " "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_room_id: rejects room without ! prefix" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "room1:example.com" "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_room_id: rejects room with multiple ! chars" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room!1:example.com" "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_user_id: accepts valid user" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@myuser:example.com" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: rejects user without @" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "myuser:example.com" "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_user_id: rejects user without domain" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@myuser" "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_user_id localpart: accepts lowercase letters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts digits" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice123:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts hyphen" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice-test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts underscore" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice_test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts dot" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice.test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts equals" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice=test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts slash" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice/test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts plus" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice+test:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts uppercase letters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@ALICE:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: accepts combination" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@Alice-Test_123:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id localpart: rejects space" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice test:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "localpart contains invalid characters"
}

@test "validate_user_id localpart: rejects at sign in localpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice@test:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "localpart contains invalid characters"
}

@test "validate_user_id localpart: rejects hash in localpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice#test:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "localpart contains invalid characters"
}

@test "validate_user_id localpart: rejects exclamation in localpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice!test:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "localpart contains invalid characters"
}

@test "validate_domain_port: rejects domain with consecutive dots" {
    export MATRIX_URL="https://ex..ample.com"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"
    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid domain structure"
}

@test "validate_domain_port: rejects domain starting with hyphen" {
    export MATRIX_URL="https://-example.com"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"
    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid domain structure"
}

@test "validate_domain_port: rejects invalid port" {
    export MATRIX_URL="https://example.com:abc"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"
    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains non-numeric characters"
}

@test "validate_domain_ip: rejects IPv6 with single leading or trailing colon" {
    export MATRIX_URL="https://[2001:db8::1:]"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"
    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "invalid IPv6 structure"
}

@test "validate_domain_ip: rejects IPv4 with too few octets" {
    export MATRIX_URL="https://192.168.1"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_ROOM_IDS="!room:matrix.org"
    run validate_core_config "test_bot"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "invalid IPv4 structure"
}
