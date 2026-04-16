init_encryption_cache

listen_e2ee &
MAIN_PID=$!
wait $MAIN_PID
