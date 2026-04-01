#!/bin/sh

set -eu

echo "🛠 Building matrix_bot..."

OUT_FILE="usr/lib/matrix/matrix_bot"
TMP_FILE="${OUT_FILE}.tmp"

# 1. Concatenate all modules in order
cat src/01_init.sh \
    src/02_helpers.sh \
    src/03_wifi.sh \
    src/04_clients.sh \
    src/05_events.sh \
    src/06_commands.sh \
    src/07_listeners.sh \
    src/08_main.sh > "$TMP_FILE"

# 2. Format with shfmt if available
if command -v shfmt >/dev/null 2>&1; then
    echo "✨ Formatting with shfmt..."
    shfmt -w -s -i 2 "$TMP_FILE"
else
    echo "⚠️ shfmt not found, skipping formatting."
fi

# 3. Lint with shellcheck if available
if command -v shellcheck >/dev/null 2>&1; then
    echo "🔍 Linting with shellcheck..."
    shellcheck -s sh -e SC3043,SC1090,SC2153 "$TMP_FILE"
else
    echo "⚠️ shellcheck not found, skipping linting."
fi

# 4. Finalize
mv "$TMP_FILE" "$OUT_FILE"
chmod 700 "$OUT_FILE"

echo "✅ Build complete: $OUT_FILE"
