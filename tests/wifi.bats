#!/usr/bin/env bats

setup() {
    background_exec() {
        LAST_EXEC_CMD="$3 $4 $5"
    }

    uci() {
        if [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "wireless.radio0" ]; then
            return 0
        elif [ "$1" = "show" ] && [ "$2" = "wireless" ]; then
            echo "wireless.radio0=wifi-device"
        else
            return 1
        fi
    }

    reply() { REPLY_MSG="$1"; }

    iwinfo() {
        if [ "$1" = "phy0" ] && [ "$2" = "info" ]; then
            echo 'ESSID: "Test_SSID"'
            echo 'Channel: 11 (2.4 GHz)'
            echo 'Signal: -45 dBm  Noise: -95 dBm'
        elif [ "$1" = "phy1" ] && [ "$2" = "info" ]; then
            echo 'ESSID: "unknown"'
            echo 'Channel: 36 (5 GHz)'
            echo 'Signal: -20 dBm  Noise: -90 dBm'
        elif [ "$*" = "" ]; then
            echo 'phy0      ESSID: "Test_SSID"'
            echo 'phy1      ESSID: "unknown"'
        fi
    }

    html_escape() { echo "$1"; }

    source "${BATS_TEST_DIRNAME}/../src/common/03_wifi.sh"
}

@test "wifi_radio_action: successfully calls background_exec for known radio" {
    LAST_EXEC_CMD=""
    wifi_radio_action down radio0 "2.4G" "!room"
    [ "$LAST_EXEC_CMD" = "wifi down radio0" ]
}

@test "wifi_radio_action: returns error and sends reply for unknown radio" {
    LAST_EXEC_CMD=""
    REPLY_MSG=""

    wifi_radio_action down unknown_radio "2.4G" "!room"
    [ "$REPLY_MSG" = "❌ <b>Error:</b> unknown_radio not found in config." ]
    [ "$LAST_EXEC_CMD" = "" ]
}

@test "get_wifi_devices: extracts interfaces correctly" {
    run get_wifi_devices
    [ "$status" -eq 0 ]
    [ "$output" = "phy0
phy1" ]
}

@test "get_wifi_info: correctly formats HTML summary from iwinfo" {
    run get_wifi_info
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SSID: <code>Test_SSID</code>"
    echo "$output" | grep -q "SSID: <code>Hidden</code>"
    echo "$output" | grep -q "Channel: 11 (2.4 GHz)"
    echo "$output" | grep -q "Channel: 36 (5 GHz)"
}

@test "get_wifi_info: masks wifi keys by default" {
    uci() {
        if [ "$1" = "show" ] && [ "$2" = "wireless" ]; then
            echo "wireless.default_radio0=wifi-iface"
            echo "wireless.default_radio0.ssid='Test_SSID'"
        elif [ "$1" = "-q" ] && [ "$2" = "get" ]; then
            case "$3" in
            wireless.default_radio0.key) echo "password123" ;;
            wireless.default_radio0.encryption) echo "psk2" ;;
            esac
        fi
    }
    WIFI_SHOW_KEY=0
    run get_wifi_info
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Key: <code>\*\*\*\*\*\*\*\*</code>" || {
        echo "Failed output: $output"
        return 1
    }
}

@test "get_wifi_info: shows full key when WIFI_SHOW_KEY=1" {
    uci() {
        if [ "$1" = "show" ] && [ "$2" = "wireless" ]; then
            echo "wireless.default_radio0=wifi-iface"
            echo "wireless.default_radio0.ssid='Test_SSID'"
        elif [ "$1" = "-q" ] && [ "$2" = "get" ]; then
            case "$3" in
            wireless.default_radio0.key) echo "password123" ;;
            wireless.default_radio0.encryption) echo "psk2" ;;
            esac
        fi
    }
    WIFI_SHOW_KEY=1
    run get_wifi_info
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Key: <code>password123</code>" || {
        echo "Failed output: $output"
        return 1
    }
}

@test "get_wifi_info: preserves special characters and emojis in SSID" {
    iwinfo() {
        if [ "$1" = "phy_special" ] && [ "$2" = "info" ]; then
            echo 'ESSID: "WIFI 🚀 + 5G <test>! & @ # $ % ^ * ( )"'
            echo 'Mode: Master  Channel: 11 (2.412 GHz)'
            echo 'Bit Rate: 144.4 MBit/s'
        elif [ "$*" = "" ]; then
            echo 'phy_special      ESSID: "WIFI 🚀 + 5G <test>! & @ # $ % ^ * ( )"'
        fi
    }

    run get_wifi_info
    [ "$status" -eq 0 ]
    echo "$output" | grep -F -q "SSID: <code>WIFI 🚀 + 5G <test>! & @ # $ % ^ * ( )</code>" || {
        echo "Failed output: $output"
        return 1
    }
}
