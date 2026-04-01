# ==========================================
# CLIENT DISPLAY FUNCTIONS
# ==========================================

# Resolves MAC address to hostname via DHCP leases or UCI static config.
get_hostname() {
    local MAC="$1"
    local DHCP_DATA="$2"
    local STATIC_CACHE="$3"

    MAC=$(printf '%s' "$MAC" | tr -cd '0123456789abcdefABCDEF:')
    [ -z "$MAC" ] && { printf 'Unknown\n'; return; }

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

# Loads static DHCP leases from UCI into a "mac=name ..." string.
# Pre-loading avoids calling uci inside per-client loops (slow I/O on OpenWrt flash).
get_static_leases() {
    uci show dhcp 2>/dev/null | awk -F. \
        '/host.*mac/ { split($2,a,"="); mac=tolower(a[2]); gsub(/'"'"'/,"",mac) }
         /host.*name/ { split($2,a,"="); name=a[2]; gsub(/'"'"'/,"",name); if(mac) print mac "=" name }' \
        | tr '\n' ' '
}

get_wifi_clients() {
    printf '🤖 <b>WiFi (LAN) Clients:</b>\n'

    DHCP_DATA=$(cat /tmp/dhcp.leases 2>/dev/null)
    ARP_DATA=$(cat /proc/net/arp 2>/dev/null)
    DEVICES=$(get_wifi_devices)
    IPV6_NEIGH=$(ip -6 neigh show 2>/dev/null)
    STATIC_LEASES=$(get_static_leases)

    if [ -z "$DEVICES" ]; then
        printf 'No wireless interfaces found.\n'
        return
    fi

    for iface in $DEVICES; do
        INFO=$(iwinfo "$iface" info)

        SSID=$(printf '%s' "$INFO" | awk -F'"' '/ESSID:/ {print $2}')
        [ -z "$SSID" ] && SSID="Hidden"

        CHAN=$(printf '%s' "$INFO" | awk -F'Channel: ' '/Channel:/ {print int($2)}')
        if [ "$CHAN" -gt 14 ] 2>/dev/null; then ICON="🚀 5G"; else ICON="📡 2.4G"; fi

        ASSOC_LIST=$(iwinfo "$iface" assoclist)
        COUNT=$(printf '%s' "$ASSOC_LIST" | grep -c "dBm")

        printf '<br><br><b>%s %s</b> [%s] (%s)<br>\n' "$ICON" "$SSID" "$iface" "$COUNT"

        if [ "$COUNT" -eq 0 ]; then
            printf '<br><i>No clients.</i>\n'
            continue
        fi

        printf '%s\n' "$ASSOC_LIST" | while read -r line; do
            case "$line" in *dBm*) ;; *) continue ;; esac

            # shellcheck disable=SC2086
            set -- $line
            MAC="$1"
            SIGNAL="$2 $3"

            IP=$(printf '%s\n' "$DHCP_DATA" | awk -v m="$MAC" 'tolower($0)~tolower(m) {ip=$3} END {print ip}')
            if [ -z "$IP" ]; then
                IP=$(printf '%s\n' "$ARP_DATA" | awk -v m="$MAC" '$0~m {print $1; exit}')
                [ -z "$IP" ] && IP="Unknown"
            fi

            NAME=$(printf '%s' "$DHCP_DATA" | awk -v m="$MAC" 'tolower($0)~tolower(m) {name=$4} END {print name}')

            if [ -z "$NAME" ] || [ "$NAME" = "*" ] || [ "$NAME" = "Unknown" ]; then
                NAME=$(printf '%s' "$STATIC_LEASES" | awk -v m="$MAC" -v RS=" " 'tolower($0)~tolower(m) {split($0,a,"="); print a[2]}')
            fi
            [ -z "$NAME" ] && NAME="Unknown"

            IPV6=$(printf '%s\n' "$IPV6_NEIGH" | awk -v m="$MAC" 'tolower($0)~tolower(m) {if ($1!~/^fe80/) {print $1; f=1; exit} else {ll=$1}} END {if (!f && ll) print ll}')

            printf '<br>🛜 <b>%s</b>\n' "$NAME"
            printf '<br>IPv4: <code>%s</code> | %s\n' "$IP" "$SIGNAL"
            if [ -n "$IPV6" ]; then printf '<br>IPv6: <small><code>%s</code></small>\n' "$IPV6"; fi
            printf '<br>Mac: <small>%s</small>\n' "$MAC"
        done
    done
}

# Identifies wired clients by filtering ARP table against wireless MACs.
get_wired_clients() {
    printf '🤖 <b>Wired (LAN) Clients:</b>\n'

    LAN_IFACE=$(uci -q get network.lan.device)
    [ -z "$LAN_IFACE" ] && LAN_IFACE="br-lan"

    WIFI_MACS=""
    WIFI_DEVICES=$(get_wifi_devices)

    for dev in $WIFI_DEVICES; do
        MACS=$(iwinfo "$dev" assoclist | awk '{print tolower($1)}' | tr '\n' ' ')
        WIFI_MACS="${WIFI_MACS}${MACS}"
    done
    WIFI_MACS=" ${WIFI_MACS} "

    DHCP_DATA=$(cat /tmp/dhcp.leases 2>/dev/null)
    STATIC_LEASES=$(get_static_leases)
    IPV6_NEIGH=$(ip -6 neigh show 2>/dev/null)

    # Single awk pass over /proc/net/arp:
    # - Skip header (NR>1)
    # - Match only the LAN bridge interface ($6==dev)
    # - Exclude null entries and incomplete ARP state
    # - Exclude MACs already seen on wireless (index in space-padded list)
    VALID_ARP=$(awk -v dev="$LAN_IFACE" -v wifi="$WIFI_MACS" \
        'NR>1 && $6==dev && $4!="00:00:00:00:00:00" && $3!="0x0" && index(wifi, " "tolower($4)" ")==0 {print $1, $4}' /proc/net/arp)

    if [ -z "$VALID_ARP" ]; then
        printf '<br><br><i>No active wired clients found.</i>\n'
        return
    fi

    printf '%s\n' "$VALID_ARP" | while read -r IP MAC; do
        NAME=$(get_hostname "$MAC" "$DHCP_DATA" "$STATIC_LEASES")
        IPV6=$(printf '%s\n' "$IPV6_NEIGH" | awk -v m="$MAC" 'tolower($0)~tolower(m) {if ($1!~/^fe80/) {print $1; f=1; exit} else {ll=$1}} END {if (!f && ll) print ll}')

        printf '<br><br>🌐 <b>%s</b>\n' "$NAME"
        printf '<br>IPv4: <code>%s</code>\n' "$IP"
        if [ -n "$IPV6" ]; then printf '<br>IPv6: <small><code>%s</code></small>\n' "$IPV6"; fi
        printf '<br>Mac: <small>%s</small>\n' "$MAC"
    done
}
