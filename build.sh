#!/bin/sh

set -eu

OUT_FILE="usr/lib/matrix/matrix_bot"
TMP_FILE="${OUT_FILE}.tmp"

echo "🛠 Building matrix_bot..."

cat src/01_init.sh \
    src/02_helpers.sh \
    src/03_wifi.sh \
    src/04_clients.sh \
    src/05_events.sh \
    src/06_commands.sh \
    src/07_listeners.sh \
    src/08_main.sh >"$TMP_FILE"

if command -v shfmt >/dev/null 2>&1; then
    echo "✨ Formatting with shfmt..."
    shfmt -w -s -i 4 "$TMP_FILE"
else
    echo "⚠️ shfmt not found, skipping formatting."
fi

if command -v shellcheck >/dev/null 2>&1; then
    echo "🔍 Linting with shellcheck..."
    if ! shellcheck -s sh -e SC3043,SC1090 "$TMP_FILE"; then
        echo "❌ Lint failed. Fix errors above."
        rm -f "$TMP_FILE"
        exit 1
    fi
else
    echo "⚠️ shellcheck not found, skipping lint."
fi

mv "$TMP_FILE" "$OUT_FILE"
chmod 700 "$OUT_FILE"

echo "✅ Build complete: $OUT_FILE"
