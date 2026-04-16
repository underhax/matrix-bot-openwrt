if [ -z "$MATRIX_URL" ] || [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_BOT_USER" ]; then
    printf "Error: Required Matrix configuration missing\n" >&2
    exit 1
fi
