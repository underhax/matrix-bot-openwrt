wifi_radio_action() {
    local action="$1" radio="$2" label="$3" room_id="$4"
    if ! uci -q get "wireless.$radio" >/dev/null 2>&1; then
        reply "❌ <b>Error:</b> $radio not found in config." "$room_id"
        return
    fi
    reply "🤖⏳ WiFi $label ${action}ing..." "$room_id"
    background_exec "WiFi $label" "$room_id" wifi "$action" "$radio"
}

get_wifi_devices() {
    iwinfo 2>/dev/null | awk '/ESSID/ {print $1}'
}

get_wifi_info() {
    local OUT="🤖 <b>WiFi Status:</b>"

    DEVICES=$(get_wifi_devices)

    if [ -z "$DEVICES" ]; then
        printf "🤖 No wireless interfaces found.\n"
        return
    fi

    UCI_WIRELESS=$(uci show wireless 2>/dev/null)

    for iface in $DEVICES; do
        INFO=$(iwinfo "$iface" info)

        if [ "$WIFI_DETAILED" != "1" ]; then
            _parsed=$(printf '%s' "$INFO" | awk '
                /ESSID:/ { if (match($0, /"[^"]*"/)) ssid = substr($0, RSTART+1, RLENGTH-2) }
                /Mode:/ { split($0, a, "Mode: "); split(a[2], b, " "); mode = b[1] }
                /Channel:/ { split($0, a, "Channel: "); chan = a[2] }
                /Bit Rate:/ { split($0, a, "Bit Rate: "); rate = a[2] }
                END {
                    if (ssid == "" || ssid == "unknown") ssid = ""
                    gsub(/[^a-zA-Z0-9 ._-]/, "", ssid)
                    if (ssid == "") ssid = "Hidden"
                    printf "%s|%s|%s|%s", ssid, mode, chan, rate
                }')
            IFS='|' read -r SSID MODE CHAN RATE <<EOF
$_parsed
EOF

            KEY="-"
            ENCRYPTION="-"
            SECTION=$(printf '%s\n' "$UCI_WIRELESS" | awk -F. -v pat=".ssid='$SSID'" 'index($0, pat) {print $1"."$2; exit}')
            if [ -n "$SECTION" ]; then
                KEY=$(uci -q get "${SECTION}.key")
                ENCRYPTION=$(uci -q get "${SECTION}.encryption")
                [ -z "$ENCRYPTION" ] && ENCRYPTION="Unknown"
            fi

            OUT="${OUT}<br><br><b>${iface}</b><br>"
            OUT="${OUT}SSID: <code>${SSID}</code> (${MODE})<br>"
            OUT="${OUT}Crypt: ${ENCRYPTION}<br>"
            if [ -n "$KEY" ]; then OUT="${OUT}Key: <code>${KEY}</code><br>"; fi
            OUT="${OUT}Channel: ${CHAN}<br>"
            OUT="${OUT}Rate: ${RATE}"

        else
            _parsed=$(printf '%s' "$INFO" | awk '
                /ESSID:/ { if (match($0, /"[^"]*"/)) ssid = substr($0, RSTART+1, RLENGTH-2) }
                /Hardware:/ {
                    if (match($0, /\[.*\]/)) chip = substr($0, RSTART+1, RLENGTH-2)
                    else { sub(/.*Hardware: */, ""); chip = $0 }
                }
                /Access Point:/ { bssid = $3 }
                /Country:/ {
                    if (match($0, /Country: [A-Z]+/)) country = substr($0, RSTART+9, RLENGTH-9)
                }
                /Signal:/ {
                    split($0, a, "Signal: "); split(a[2], b, "  Noise")
                    signal = b[1]
                }
                /Link Quality:/ {
                    if (signal == "") { split($0, c, "Link Quality: "); lq = c[2] }
                }
                /Noise:/ { split($0, a, "Noise: "); noise = a[2] }
                /Tx-Power:/ {
                    split($0, a, "Tx-Power: "); split(a[2], b, "  Link")
                    tx_str = b[1]; tx_val = tx_str
                    gsub(/[^0-9]/, "", tx_val); tx_val = tx_val + 0
                    if (tx_val > 0) tx_pwr = tx_val " dBm (" sprintf("%.0f", 10^(tx_val/10)) " mW)"
                    else tx_pwr = tx_str
                }
                /Bit Rate:/ { split($0, a, "Bit Rate: "); rate = a[2] }
                /HT Mode:/ {
                    split($0, a, "HT Mode: "); ht_mode = a[2]
                    width = ht_mode; gsub(/[A-Z]/, "", width)
                }
                /Channel:/ {
                    split($0, a, "Channel: "); chan_num = int(a[2])
                    split(a[2], d, "  HT"); chan_str = d[1]
                }
                /Encryption:/ { split($0, a, "Encryption: "); enc = a[2] }
                END {
                    if (ssid == "" || ssid == "unknown") ssid = ""
                    gsub(/[^a-zA-Z0-9 ._-]/, "", ssid)
                    if (ssid == "") ssid = "Hidden"
                    if (signal == "") signal = lq
                    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", \
                        ssid, chip, bssid, country, signal, noise, \
                        tx_pwr, rate, ht_mode, chan_num, chan_str, enc, width
                }')
            IFS='|' read -r SSID CHIP BSSID COUNTRY SIGNAL NOISE \
                TX_PWR RATE HT_MODE CHAN_NUM CHAN_STR ENC_LIVE WIDTH <<EOF
$_parsed
EOF

            [ -z "$COUNTRY" ] && COUNTRY="World"
            case "$NOISE" in *unknown*) NOISE="0 dBm" ;; esac
            [ -n "$WIDTH" ] && WIDTH="${WIDTH} MHz" || WIDTH="Legacy"

            ICON="📡 2.4G"
            STANDARD="802.11?"

            if [ "$CHAN_NUM" -gt 14 ] 2>/dev/null; then
                ICON="🚀 5G"
                case "$HT_MODE" in
                *VHT*) STANDARD="802.11 ac/n/a" ;;
                *HE*) STANDARD="802.11 ax/ac" ;;
                *HT*) STANDARD="802.11 n/a" ;;
                *) STANDARD="802.11 a" ;;
                esac
            else
                case "$HT_MODE" in
                *HE*) STANDARD="802.11 ax/n/g" ;;
                *HT*) STANDARD="802.11 b/g/n" ;;
                *) STANDARD="802.11 b/g" ;;
                esac
            fi

            CLIENT_COUNT=$(iwinfo "$iface" assoclist | grep -c "dBm")

            KEY="-"
            OCV="-"
            SECTION=$(printf '%s\n' "$UCI_WIRELESS" | awk -F. -v pat=".ssid='$SSID'" 'index($0, pat) {print $1"."$2; exit}')

            if [ -n "$SECTION" ]; then
                KEY=$(uci -q get "${SECTION}.key")
                OCV=$(uci -q get "${SECTION}.ocv")
                [ -z "$OCV" ] && OCV="0"

                if [ "$COUNTRY" = "World" ]; then
                    local WIFI_DEV=""
                    WIFI_DEV=$(uci -q get "${SECTION}.device")
                    local COUNTRY_UCI=""
                    [ -n "$WIFI_DEV" ] && COUNTRY_UCI=$(uci -q get "wireless.${WIFI_DEV}.country")
                    [ -n "$COUNTRY_UCI" ] && COUNTRY="$COUNTRY_UCI"
                fi
            fi

            OUT="${OUT}<br><br><b>${ICON} ${iface}</b><br>"
            OUT="${OUT}<i>${CHIP}</i><br>"
            OUT="${OUT}SSID: <code>${SSID}</code><br>"
            OUT="${OUT}BSSID: ${BSSID} | Country: ${COUNTRY}<br>"
            OUT="${OUT}Mode: ${STANDARD} (${WIDTH})<br>"
            OUT="${OUT}Crypt: ${ENC_LIVE}<br>"

            if [ -n "$KEY" ]; then
                OUT="${OUT}Key: <code>${KEY}</code><br>"
            fi

            OUT="${OUT}Clients: <b>${CLIENT_COUNT}</b> | OCV: ${OCV}<br>"
            OUT="${OUT}Channel: ${CHAN_STR}<br>"
            OUT="${OUT}Tx: ${TX_PWR} | Rate: ${RATE}<br>"
            OUT="${OUT}Signal: ${SIGNAL} | Noise: ${NOISE}"
        fi
    done

    printf '%s\n' "$OUT"
}
