#!/bin/sh

set -eu

OUT_E2EE="usr/lib/matrix/matrix_bot"
OUT_HTTP="usr/lib/matrix/matrix_bot_http"
SEND_E2EE="usr/lib/matrix/matrix_send"
SEND_HTTP="usr/lib/matrix/matrix_send_http"
TMP_FILE="usr/lib/matrix/tmp_$$.sh"

echo "🛠 Building matrix_bot (E2EE)..."

cat src/common/00_base.sh \
    src/common/01_verify_function.sh \
    src/e2ee/01_init.sh \
    src/common/02_helpers.sh \
    src/common/03_wifi.sh \
    src/common/04_clients.sh \
    src/common/05_events.sh \
    src/common/06_commands.sh \
    src/e2ee/07_listener.sh \
    src/e2ee/08_main.sh >"$TMP_FILE"

if command -v shfmt >/dev/null 2>&1; then
    shfmt -w -s -i 4 "$TMP_FILE"
fi

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -e SC3043,SC1090,SC1091 "$TMP_FILE" || {
        echo "❌ Lint failed for E2EE bot build."

        rm -f "$TMP_FILE"
        exit 1
    }
fi

mv "$TMP_FILE" "$OUT_E2EE"

echo "✅ Build complete: $OUT_E2EE"

echo "⚙️ Generating init script for E2EE..."

sed "s|{{SCRIPT}}|/usr/lib/matrix/matrix_bot|g; s|{{NAME}}|matrixbot|g" src/common/matrixbot.init >etc/init.d/matrixbot

echo "🛠 Building matrix_bot_http (HTTP)..."

cat src/common/00_base.sh \
    src/common/01_verify_function.sh \
    src/http/01_init.sh \
    src/common/02_helpers.sh \
    src/common/03_wifi.sh \
    src/common/04_clients.sh \
    src/common/05_events.sh \
    src/common/06_commands.sh \
    src/http/07_listener.sh \
    src/http/08_main.sh >"$TMP_FILE"

if command -v shfmt >/dev/null 2>&1; then
    shfmt -w -s -i 4 "$TMP_FILE"
fi

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -e SC3043,SC1090,SC1091 "$TMP_FILE" || {
        echo "❌ Lint failed for HTTP bot build."

        rm -f "$TMP_FILE"
        exit 1
    }
fi

mv "$TMP_FILE" "$OUT_HTTP"

echo "✅ Build complete: $OUT_HTTP"

echo "⚙️ Generating init script for HTTP..."

sed "s|{{SCRIPT}}|/usr/lib/matrix/matrix_bot_http|g; s|{{NAME}}|matrixbot_http|g" src/common/matrixbot.init >etc/init.d/matrixbot_http

if command -v shellcheck >/dev/null 2>&1; then
    echo "🔍 Linting init scripts..."
    shellcheck -s sh -e SC2034,SC3043 etc/init.d/matrixbot etc/init.d/matrixbot_http || {
        echo "❌ Lint failed for init scripts."
        exit 1
    }
fi

echo "🛠 Building matrix_send (Universal/E2EE)..."

cat src/common/00_base.sh \
    src/common/01_verify_function.sh \
    src/common/sender_01_init.sh \
    src/e2ee/sender_01_ssh_config.sh \
    src/common/sender_01_validate.sh \
    src/e2ee/sender_02_args.sh \
    src/common/sender_03_payload.sh \
    src/common/sender_04_room_logic.sh \
    src/e2ee/sender_04_ssh.sh \
    src/common/sender_05_http.sh >"$TMP_FILE"

if command -v shfmt >/dev/null 2>&1; then
    shfmt -w -s -i 4 "$TMP_FILE"
fi

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -e SC3043,SC1090,SC1091 "$TMP_FILE" || {
        echo "❌ Lint failed for Universal sender build."

        rm -f "$TMP_FILE"
        exit 1
    }
fi
mv "$TMP_FILE" "$SEND_E2EE"
echo "✅ Build complete: $SEND_E2EE"

echo "🛠 Building matrix_send_http (Pure HTTP)..."

cat src/common/00_base.sh \
    src/common/01_verify_function.sh \
    src/common/sender_01_init.sh \
    src/http/sender_01_http_config.sh \
    src/common/sender_01_validate.sh \
    src/http/sender_02_args.sh \
    src/common/sender_03_payload.sh \
    src/common/sender_04_room_logic.sh \
    src/common/sender_05_http.sh >"$TMP_FILE"

if command -v shfmt >/dev/null 2>&1; then
    shfmt -w -s -i 4 "$TMP_FILE"
fi

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s sh -e SC3043,SC1090,SC1091 "$TMP_FILE" || {
        echo "❌ Lint failed for Pure HTTP sender build."

        rm -f "$TMP_FILE"
        exit 1
    }
fi
mv "$TMP_FILE" "$SEND_HTTP"

echo "✅ Build complete: $SEND_HTTP"
