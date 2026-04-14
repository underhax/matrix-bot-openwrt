#!/usr/bin/env bats

setup() {
    debug_log() { return 0; }

    reply() {
        REPLY_MSG="$1"
        REPLY_ROOM="$2"
    }

    background_exec() {
        BG_EXEC_LABEL="$1"
        BG_EXEC_ROOM="$2"
        BG_EXEC_CMD="$3 $4 $5"
    }

    get_services_list() { echo "nginx dropbear dnsmasq"; }
    get_iface_list() { echo "lan wan loopback"; }

    uptime() { echo " 12:25:20 up 3 days, 13:01,  load average: 0.01, 0.05, 0.10"; }

    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:         248616      102408       52184         548       94024       97284"
        echo "Swap:             0           0           0"
    }

    export PROC_MEMINFO="${BATS_TEST_TMPDIR}/meminfo"
    cat <<'EOF' >"$PROC_MEMINFO"
MemTotal:         248616 kB
MemFree:           52184 kB
MemAvailable:      97284 kB
Buffers:            6200 kB
Cached:            83000 kB
EOF

    uci() {
        if [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "network.lan.device" ]; then
            echo "br-lan"
        elif [ "$1" = "-q" ] && [ "$2" = "get" ] && [ "$3" = "network.wan" ]; then
            echo "interface"
        else
            return 1
        fi
    }

    etherwake() {
        [ "$1" = "-i" ] && [ "$3" = "AA:BB:CC:DD:EE:01" ] && return 0
        echo "etherwake: Invalid MAC"
        return 1
    }

    REPLY_MSG=""
    BG_EXEC_CMD=""

    source "${BATS_TEST_DIRNAME}/../src/06_commands.sh"

    awk() {
        for _a; do
            if [ "$_a" = "/proc/meminfo" ]; then
                set -- "${@%/proc/meminfo}" "$PROC_MEMINFO"
                break
            fi
        done
        command awk "$@"
    }
}

@test "cmd_sysinfo: uptime correctly formats output" {
    cmd_sysinfo "uptime" "!room"

    echo "$REPLY_MSG" | grep -q "🤖 <b>Uptime:</b>"
    echo "$REPLY_MSG" | grep -q "time: 12:25:20"
    echo "$REPLY_MSG" | grep -q "up: 3 days, 13:01"
    echo "$REPLY_MSG" | grep -q "load average: 0.01, 0.05, 0.10"
}

@test "cmd_sysinfo: memory correctly calculates MB" {
    cmd_sysinfo "memory" "!room"

    [ "$REPLY_MSG" = "🤖 <b>Memory:</b><br>Total: 243 MB Used: 100 MB Free: 51 MB" ]
}

@test "cmd_sysinfo: meminfo formats top 5 lines to MB" {
    cmd_sysinfo "meminfo" "!room"

    echo "$REPLY_MSG" | grep -q "MemTotal: 242 MB"
    echo "$REPLY_MSG" | grep -q "MemFree: 50 MB"
    echo "$REPLY_MSG" | grep -q "MemAvailable: 95 MB"
    echo "$REPLY_MSG" | grep -q "Buffers: 6 MB"
    echo "$REPLY_MSG" | grep -q "Cached: 81 MB"
}

@test "cmd_wol: sends magic packet for valid MAC" {
    cmd_wol "wol" "AA:BB:CC:DD:EE:01" "!room"
    [ "$REPLY_MSG" = "🤖 Magic packet sent to <code>AA:BB:CC:DD:EE:01</code>" ]
}

@test "cmd_wol: rejects malformed MAC address" {
    cmd_wol "wol" "bad-mac-address" "!room"
    echo "$REPLY_MSG" | grep -q "Invalid MAC address format"
}

@test "cmd_wol: replies with usage when MAC argument is missing" {
    cmd_wol "wol" "" "!room"
    echo "$REPLY_MSG" | grep -q "Usage: wol"
}

@test "cmd_iface: rejects unknown interface" {
    cmd_iface "ifup" "unknown_iface" "!room"
    echo "$REPLY_MSG" | grep -q "Interface 'unknown_iface' not found"
}

@test "cmd_iface: schedules ifdown via background_exec for known interface" {
    cmd_iface "ifdown" "wan" "!room"
    [ "$BG_EXEC_CMD" = "ifdown wan " ]
}

@test "cmd_service: rejects service with invalid name characters" {
    cmd_service "restart" "***badname***" "!room"
    echo "$REPLY_MSG" | grep -q "Invalid service name format"
}

@test "cmd_service: replies not-found for a non-existent service binary" {
    cmd_service "restart" "unknown_svc" "!room"
    echo "$REPLY_MSG" | grep -q "not found"
}

@test "cmd_service: replies usage when no argument given" {
    cmd_service "restart" "" "!room"
    echo "$REPLY_MSG" | grep -q "Usage: restart"
}
