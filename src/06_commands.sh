# ==========================================
# COMMAND HANDLERS
# ==========================================

cmd_help() {
    local room_id="$1"
    local nginx_info=""
    local wol_pc_info=""

    if [ -x "/etc/init.d/nginx" ]; then
        nginx_info="Check config & reload nginx<br>Usage: reload nginx<br>"
    fi

    if [ -n "$MAC_PC" ]; then
        wol_pc_info="2. Wake PC<br>Usage: wol_pc<br>"
    fi

    local res
    res="🤖 <b>HELP</b><br>
<br>
<b>INFO:</b><br>
1. Router uptime<br>
Usage: uptime<br>
2. RAM (MB)<br>
Usage: memory<br>
3. Memory Detail (MB)<br>
Usage: meminfo<br>
4. IPv4 (WAN)<br>
Usage: wan_ip<br>
5. DHCP clients<br>
Usage: clients / wifi_clients / wired_clients<br>
<br>
<b>SERVICES:</b><br>
Available: $(get_services_list)<br>
Usage: restart [service]<br>
${nginx_info}
<br>
<b>INTERFACES:</b><br>
Available: $(get_iface_list)<br>
Usage: ifup [interface]<br>
Usage: ifdown [interface]<br>
<br>
<b>WIFI:</b><br>
Usage: wifi_info / wifi_up_2_4 / wifi_down_2_4 / wifi_reload_2_4<br>
wifi_up_5 / wifi_down_5 / wifi_reload_5<br>
<br>
<b>WOL:</b><br>
1. Wake-on-LAN<br>
Usage: wol [mac]<br>
${wol_pc_info}"

    reply "$res" "$room_id"
}

cmd_sysinfo() {
    local cmd="$1"
    local room_id="$2"
    local res=""

    case "$cmd" in
        "uptime")
            local sed_script='s/^[ \t]*//; s/^/time: /; s/ up /<br>up: /; s/,*[ \t]*load average: /<br>load average: /'
            local up_data
            up_data=$(uptime | sed -E "$sed_script")
            res="🤖 <b>Uptime:</b><br>$up_data"
            ;;

        "memory")
            res="🤖 <b>Memory:</b><br>$(free | awk '/Mem:/ {printf "Total: %.0f MB Used: %.0f MB Free: %.0f MB", $2/1024, $3/1024, $4/1024}')"
            ;;

        "meminfo")
            local mem_data
            mem_data=$(awk '$3=="kB"{$2=int($2/1024);$3="MB"} NR<=5{print $0 "<br>"}' /proc/meminfo)
            res="🤖 <b>Memory Detail:</b><br>$mem_data"
            ;;

        "wan_ip")
            local iface
            iface=$(uci -q get network.wan.device)
            [ -z "$iface" ] && iface=$(uci -q get network.wan.ifname)

            local ip=""
            for _url in "4.ipquail.com/ip" "ifconfig.me/ip" "api64.ipify.org"; do
                if [ -n "$iface" ]; then
                    ip=$(curl -4 -s --interface "$iface" --connect-timeout 5 --max-time 10 "https://$_url" 2>/dev/null)
                else
                    ip=$(curl -4 -s --connect-timeout 5 --max-time 10 "https://$_url" 2>/dev/null)
                fi
                case "$ip" in
                    *[0-9].*[0-9].*[0-9].*[0-9]*) break ;;
                    *) ip="" ;;
                esac
            done

            if [ -z "$ip" ]; then
                local ifstatus_tmp="/tmp/ifstatus_$$.tmp"
                ( umask 177 && : > "$ifstatus_tmp" )
                ifstatus wan 2>/dev/null > "$ifstatus_tmp"
                ip=$(extract_json "$ifstatus_tmp" '.["ipv4-address"][0].address // empty' '@["ipv4-address"][0].address')
                rm -f "$ifstatus_tmp"
            fi

            if [ -n "$ip" ]; then
                res="🤖 <b>WAN IP:</b> <code>$ip</code>"
            else
                res="❌ <b>WAN IP:</b> Could not determine (all sources failed)"
            fi
            ;;
    esac

    reply "$res" "$room_id"
}

cmd_clients() {
    local cmd="$1"
    local room_id="$2"
    local res=""

    case "$cmd" in
        "wifi_clients")  res=$(get_wifi_clients) ;;
        "wired_clients") res=$(get_wired_clients) ;;
        "clients")
            res="<b>=== NETWORK REPORT ===</b><br><br>"
            res="${res}$(get_wifi_clients)<br><br>$(get_wired_clients)"
            ;;
    esac

    reply "$res" "$room_id"
}

cmd_service() {
    local cmd="$1"
    local args="$2"
    local room_id="$3"
    local res=""

    case "$cmd" in
        "restart")
            if [ -n "$args" ]; then
                case "$args" in
                    *[!a-zA-Z0-9_-]*)
                        res="⛔ <b>Error:</b> Invalid service name format.<br>Available: $(get_services_list)"
                        reply "$res" "$room_id"
                        return
                        ;;
                esac

                if [ -x "/etc/init.d/$args" ]; then
                    local targets="${SVC_WANTED:-$DEFAULT_SERVICES}"
                    case " $targets " in *" $args "*)
                        res="🤖⏳ Service $args restarting..."
                        background_exec "$args restart" "$room_id" /etc/init.d/"$args" restart
                        ;;
                    *)
                        res="⛔ <b>Access Denied:</b><br>Service '$args' is not in the allowed list: $(get_services_list)"
                        ;;
                    esac
                else
                    res="❌ <b>Error:</b> Service '$args' not found.<br>Available: $(get_services_list)"
                fi
            else
                res="🤖 Usage: restart [service]<br>Available: $(get_services_list)"
            fi
            ;;

        "reload")
            if [ "$args" = "nginx" ]; then
                if [ -x "/usr/sbin/nginx" ]; then
                    if /usr/sbin/nginx -t >/dev/null 2>&1; then
                        res="🤖⏳ Config OK. Nginx reloading..."
                        background_exec "Nginx Reload" "$room_id" /usr/sbin/nginx -s reload
                    else
                        res="❌ <b>Nginx Error:</b> Config check failed! Run 'nginx -t' in terminal to see details."
                    fi
                else
                        res="🤖 Error: Nginx binary not found."
                fi
            else
                res="🤖 Usage: reload nginx"
            fi
            ;;
    esac

    [ -n "$res" ] && reply "$res" "$room_id"
}

cmd_iface() {
    local cmd="$1"
    local args="$2"
    local room_id="$3"
    local res=""

    if [ -n "$args" ]; then
        if [ "$(uci -q get "network.$args")" != "interface" ]; then
            res="⛔ <b>Error:</b> Interface '$args' not found in config."
            reply "$res" "$room_id"
            return
        fi

        case "$cmd" in
            "ifup")
                res="🤖⏳ Interface $args starting..."
                background_exec "Ifup $args" "$room_id" ifup "$args"
                ;;
            "ifdown")
                res="🤖⏳ Interface $args stopping..."
                background_exec "Ifdown $args" "$room_id" ifdown "$args"
                ;;
        esac
    else
        res="🤖 Usage: $cmd interface_name<br>Available: $(get_iface_list)"
    fi

    [ -n "$res" ] && reply "$res" "$room_id"
}

cmd_wifi() {
    local cmd="$1"
    local room_id="$2"

    case "$cmd" in
        "wifi_info"|"wifi")
            local res
            res=$(get_wifi_info)
            reply "$res" "$room_id"
            ;;
        "wifi_down_2_4")   wifi_radio_action down   radio0 "2.4G" "$room_id" ;;
        "wifi_up_2_4")     wifi_radio_action up     radio0 "2.4G" "$room_id" ;;
        "wifi_reload_2_4") wifi_radio_action reload radio0 "2.4G" "$room_id" ;;
        "wifi_down_5")     wifi_radio_action down   radio1 "5G"   "$room_id" ;;
        "wifi_up_5")       wifi_radio_action up     radio1 "5G"   "$room_id" ;;
        "wifi_reload_5")   wifi_radio_action reload radio1 "5G"   "$room_id" ;;
    esac
}

cmd_wol() {
    local cmd="$1"
    local args="$2"
    local room_id="$3"
    local res=""
    local mac_target=""

    case "$cmd" in
        "wol")
            if [ -n "$args" ]; then
                mac_target="$args"
                if ! awk -v m="$mac_target" 'BEGIN { exit !(m ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) }'; then
                    res="⛔ <b>Error:</b> Invalid MAC address format. Expected: AA:BB:CC:DD:EE:FF"
                    reply "$res" "$room_id"
                    return
                fi
            else
                res="🤖 Usage: wol AA:BB:CC:DD:EE:FF<br>You can see available MAC addresses using the command: <code>clients</code>"
                reply "$res" "$room_id"
                return
            fi
            ;;
        "wol_pc")
            if [ -n "$MAC_PC" ]; then
                mac_target="$MAC_PC"
                if ! awk -v m="$mac_target" 'BEGIN { exit !(m ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) }'; then
                    res="❌ <b>Error:</b> Invalid MAC_PC format in config."
                    reply "$res" "$room_id"
                    return
                fi
            else
                res="🤖 Error: MAC_PC variable is not set in bot.conf"
                reply "$res" "$room_id"
                return
            fi
            ;;
    esac

    if [ -n "$mac_target" ]; then
        if command -v etherwake >/dev/null; then
            local iface
            iface=$(uci -q get network.lan.device)
            [ -z "$iface" ] && iface="br-lan"

            local out
            out=$(etherwake -i "$iface" "$mac_target" 2>&1)
            # shellcheck disable=SC2181
            if [ $? -eq 0 ]; then
                [ "$cmd" = "wol_pc" ] && res="🤖 Waking PC (<code>$mac_target</code>)..." || res="🤖 Magic packet sent to <code>$mac_target</code>"
            else
                res="❌ <b>Error:</b> Failed to send WOL.<br>Output: $out"
            fi
        else
            res="❌ <b>Error:</b> <code>etherwake</code> is not installed.<br>Run: <code>opkg update && opkg install etherwake</code>"
        fi
    fi

    [ -n "$res" ] && reply "$res" "$room_id"
}

# ==========================================
# COMMAND DISPATCHER
# ==========================================

# Parses message body into command + arguments, validates, and dispatches to handler functions.
process_command() {
    local SENDER="$1"
    local BODY="$2"
    local ROOM_ID="$3"

    debug_log "CMD: $BODY | Room: $ROOM_ID"

    if [ -n "$MATRIX_ADMIN_USER" ] && [ "$SENDER" != "$MATRIX_ADMIN_USER" ]; then
        reply "⚠️ Access Denied" "$ROOM_ID"
        return
    fi

    set -f
    # shellcheck disable=SC2086
    set -- $BODY
    set +f
    local CMD="$1"
    shift
    local ARGS="$*"

    # Strict allowlist for arguments: blocks all shell metacharacters.
    local SAFE_ARGS
    SAFE_ARGS=$(printf '%s' "$ARGS" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .:_-')

    case "$CMD" in
        "help"|"start") cmd_help "$ROOM_ID" ;;
        "uptime"|"memory"|"meminfo"|"wan_ip") cmd_sysinfo "$CMD" "$ROOM_ID" ;;
        "clients"|*"_clients") cmd_clients "$CMD" "$ROOM_ID" ;;
        "restart"|"reload") cmd_service "$CMD" "$SAFE_ARGS" "$ROOM_ID" ;;
        "ifup"|"ifdown") cmd_iface "$CMD" "$SAFE_ARGS" "$ROOM_ID" ;;
        "wifi"|"wifi_"*) cmd_wifi "$CMD" "$ROOM_ID" ;;
        "wol"|"wol_pc") cmd_wol "$CMD" "$SAFE_ARGS" "$ROOM_ID" ;;
        *) reply "🤖 Unknown: <code>$CMD</code>.<br>Try <code>help</code>" "$ROOM_ID" ;;
    esac
}
