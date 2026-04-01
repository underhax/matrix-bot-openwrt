# === WIFI RADIO ACTION (DRY helper) ===
# $1=action (up|down|reload), $2=radio UCI name (radio0|radio1),
# $3=human label (2.4G|5G), $4=room_id
wifi_radio_action() {
    local action="$1" radio="$2" label="$3" room_id="$4"
    if ! uci -q get "wireless.$radio" >/dev/null 2>&1; then
        reply "❌ <b>Error:</b> $radio not found in config." "$room_id"
        return
    fi
    reply "🤖⏳ WiFi $label ${action}ing..." "$room_id"
    background_exec "WiFi $label" "$room_id" wifi "$action" "$radio"
}

# === WIFI INFO ===

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

    # Cache UCI wireless config once to prevent slow I/O inside the loop
    UCI_WIRELESS=$(uci show wireless 2>/dev/null)

    for iface in $DEVICES; do
        INFO=$(iwinfo "$iface" info)

        # --- SSID ---
        SSID=$(printf '%s' "$INFO" | awk -F'"' '/ESSID:/ {print $2}')
        if [ "$SSID" = "unknown" ] || [ -z "$SSID" ]; then SSID="[Hidden]"; fi

        SSID=$(printf '%s' "$SSID" | tr -cd 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-')
        if [ -z "$SSID" ]; then SSID="[Hidden]"; fi

        if [ "$WIFI_DETAILED" != "1" ]; then
            MODE=$(printf '%s' "$INFO" | awk -F'Mode: ' '/Mode:/ {split($2, a, " "); print a[1]}')
            CHAN=$(printf '%s' "$INFO" | awk -F'Channel: ' '/Channel:/ {print $2}')
            RATE=$(printf '%s' "$INFO" | awk -F'Bit Rate: ' '/Bit Rate:/ {print $2}')

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
            CHIP=$(printf '%s' "$INFO" | awk '/Hardware:/ {if (match($0, /\[.*\]/)) print substr($0, RSTART+1, RLENGTH-2); else {sub(/.*Hardware: /, ""); print}}')
            BSSID=$(printf '%s' "$INFO" | awk '/Access Point:/ {print $3}')
            COUNTRY=$(printf '%s' "$INFO" | awk 'match($0, /Country: [A-Z]+/) {print substr($0, RSTART+9, RLENGTH-9)}')
            [ -z "$COUNTRY" ] && COUNTRY="World"

            SIGNAL=$(printf '%s' "$INFO" | awk '/Signal:/ {split($0, a, "Signal: "); split(a[2], b, "  Noise"); s=b[1]} /Link Quality:/ {split($0, c, ": "); q=c[2]} END {print (s!="" ? s : q)}')
            NOISE=$(printf '%s' "$INFO" | awk -F'Noise: ' '{print $2}')
            case "$NOISE" in *unknown*) NOISE="0 dBm" ;; esac

            TX_STR=$(printf '%s' "$INFO" | awk '/Tx-Power:/ {split($0,a,"Tx-Power: "); split(a[2],b,"  Link"); print b[1]}')
            TX_VAL=$(printf '%s' "$TX_STR" | tr -cd '0-9')

            if [ -n "$TX_VAL" ]; then
                MW=$(awk "BEGIN {printf \"%.0f\", 10^($TX_VAL/10)}")
                TX_PWR="${TX_VAL} dBm (${MW} mW)"
            else
                TX_PWR="$TX_STR"
            fi

            RATE=$(printf '%s' "$INFO" | awk -F'Bit Rate: ' '{print $2}')
            HT_MODE=$(printf '%s' "$INFO" | awk -F'HT Mode: ' '/HT Mode:/ {print $2}')
            CHAN_NUM=$(printf '%s' "$INFO" | awk -F'Channel: ' '/Channel:/ {print int($2)}')
            CHAN_STR=$(printf '%s' "$INFO" | awk -F'Channel: ' '/Channel:/ {split($2,a,"  HT"); print a[1]}')

            ICON="📡 2.4G"
            STANDARD="802.11?"

            if [ "$CHAN_NUM" -gt 14 ] 2>/dev/null; then
                ICON="🚀 5G"
                case "$HT_MODE" in
                    *VHT*) STANDARD="802.11 ac/n/a" ;;
                    *HE*)  STANDARD="802.11 ax/ac" ;;
                    *HT*)  STANDARD="802.11 n/a" ;;
                    *)     STANDARD="802.11 a" ;;
                esac
            else
                ICON="📡 2.4G"
                case "$HT_MODE" in
                    *HE*) STANDARD="802.11 ax/n/g" ;;
                    *HT*) STANDARD="802.11 b/g/n" ;;
                    *)    STANDARD="802.11 b/g" ;;
                esac
            fi

            WIDTH=$(printf '%s' "$HT_MODE" | sed 's/[A-Z]*//g')
            [ -n "$WIDTH" ] && WIDTH="${WIDTH} MHz" || WIDTH="Legacy"

            CLIENT_COUNT=$(iwinfo "$iface" assoclist | grep -c "dBm")

            KEY="-"
            OCV="-"
            ENC_LIVE=$(printf '%s' "$INFO" | awk -F'Encryption: ' '/Encryption:/ {print $2}')

            SECTION=$(printf '%s\n' "$UCI_WIRELESS" | awk -F. -v pat=".ssid='$SSID'" 'index($0, pat) {print $1"."$2; exit}')

            if [ -n "$SECTION" ]; then
                KEY=$(uci -q get "${SECTION}.key")
                OCV=$(uci -q get "${SECTION}.ocv")
                [ -z "$OCV" ] && OCV="0"

                if [ "$COUNTRY" = "World" ]; then
                    WIFI_DEV=$(uci -q get "${SECTION}.device")
                    [ -n "$WIFI_DEV" ] && COUNTRY_UCI=$(uci -q get "wireless.${WIFI_DEV}.country")
                    [ -n "$COUNTRY_UCI" ] && COUNTRY="${COUNTRY_UCI}"
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
