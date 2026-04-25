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

    ls() {
        echo "-rw------- 1 0 0 100 Jan 1 00:00 file"
    }
    export -f ls

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

@test "validate_user_id: accepts empty value" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: rejects user exceeding 255 characters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    local long_localpart=""
    local i=0
    while [ $i -lt 245 ]; do
        long_localpart="${long_localpart}a"
        i=$((i + 1))
    done
    run validate_user_id "@${long_localpart}:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "exceeds 255 characters"
}

@test "validate_user_id: accepts user at exactly 255 characters" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    local long_localpart=""
    local i=0
    while [ $i -lt 243 ]; do
        long_localpart="${long_localpart}a"
        i=$((i + 1))
    done
    run validate_user_id "@${long_localpart}:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: rejects empty localpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "must have localpart and domain"
}

@test "validate_user_id: rejects empty serverpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "must have localpart and domain"
}

@test "validate_user_id: accepts domain with port" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:example.com:8448" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: accepts IPv4 serverpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:192.168.1.1" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: accepts IPv6 serverpart" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:[2001:db8::1]" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_user_id: accepts IPv6 serverpart with port" {
    export MATRIX_URL="https://matrix.org"
    export MATRIX_ACCESS_TOKEN="syt_123"
    export MATRIX_BOT_USER="@bot:matrix.org"
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    source "${BATS_TEST_DIRNAME}/../src/common/bot_03_validate.sh"
    run validate_user_id "@alice:[2001:db8::1]:8448" "VAR" "test"
    [ "$status" -eq 0 ]
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

validate_bool_local() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    *[!01]*)
        logger -t "$log_tag" "FATAL: $var_name contains invalid characters."
        return 1
        ;;
    esac
    return 0
}

validate_path_list_local() {
    local val="$1"
    local var_name="$2"
    local log_tag="$3"
    [ -z "$val" ] && return 0
    case "$val" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./\ -]*)
        logger -t "$log_tag" "FATAL: $var_name contains invalid characters."
        return 1
        ;;
    esac
    return 0
}

@test "validate_bool: accepts empty value" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_bool: accepts value 0" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "0" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_bool: accepts value 1" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "1" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_bool: rejects value 2" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "2" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_bool: rejects value true" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "true" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_bool: rejects value false" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "false" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_bool: rejects value with space" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_bool_local "0 1" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_path_list: accepts empty value" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts single path" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/service" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts multiple paths" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/service /etc/init.d/network" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts hyphen in path" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/my-service" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts underscore in path" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/my_service" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts dot in path" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/service.sh" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: accepts space in path list" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "service-a service_b" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_path_list: rejects semicolon" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/service;rm -rf /" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_path_list: rejects pipe" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local "/usr/sbin/service|cat" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_path_list: rejects dollar sign" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local '/usr/sbin/$PATH' "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_path_list: rejects backtick" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_path_list_local '/usr/sbin/`id`' "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_room_id: accepts empty value" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: accepts valid room" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: accepts room with server port" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:matrix.org:8448" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: accepts room with IPv4 server" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:192.168.1.1" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: accepts room with IPv6 server" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:[2001:db8::1]" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: accepts room with IPv6 server and port" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:[2001:db8::1]:8448" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id: rejects empty localpart" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "empty localpart or domain"
}

@test "validate_room_id: rejects empty serverpart" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room:" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "empty localpart or domain"
}

@test "validate_room_id localpart: accepts lowercase" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!abc123:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts uppercase" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!ABC:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts hyphen" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!my-room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts underscore" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!my_room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts dot" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!my.room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts equals" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!my=room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: accepts slash" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!my/room:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id localpart: rejects space" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room name:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "localpart contains invalid characters"
}

@test "validate_room_id localpart: rejects hash" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room#1:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_room_id localpart: rejects semicolon" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id "!room;rm:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains invalid characters"
}

@test "validate_room_id_list: accepts empty value" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id_list "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_room_id_list: rejects invalid room in list" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id_list "!valid:matrix.org invalid:matrix.org" "VAR" "test"
    [ "$status" -eq 1 ]
}

@test "validate_room_id_list: accepts three valid rooms" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_room_id_list "!room1:matrix.org !room2:matrix.org !room3:matrix.org" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts empty value" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts port 1" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "1" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts port 65535" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "65535" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts port 8080" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "8080" "VAR" "test"
    [ "$status" -eq 0 ]
}

@test "validate_port: rejects port 0" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "0" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "must be between 1 and 65535"
}

@test "validate_port: rejects port 65536" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "65536" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "must be between 1 and 65535"
}

@test "validate_port: rejects port -1" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "-1" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains non-numeric characters"
}

@test "validate_port: rejects negative port" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_port "-8080" "VAR" "test"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "contains non-numeric characters"
}

@test "validate_ipv4: accepts valid IP" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: accepts 0.0.0.0" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: accepts 255.255.255.255" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: rejects leading zero in octet" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168.01.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects octet 256" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168.1.256"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects too many octets" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects empty octet" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168..1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects non-numeric octet" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv4 "192.168.abc.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv6: accepts full address" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001:db8:85a3:0:0:8a2e:370:7334"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: accepts double colon shorthand" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001:db8::1"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: accepts loopback" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "::1"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: accepts all zeros shorthand" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "::"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: accepts with brackets" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "[2001:db8::1]"
    [ "$status" -eq 0 ]
}

@test "validate_ipv6: rejects triple colon" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001:::db8::1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv6: rejects double colon twice" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001::db8::1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv6: rejects invalid characters" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001:db8::1g"
    [ "$status" -eq 1 ]
}

@test "validate_ipv6: rejects too many hextets" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_ipv6 "2001:db8:85a3:0:0:8a2e:370:7334:1"
    [ "$status" -eq 1 ]
}

@test "validate_domain: accepts valid domain" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts subdomain" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "sub.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts digits in domain" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "example123.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: accepts hyphen in domain" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "my-example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain: rejects domain starting with hyphen" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "-example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain ending with hyphen" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "example-"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain starting with dot" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain ".example.com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects domain ending with dot" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "example.com."
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects consecutive dots" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "example..com"
    [ "$status" -eq 1 ]
}

@test "validate_domain: rejects invalid characters" {
    source "${BATS_TEST_DIRNAME}/../src/common/01_common.sh"
    run validate_domain "exam ple.com"
    [ "$status" -eq 1 ]
}
