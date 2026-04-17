PLAIN_TEXT=$(printf '%s' "$MSG" | sed 's/<[bB][rR][^>]*>/\n/g; s/<[^>]*>//g')

if [ "$DEBUG_MODE" -eq 1 ]; then
    printf '%s\n' "--- PREPARED DATA ---"
    printf 'Notification Body (Plain):\n%s\n' "$PLAIN_TEXT"
    printf '%s\n' "-----------------------"
    printf 'Room Message (HTML):\n%s\n' "$MSG"
    printf '%s\n' "-----------------------"
fi

if [ "$FORCE_AWK_FALLBACK" -eq 0 ] && command -v jq >/dev/null 2>&1; then
    debug_echo "JSON Strategy: JQ (Best Practice)"
    JSON_PAYLOAD=$(jq -n --arg b "$PLAIN_TEXT" --arg f "$MSG" \
        '{msgtype: "m.text", body: $b, format: "org.matrix.custom.html", formatted_body: $f}')
else
    if [ "$FORCE_AWK_FALLBACK" -eq 1 ]; then
        debug_echo "JSON Strategy: Native (awk fallback) [FORCED]"
    else
        debug_echo "JSON Strategy: Native (awk fallback)"
    fi

    # shellcheck disable=SC2016
    AWK_ESC='{
        gsub(/\\/, "\\\\\\\\")
        gsub(/"/, "\\\\\"")
        gsub(/\010/, "\\\\b")
        gsub(/\014/, "\\\\f")
        gsub(/\015/, "\\\\r")
        gsub(/\011/, "\\\\t")
        if (NR > 1) printf "\\n"
        printf "%s", $0
    }'
    ESC_PLAIN=$(printf '%s' "$PLAIN_TEXT" | awk "$AWK_ESC")
    ESC_HTML=$(printf '%s' "$MSG" | awk "$AWK_ESC")
    JSON_PAYLOAD="{\"msgtype\":\"m.text\",\"body\":\"$ESC_PLAIN\",\"format\":\"org.matrix.custom.html\",\"formatted_body\":\"$ESC_HTML\"}"
fi
