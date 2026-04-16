init_encryption_cache

listen_http &
MAIN_PID=$!
wait $MAIN_PID
