#!/usr/bin/env bats

setup() {
    debug_log() { return 0; }
    get_wifi_devices() { echo "wlan0"; }

    export ARP_FILE="${BATS_TEST_TMPDIR}/arp"
    cat <<'EOF' >"$ARP_FILE"
IP address       HW type     Flags       HW address            Mask     Device
192.168.1.100    0x1         0x2         aa:bb:cc:dd:ee:01     *        br-lan
192.168.1.101    0x1         0x2         aa:bb:cc:dd:ee:02     *        br-lan
192.168.1.102    0x1         0x2         aa:bb:cc:dd:ee:03     *        br-lan
192.168.1.103    0x1         0x2         aa:bb:cc:dd:ee:04     *        br-lan
172.20.0.1       0x1         0x2         aa:bb:cc:dd:ee:02     *        br-lan
EOF

    cat() {
        if [ "$1" = "/tmp/dhcp.leases" ]; then
            echo "0 aa:bb:cc:dd:ee:01 192.168.1.100 wifi-phone *"
            echo "0 aa:bb:cc:dd:ee:02 192.168.1.101 wired-pc *"
            echo "0 aa:bb:cc:dd:ee:04 192.168.1.103 * 01:aa:bb:cc:dd:ee:04"
        fi
    }

    ip() {
        if [ "$1" = "-6" ] && [ "$2" = "neigh" ]; then
            echo "fe80::1000:2000:3000:4000 dev br-lan lladdr aa:bb:cc:dd:ee:01 STALE"
            echo "fe80::1000:2000:3000:4001 dev br-lan lladdr aa:bb:cc:dd:ee:02 STALE"
            echo "fe80::dead:beef dev br-lan FAILED"
        elif [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$3" = "show" ]; then
            echo "    inet 192.168.1.1/24 brd 192.168.1.255 scope global br-lan"
        fi
    }

    ubus() {
        if [ "$1" = "call" ] && [ "$2" = "dhcp" ] && [ "$3" = "ipv6leases" ]; then
            printf '{\n'
            printf '  "device": {\n'
            printf '    "br-lan": {\n'
            printf '      "leases": [\n'
            printf '        {\n'
            printf '          "hostname": "wired-pc",\n'
            printf '          "ipv6-addr": [\n'
            printf '            {\n'
            printf '              "address": "fd25:192:168:1::200"\n'
            printf '            }\n'
            printf '          ]\n'
            printf '        }\n'
            printf '      ]\n'
            printf '    }\n'
            printf '  }\n'
            printf '}\n'
        fi
    }

    iwinfo() {
        if [ "$1" = "wlan0" ] && [ "$2" = "info" ]; then
            echo 'ESSID: "Test_SSID"'
            echo 'Channel: 11 (2.4 GHz)'
            echo 'Signal: -45 dBm  Noise: -95 dBm'
        elif [ "$1" = "wlan0" ] && [ "$2" = "assoclist" ]; then
            echo "aa:bb:cc:dd:ee:01  -55 dBm / -90 dBm (SNR 35)  0 ms"
        fi
    }

    uci() {
        if [ "$1" = "show" ] && [ "$2" = "dhcp" ]; then
            echo "dhcp.@host[0]=host"
            echo "dhcp.@host[0].name='static-server'"
            echo "dhcp.@host[0].mac='AA:BB:CC:DD:EE:03'"
            echo "dhcp.@host[0].ip='192.168.1.102'"
            echo "dhcp.@host[1]=host"
            echo "dhcp.@host[1].name='static-unknown-dhcp'"
            echo "dhcp.@host[1].mac='aa:bb:cc:dd:ee:04'"
            echo "dhcp.@host[1].ip='192.168.1.103'"
        elif [ "$1" = "show" ] && [ "$2" = "network" ]; then
            echo "network.lan=interface"
            echo "network.lan.device='br-lan'"
            echo "network.lan.proto='static'"
            echo "network.lan_dev=device"
            echo "network.lan_dev.name='br-lan'"
            echo "network.lan_dev.type='bridge'"
        fi
    }

    source "${BATS_TEST_DIRNAME}/../src/common/04_clients.sh"
}

@test "get_wifi_clients: correctly identifies and formats wireless clients" {
    run get_wifi_clients
    [ "$status" -eq 0 ]

    echo "$output" | grep -q "WiFi (LAN) Clients:"
    echo "$output" | grep -q "Test_SSID"

    echo "$output" | grep -q "wifi-phone"
    echo "$output" | grep -q "192.168.1.100"
    echo "$output" | grep -q -- "-55 dBm"
    echo "$output" | grep -q "fe80::1000:2000:3000:4000"

    if echo "$output" | grep -q "wired-pc"; then false; fi
}

@test "get_wired_clients: identifies arp entries excluding wifi clients" {
    run get_wired_clients
    [ "$status" -eq 0 ]

    echo "$output" | grep -q "Wired (LAN) Clients:"

    echo "$output" | grep -q "wired-pc"
    echo "$output" | grep -q "192.168.1.101"

    echo "$output" | grep -q "static-server"
    echo "$output" | grep -q "192.168.1.102"

    echo "$output" | grep -q "static-unknown-dhcp"
    echo "$output" | grep -q "192.168.1.103"

    if echo "$output" | grep -q "wifi-phone"; then false; fi
}

@test "get_wired_clients: filters out IPs outside managed subnets" {
    run get_wired_clients
    [ "$status" -eq 0 ]

    echo "$output" | grep -q "192.168.1.101"
    if echo "$output" | grep -q "172.20.0.1"; then false; fi

    COUNT=$(echo "$output" | grep -c "wired-pc")
    [ "$COUNT" -eq 1 ]
}

@test "get_wired_clients: resolves DHCPv6 ULA address by hostname" {
    run get_wired_clients
    [ "$status" -eq 0 ]

    echo "$output" | grep -q "fd25:192:168:1::200"
}
