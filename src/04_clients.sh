get_hostname() {
    local MAC="$1"
    local DHCP_DATA="$2"
    local STATIC_CACHE="$3"

    MAC=$(printf '%s' "$MAC" | tr -cd '0123456789abcdefABCDEF:')
    [ -z "$MAC" ] && {
        printf 'Unknown\n'
        return
    }

    local NAME
    NAME=$(printf '%s' "$DHCP_DATA" | awk -v m="$MAC" 'tolower($0)~tolower(m) {name=$4} END {print name}')

    if [ -z "$NAME" ] || [ "$NAME" = "*" ] || [ "$NAME" = "Unknown" ]; then
        if [ -n "$STATIC_CACHE" ]; then
            NAME=$(printf '%s' "$STATIC_CACHE" | awk -v m="$MAC" -v RS=" " 'tolower($0)~tolower(m) {split($0,a,"="); print a[2]}')
        else
            local SECTION
            SECTION=$(uci show dhcp | awk -F. -v m="$MAC" -v q="'" 'BEGIN {pat="mac=" q tolower(m)} index(tolower($0), pat) {print $1"."$2; exit}')
            [ -n "$SECTION" ] && NAME=$(uci -q get "${SECTION}.name")
        fi
    fi

    [ -z "$NAME" ] && NAME="Unknown"
    [ "$NAME" = "*" ] && NAME="Unknown"

    printf '%s\n' "$NAME"
}

get_static_leases() {
    uci show dhcp 2>/dev/null | awk -F= \
        '/host.*mac=/ { macs[$1] = tolower($2); gsub(/'"'"'/,"",macs[$1]) }
         /host.*name=/ { names[$1] = $2; gsub(/'"'"'/,"",names[$1]) }
         END { for (i in macs) { idx=i; sub(/\.mac$/, ".name", idx); if (names[idx]) print macs[i] "=" names[idx] } }' |
        tr '\n' ' '
}

get_wifi_clients() {
    printf '🤖 <b>WiFi (LAN) Clients:</b>\n'

    DEVICES=$(get_wifi_devices)
    if [ -z "$DEVICES" ]; then
        printf 'No wireless interfaces found.\n'
        return
    fi

    DHCP_DATA=$(cat /tmp/dhcp.leases 2>/dev/null)
    ARP_DATA=$(cat /proc/net/arp 2>/dev/null)
    IPV6_NEIGH=$(ip -6 neigh show 2>/dev/null)
    STATIC_LEASES=$(get_static_leases)

    for iface in $DEVICES; do
        INFO=$(iwinfo "$iface" info)
        ASSOC_LIST=$(iwinfo "$iface" assoclist)

        # Single awk: parse iwinfo info/assoclist + all lookup sources, emit HTML
        printf '%s\n---ASSOC---\n%s\n---DHCP---\n%s\n---ARP---\n%s\n---STATIC---\n%s\n---IPV6---\n%s\n' \
            "$INFO" "$ASSOC_LIST" "$DHCP_DATA" "$ARP_DATA" "$STATIC_LEASES" "$IPV6_NEIGH" |
            awk -v iface="$iface" '
            BEGIN { section = "info" }
            /^---ASSOC---$/ { section = "assoc"; next }
            /^---DHCP---$/ { section = "dhcp"; next }
            /^---ARP---$/ { section = "arp"; next }
            /^---STATIC---$/ { section = "static"; next }
            /^---IPV6---$/ { section = "ipv6"; next }

            section == "info" && /ESSID:/ {
                if (match($0, /"[^"]*"/)) ssid = substr($0, RSTART+1, RLENGTH-2)
            }
            section == "info" && /Channel:/ {
                split($0, a, "Channel: "); chan = int(a[2])
            }

            section == "assoc" && /dBm/ {
                assoc_macs[++assoc_count] = tolower($1)
                assoc_signal[tolower($1)] = $2 " " $3
            }

            section == "dhcp" && NF >= 4 {
                m = tolower($2); dhcp_ip[m] = $3; dhcp_name[m] = $4
            }

            section == "arp" && NF >= 4 && $3 ~ /^0x/ && $3 != "0x0" && $4 != "00:00:00:00:00:00" {
                m = tolower($4)
                if (!(m in dhcp_ip)) arp_ip[m] = $1
            }

            section == "static" {
                n = split($0, items, " ")
                for (i = 1; i <= n; i++) {
                    if (items[i] == "") continue
                    split(items[i], kv, "=")
                    if (kv[1] != "" && kv[2] != "") static_name[kv[1]] = kv[2]
                }
            }

            section == "ipv6" && NF >= 5 {
                m = tolower($5); addr = $1
                if (addr !~ /^fe80/ && !(m in ipv6g)) ipv6g[m] = addr
                else if (addr ~ /^fe80/ && !(m in ipv6l)) ipv6l[m] = addr
            }

            END {
                if (ssid == "" || ssid == "unknown") ssid = "Hidden"
                if (chan+0 > 14) icon = "\360\237\232\200 5G"
                else icon = "\360\237\223\241 2.4G"

                printf "<br><br><b>%s %s</b> [%s] (%d)<br>\n", icon, ssid, iface, assoc_count

                if (assoc_count == 0) {
                    printf "<br><i>No clients.</i>\n"
                } else {
                    for (i = 1; i <= assoc_count; i++) {
                        mac = assoc_macs[i]

                        ip = ""
                        if (mac in dhcp_ip) ip = dhcp_ip[mac]
                        if (ip == "" && (mac in arp_ip)) ip = arp_ip[mac]
                        if (ip == "") ip = "Unknown"

                        name = ""
                        if (mac in dhcp_name && dhcp_name[mac] != "*" && dhcp_name[mac] != "Unknown")
                            name = dhcp_name[mac]
                        if (name == "" && (mac in static_name)) name = static_name[mac]
                        if (name == "") name = "Unknown"

                        ipv6 = ""
                        if (mac in ipv6g) ipv6 = ipv6g[mac]
                        else if (mac in ipv6l) ipv6 = ipv6l[mac]

                        printf "<br>\360\237\233\234 <b>%s</b>\n", name
                        printf "<br>IPv4: <code>%s</code> | %s\n", ip, assoc_signal[mac]
                        if (ipv6 != "") printf "<br>IPv6: <small><code>%s</code></small>\n", ipv6
                        printf "<br>Mac: <small>%s</small>\n", mac
                    }
                }
            }'
    done
}

get_wired_clients() {
    printf '🤖 <b>Wired (LAN) Clients:</b>\n'

    BRIDGE_DEVS=$(uci show network 2>/dev/null | awk -F"'" '
        /\.type=.bridge/ { sec=$0; sub(/\.type=.*/, "", sec); is_bridge[sec]=1 }
        /\.name=/  { sec=$0; sub(/\.name=.*/, "", sec); dev_name[sec]=$2 }
        /\.proto=.static/ { sec=$0; sub(/\.proto=.*/, "", sec); is_static[sec]=1 }
        /\.device=/ { sec=$0; sub(/\.device=.*/, "", sec); iface_dev[sec]=$2 }
        END {
            for (s in is_bridge)
                if (s in dev_name) br[dev_name[s]]=1
            for (s in is_static)
                if ((s in iface_dev) && (iface_dev[s] in br))
                    printf "%s ", iface_dev[s]
        }')

    # shellcheck disable=SC2086
    BRIDGE_NETS=$(ip -4 addr show 2>/dev/null | awk -v devs=" $BRIDGE_DEVS " '
        /inet / && index(devs, " " $NF " ") > 0 { printf "%s=%s ", $2, $NF }')

    WIFI_MACS=""
    WIFI_DEVICES=$(get_wifi_devices)
    for dev in $WIFI_DEVICES; do
        MACS=$(iwinfo "$dev" assoclist | awk '/dBm/ {printf "%s ", tolower($1)}')
        WIFI_MACS="${WIFI_MACS}${MACS}"
    done

    DHCP_DATA=$(cat /tmp/dhcp.leases 2>/dev/null)
    STATIC_LEASES=$(get_static_leases)
    IPV6_NEIGH=$(ip -6 neigh show 2>/dev/null)
    DHCPv6_DATA=$(ubus call dhcp ipv6leases 2>/dev/null | awk \
        '/"hostname"/ { gsub(/[",]/, ""); h = $2 }
         /"address"/ { gsub(/[",]/, ""); if (h != "") print h, $2 }')

    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "---DHCP---" "$DHCP_DATA" "---STATIC---" "$STATIC_LEASES" \
        "---IPV6---" "$IPV6_NEIGH" "---DHCPv6---" "$DHCPv6_DATA" |
        awk -v wifi=" ${WIFI_MACS}" -v nets="$BRIDGE_NETS" '
        BEGIN {
            sn = split(nets, nlist, " ")
            for (i = 1; i <= sn; i++) {
                split(nlist[i], eq, "=")
                split(eq[1], p, "/")
                sub_ip[i] = p[1]
                sub_bits[i] = p[2] + 0
                sub_dev[i] = eq[2]
            }
        }

        function ip2num(ip,    a) {
            split(ip, a, ".")
            return a[1] * 16777216 + a[2] * 65536 + a[3] * 256 + a[4]
        }

        function in_managed(ip, dev,    i, d) {
            for (i = 1; i <= sn; i++) {
                if (dev != sub_dev[i]) continue
                d = 2 ^ (32 - sub_bits[i])
                if (int(ip2num(ip) / d) == int(ip2num(sub_ip[i]) / d))
                    return 1
            }
            return 0
        }

        FNR == NR {
            if (NF >= 6 && $4 != "00:00:00:00:00:00" && $3 != "0x0") {
                m = tolower($4)
                if (index(wifi, " " m " ") == 0 && in_managed($1, $6)) {
                    arp_macs[++arp_count] = m
                    arp_ips[arp_count] = $1
                }
            }
            next
        }

        /^---DHCP---$/ { section = "dhcp"; next }
        /^---STATIC---$/ { section = "static"; next }
        /^---IPV6---$/ { section = "ipv6"; next }
        /^---DHCPv6---$/ { section = "dhcpv6"; next }

        section == "dhcp" && NF >= 4 {
            m = tolower($2); dhcp_name[m] = $4
        }

        section == "static" {
            n = split($0, items, " ")
            for (i = 1; i <= n; i++) {
                if (items[i] == "") continue
                split(items[i], kv, "=")
                if (kv[1] != "" && kv[2] != "") static_name[kv[1]] = kv[2]
            }
        }

        section == "ipv6" && NF >= 5 {
            m = tolower($5); addr = $1
            if (addr !~ /^fe80/ && !(m in ipv6g)) ipv6g[m] = addr
            else if (addr ~ /^fe80/ && !(m in ipv6l)) ipv6l[m] = addr
        }

        section == "dhcpv6" && NF >= 2 {
            dhcpv6[tolower($1)] = $2
        }

        END {
            if (arp_count == 0) {
                printf "<br><br><i>No active wired clients found.</i>\n"
            } else {
                for (i = 1; i <= arp_count; i++) {
                    mac = arp_macs[i]

                    name = ""
                    if (mac in dhcp_name && dhcp_name[mac] != "*" && dhcp_name[mac] != "Unknown")
                        name = dhcp_name[mac]
                    if (name == "" && (mac in static_name)) name = static_name[mac]
                    if (name == "") name = "Unknown"

                    ipv6 = ""
                    if (tolower(name) in dhcpv6) ipv6 = dhcpv6[tolower(name)]
                    if (ipv6 == "" && (mac in ipv6g)) ipv6 = ipv6g[mac]
                    if (ipv6 == "" && (mac in ipv6l)) ipv6 = ipv6l[mac]

                    printf "<br><br>\360\237\214\220 <b>%s</b>\n", name
                    printf "<br>IPv4: <code>%s</code>\n", arp_ips[i]
                    if (ipv6 != "") printf "<br>IPv6: <small><code>%s</code></small>\n", ipv6
                    printf "<br>Mac: <small>%s</small>\n", mac
                }
            }
        }' "${ARP_FILE:-/proc/net/arp}" -
}
