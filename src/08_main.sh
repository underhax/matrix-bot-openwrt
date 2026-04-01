# === LAUNCH ===
init_encryption_cache

case "$RUN_MODE" in
    "e2ee")
        listen_e2ee &
        MAIN_PID=$!
        wait $MAIN_PID
        ;;
    "http")
        listen_http &
        MAIN_PID=$!
        wait $MAIN_PID
        ;;
    "auto")
        printf 'Starting AUTO mode...\n'
        listen_e2ee &
        MAIN_PID=$!
        listen_http
        ;;
esac
