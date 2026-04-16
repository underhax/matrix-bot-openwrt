    if [ -z "$MATRIX_URL" ] || [ -z "$MATRIX_ACCESS_TOKEN" ]; then
        printf '[Error] MATRIX_URL or MATRIX_ACCESS_TOKEN missing in config\n' >&2
        exit 1
    fi
else
    printf "[Error] Config file not found: %s\n" "$CONF_FILE" >&2
    exit 1
fi
