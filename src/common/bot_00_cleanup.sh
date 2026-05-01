core_cleanup() {
    trap - INT TERM EXIT
    rm -rf -- "$BOT_RUN_DIR" 2>/dev/null

    for p in $(jobs -p); do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 1
    for p in $(jobs -p); do
        kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
    done
}
