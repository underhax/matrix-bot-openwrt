#!/bin/sh
# ==============================================================================
# Matrix Bot for OpenWrt
# Description: Remote router management via Matrix protocol.
# Features: E2EE support via matrix-commander-rs, HTTP fallback, service control.
# Author: DevSec
# License: MIT
# ==============================================================================

export LC_ALL=C

# === CONFIGURATION ===
CONF_FILE="/etc/config/bot.conf"
SENDER_SCRIPT="/usr/lib/matrix/matrix_send"

# === OPERATING MODES ===
DEBUG_MODE=0
RUN_MODE="auto"

# Default allowed services (fallback if SVC_WANTED is missing in config)
DEFAULT_SERVICES="dnsmasq firewall network odhcpd cron uhttpd"

MAIN_PID=""

# === CLEANUP ON EXIT ===
cleanup() {
    trap - INT TERM EXIT
    printf '\nStopping Matrix Bot...\n'

    # Remove temp files created during runtime
    rm -f /tmp/sync_* /tmp/evt_* /tmp/ssh_evt_* \
          /tmp/enc_check_* /tmp/mhdr_*

    if [ -n "$MAIN_PID" ]; then
        kill -TERM "$MAIN_PID" 2>/dev/null
        sleep 1
        kill -0 "$MAIN_PID" 2>/dev/null && kill -KILL "$MAIN_PID" 2>/dev/null
    fi

    for p in $(jobs -p); do
        kill -TERM "$p" 2>/dev/null
    done
    sleep 1
    for p in $(jobs -p); do
        kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null
    done

    if [ -n "$SSH_PORT" ]; then
        PIDS_SSH=$(ps | awk -v p="$SSH_PORT" '/ssh/ && $0 ~ p && !/awk/ {print $1}')
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
        sleep 1
        for pid in $PIDS_SSH; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done
    fi

    PIDS_CURL=$(ps | awk '/curl/ && /_matrix/ && !/awk/ {print $1}')
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -TERM "$pid" 2>/dev/null; done
    sleep 1
    for pid in $PIDS_CURL; do [ "$pid" != "$$" ] && kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null; done

    exit 0
}
trap cleanup INT TERM EXIT

while [ $# -gt 0 ]; do
    case "$1" in
        -d) DEBUG_MODE=1; printf "DEBUG ON\n" ;;
        --no-e2ee) RUN_MODE="http"; printf "MODE: HTTP ONLY\n" ;;
        --e2ee) RUN_MODE="e2ee"; printf "MODE: SSH ONLY\n" ;;
    esac
    shift
done

debug_log() { [ "$DEBUG_MODE" -eq 1 ] && printf "[DEBUG] %s\n" "$1"; }

if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE" || { printf "Error: Failed to source config file\n" >&2; exit 1; }

    if [ -z "$MATRIX_URL" ] || [ -z "$MATRIX_ACCESS_TOKEN" ] || [ -z "$MATRIX_BOT_USER" ]; then
        printf "Error: Required Matrix configuration missing\n" >&2
        exit 1
    fi
else
    printf "Config not found\n" >&2
    exit 1
fi
