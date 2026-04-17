# Matrix Bot for OpenWrt
[![ShellCheck Lint](https://github.com/underhax/matrix-bot-openwrt/actions/workflows/ci.yml/badge.svg)](https://github.com/underhax/matrix-bot-openwrt/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, POSIX shell–based Matrix bot for remote router management over the [Matrix protocol](https://matrix.org/). Designed for OpenWrt, providing a secure and efficient way to control your router from any Matrix client.

**Features:**
- Remote control via Matrix chat: services, interfaces, Wi-Fi, WOL, clients, system info
- **Two build variants**: Choose between a high-security E2EE version (via SSH) or a lightweight HTTP-only version.
- **Standalone Sender**: The notification scripts (`matrix_send` or `matrix_send_http`) can be used independently from the bot for any system alerts.

- Security alerts forwarded to a dedicated admin room on unauthorized access attempts.
- Managed by `procd` — automatic restart on crash, logs via `logread`.

**Compatibility:** Successfully tested on OpenWrt 25.12.0 (Xiaomi Mi Router 3G).

---

## Matrix Setup

### 1. Register a bot account

Register a dedicated Matrix account for the bot on your homeserver (e.g. `@mybot:matrix-example.tld`). Do **not** use your personal account.

### 2. Get an access token

Log in to the bot account and retrieve its access token:

```sh
# Using curl:
curl -s -X POST "https://matrix-example.tld/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"mybot","password":"yourpassword"}'

# Or using wget:
wget -q -O - --header="Content-Type: application/json" \
  --post-data='{"type":"m.login.password","user":"mybot","password":"yourpassword"}' \
  "https://matrix-example.tld/_matrix/client/v3/login"
```

Copy the `access_token` field from the response.

**E2EE Method Note:** If you are using `matrix-commander-rs`, you can also find the token in your `credentials.json` file on the external host.

### 3. Create rooms

Create (or reuse) the following rooms in your Matrix client:

| Room | Purpose | Variable |
|---|---|---|
| **Command rooms** | Where you send commands to the bot. Can be E2EE-encrypted or plaintext. One or more. | `MATRIX_ROOM_IDS` |
| **Admin/alert room** | Where the bot sends security alerts (unauthorized access). Does **not** accept commands. | `MATRIX_ROOM_ADMIN` |

Invite the bot account to all rooms. Get room IDs from your client (usually under Room Settings → Advanced) — they look like `!AbCdEfGhIj:matrix-example.tld` or `!0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs`.

---

## Choose Your Installation Method

Select the method that best fits your security requirements and infrastructure.

<details>
<summary><b>Method A: E2EE (Secure) - [Click to expand]</b></summary>

### Overview
Recommended for maximum privacy. Uses End-to-End Encryption (E2EE) via an SSH tunnel to an external host running [`matrix-commander-rs`](https://github.com/8go/matrix-commander-rs).

### Architecture (E2EE)

```
OpenWrt Router
│
├── /etc/config/bot.conf          ← credentials & settings
├── /etc/init.d/matrixbot         ← service control (start/stop/enable)
├── /etc/matrix_bot_known_hosts   ← SSH host key store (created during setup)
│
└── /usr/lib/matrix/
    ├── matrix_bot                ← E2EE listener & command handler
    └── matrix_send               ← universal message sender (SSH first)
```

### 1. Requirements
**On the Router:**

```sh
apk update && apk add curl jq openssh-client
```

| Package | Purpose |
|---|---|
| `curl` | **(Preferred)** Robust HTTP transport for credential passing (fallback: built-in `wget`). |
| `jq` | **(Preferred)** Reliable JSON parsing (fallback: built-in `jsonfilter`). |
| `openssh-client` | **Required** for the SSH tunnel. SSH transport to the E2EE host running `matrix-commander-rs` |

> `wget` and `jsonfilter` are included in OpenWrt by default and are used automatically if `curl` or `jq` is not installed. `curl` and `jq` are strongly recommended for correctness and security.

For Wake-on-LAN support:

```sh
apk add etherwake
```

For Nginx reload support — Nginx must already be installed:

```sh
apk add nginx
```

**External Host:**
- Any external host (VPS, Raspberry Pi, Home Server, and similar).
- [`matrix-commander-rs`](https://github.com/8go/matrix-commander-rs) installed and **already logged in** to your **bot Matrix account**.
- A dedicated SSH key pair for the bot (see **SSH Key Setup** bellow)
- **Recommended Setup**: Use the [**matrix-commander-rs-gateway**](https://github.com/underhax/matrix-commander-rs-gateway) Docker container.

### 2. Installation

```sh
mkdir -p /usr/lib/matrix
# Download Bot, Universal Sender, and Init script
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/usr/lib/matrix/matrix_bot" -o /usr/lib/matrix/matrix_bot
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/usr/lib/matrix/matrix_send" -o /usr/lib/matrix/matrix_send
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/etc/init.d/matrixbot" -o /etc/init.d/matrixbot

# Set permissions
chmod 500 /usr/lib/matrix/matrix_*
chmod 500 /etc/init.d/matrixbot
```

### 3. SSH Key Setup
Generate a dedicated key pair on the router:

```sh
mkdir -p /root/.ssh
ssh-keygen -t ed25519 -f /root/.ssh/router-matrix -N "" -C "matrix-bot@openwrt"
chmod 400 /root/.ssh/router-matrix
cat /root/.ssh/router-matrix.pub
```

Copy the public key to the external host (`~/.ssh/authorized_keys`).

Register the remote host key (run once — uses your config values):

```sh
. /etc/config/bot.conf && \
ssh -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$SSH_USER@$SSH_HOST" exit 2>&1 && \
echo "Host key saved." && cat /etc/matrix_bot_known_hosts
```

This stores the host key in `/etc/matrix_bot_known_hosts`. The bot uses `StrictHostKeyChecking=yes` against this file — MITM attacks will be rejected.

### 4. Finalize
Edit `/etc/config/bot.conf` — see [Configuration](#configuration) below.

Enable and start the service:

```sh
/etc/init.d/matrixbot enable
/etc/init.d/matrixbot start
```
</details>

<details>
<summary><b>Method B: HTTP (Simple) - [Click to expand]</b></summary>

### Overview
Designed for simplicity. Communicates directly with the Matrix API. Best for unencrypted rooms, quick setups, or when you cannot maintain an external host. Similar to a Telegram bot experience.

### Architecture (HTTP)
```
OpenWrt Router
│
├── /etc/config/bot.conf          ← credentials & settings
├── /etc/init.d/matrixbot_http    ← service control
│
└── /usr/lib/matrix/
    ├── matrix_bot_http           ← HTTP polling listener & handler
    └── matrix_send_http          ← message sender (direct HTTP)
```

### 1. Requirements
**On the Router:**
```sh
apk update && apk add curl jq
```

| Package | Purpose |
|---|---|
| `curl` | **(Preferred)** Robust HTTP transport for credential passing (fallback: built-in `wget`). |
| `jq` | **(Preferred)** Reliable JSON parsing (fallback: built-in `jsonfilter`). |

> `wget` and `jsonfilter` are included in OpenWrt by default and are used automatically if `curl` or `jq` is not installed. `curl` and `jq` are strongly recommended for correctness and security.

For Wake-on-LAN support:

```sh
apk add etherwake
```

For Nginx reload support — Nginx must already be installed:

```sh
apk add nginx
```

### 2. Installation
```sh
mkdir -p /usr/lib/matrix
# Download HTTP Bot, Pure HTTP Sender, and Init script
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/usr/lib/matrix/matrix_bot_http" -o /usr/lib/matrix/matrix_bot_http
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/usr/lib/matrix/matrix_send_http" -o /usr/lib/matrix/matrix_send_http
curl -sSL "https://raw.githubusercontent.com/underhax/matrix-bot-openwrt/refs/tags/v1.0.0/etc/init.d/matrixbot_http" -o /etc/init.d/matrixbot_http

# Set permissions
chmod 500 /usr/lib/matrix/matrix_*
chmod 500 /etc/init.d/matrixbot_http
```

### 3. Finalize
Edit `/etc/config/bot.conf` — see [Configuration](#configuration) below.

Enable and start the service:

```sh
/etc/init.d/matrixbot_http enable
/etc/init.d/matrixbot_http start
```
</details>

---

## Configuration

All settings live in `/etc/config/bot.conf`. Create it and set strictly root-only permissions:
```sh
touch /etc/config/bot.conf
chmod 400 /etc/config/bot.conf
```

### Configuration Template
```sh
# /etc/config/bot.conf
# Permissions must be 400 (chmod 400 /etc/config/bot.conf)

# =====================
# Matrix (Required for both)
# =====================

# Base URL of your Matrix homeserver (no trailing slash)
MATRIX_URL='https://matrix-example.tld'

# Space-separated list of room IDs where the bot accepts commands.
MATRIX_ROOM_IDS='!AbCdEfGhIj:matrix-example.tld !0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs'

# Admin/alert room: bot sends security warnings here. NOT a command room.
MATRIX_ROOM_ADMIN='!UvWxYzAbCd:matrix-example.tld'

# Full Matrix user ID of the bot account (must be invited to all rooms above)
MATRIX_BOT_USER='@mybot:matrix-example.tld'
# Full Matrix user ID of the admin (the only user whose commands are accepted)
MATRIX_ADMIN_USER='@me:matrix-example.com'

# Access token (from login response or from matrix-commander-rs credentials.json)
MATRIX_ACCESS_TOKEN='syt_XXXXXXXXXXXXXXXXXXXXXXXX'

# =====================
# SSH (Required for E2EE Method)
# =====================

# Hostname or IP of the machine running matrix-commander-rs
SSH_HOST='192.168.1.100'
SSH_PORT='22'
SSH_USER='myuser'
# Path to the private key generated during setup
SSH_KEY='/root/.ssh/router-matrix'

# =====================
# Wi-Fi display
# =====================

# Set to 1 for detailed Wi-Fi info (hardware, BSSID, signal, TX power, etc.)
# Set to 0 or leave empty for simple mode (SSID, channel, rate, key)
WIFI_DETAILED=0

# Set to 1 to reveal Wi-Fi passwords in plaintext in chat outputs.
# Set to 0 or leave empty to mask passwords (e.g. ********) for security.
WIFI_SHOW_KEY=0

# =====================
# Service control
# =====================

# Space-separated whitelist of services allowed to be restarted via 'restart' command.
# Only services in this list AND present in /etc/init.d/ can be restarted.
# Default (used if this variable is absent): dnsmasq firewall network odhcpd cron uhttpd
SVC_WANTED='dnsmasq firewall network odhcpd cron uhttpd nginx'

# =====================
# Wake-on-LAN
# =====================

# Optional: List of interfaces for WOL broadcasting (defaults to br-lan if empty)
# WOL_INTERFACES="br-lan br-guest"

# MAC address of a specific machine to wake with the 'wol_pc' command (optional)
MAC_PC='AA:BB:CC:DD:EE:FF'
```

---

## Usage

Once the bot is running and invited to your rooms, send commands as `MATRIX_ADMIN_USER` in the command room.

### Quick start
Send `help` or `start` to get the full command list from the bot itself.

### Command reference

#### System info
| Command | Description |
|---|---|
| `uptime` | Router uptime and load average |
| `memory` | RAM usage in MB (total / used / free) |
| `meminfo` | Detailed `/proc/meminfo` (first 5 entries) |
| `wan_ip` | Public WAN IP address (queries external services with local fallback) |

#### Network clients
| Command | Description |
|---|---|
| `clients` | Full network report: all Wi-Fi + wired clients |
| `wifi_clients` | Wi-Fi associated clients (IP, IPv6, MAC, signal, hostname) |
| `wired_clients` | Wired LAN clients from ARP table (excluding Wi-Fi MACs) |

#### Service management
| Command | Description |
|---|---|
| `restart <service>` | Restart a service from the whitelist (e.g. `restart dnsmasq`) |
| `reload nginx` | Test Nginx config, then reload if valid |

#### Network interfaces
| Command | Description |
|---|---|
| `ifup <iface>` | Bring up a UCI-defined network interface (e.g. `ifup wan`) |
| `ifdown <iface>` | Bring down a UCI-defined network interface |

#### Wi-Fi control
| Command | Description |
|---|---|
| `wifi` / `wifi_info` | Wi-Fi status (SSID, encryption, channel, rate, key) |
| `wifi_up_2_4` / `wifi_down_2_4` | Enable/Disable 2.4 GHz radio (radio0) |
| `wifi_up_5` / `wifi_down_5` | Enable/Disable 5 GHz radio (radio1) |
| `wifi_reload_2_4` / `wifi_reload_5` | Reload radio configuration |

#### Wake-on-LAN
| Command | Description |
|---|---|
| `wol <MAC>` | Send WOL magic packet to any MAC (format: `AA:BB:CC:DD:EE:FF`) |
| `wol_pc` | Send WOL magic packet to `MAC_PC` from config |

---

## Standalone Usage
The sending scripts can be used independently for your own system alerts or crontab notifications.

**Universal Sender (`matrix_send`):**
Tries SSH (E2EE) first, falls back to HTTP if the tunnel is down.
```sh
/usr/lib/matrix/matrix_send --room-id '!RoomID:server.tld' 'Alert: WAN link is down!'
```

**Pure HTTP Sender (`matrix_send_http`):**
Direct HTTP only, no SSH overhead.
```sh
/usr/lib/matrix/matrix_send_http --room-id '!RoomID:server.tld' 'Backup successful.'
```

---

## Security Model
- **Process Isolation**: You only run the code necessary for your chosen transport. E2EE build physically lacks HTTP polling logic.
- **Single admin**: only `MATRIX_ADMIN_USER` can issue commands. Any other sender triggers an alert to `MATRIX_ROOM_ADMIN`.
- **Room whitelist**: events from any room not listed in `MATRIX_ROOM_IDS` are silently dropped.
- **Service whitelist**: only services in `SVC_WANTED` can be restarted. Service names are validated against `[a-zA-Z0-9_-]` before use.
- **Input sanitization**: all command arguments are strictly filtered using native shell whitelisting to block shell metacharacters and injection attempts.
- **SSH host verification**: `StrictHostKeyChecking=yes` with a dedicated `known_hosts` file.
- **Credential Protection**: When using HTTP transport (directly or as fallback), the Matrix access token is passed via secure `chmod 400` memory files to `curl -K` rather than on the command line.

---

## File Permissions Summary
| Path | Owner | Mode | Notes |
|---|---|---|---|
| `/usr/lib/matrix/matrix_bot*` | root | `500` | Bot executables |
| `/usr/lib/matrix/matrix_send*` | root | `500` | Message senders |
| `/etc/init.d/matrixbot*` | root | `500` | procd init scripts |
| `/etc/config/bot.conf` | root | `400` | Credentials — strictly root-only |
| `/root/.ssh/router-matrix` | root | `400` | SSH private key |
| `/etc/matrix_bot_known_hosts` | root | `600` | SSH host key store |

---

## Troubleshooting
- **Logs**: Use `logread -f -e matrix` to view real-time activity.
- **Debug**: Run the bot script with the `-d` flag (e.g., `/usr/lib/matrix/matrix_bot -d`).
- **E2EE**: Verify SSH connectivity manually before starting the service.
- **HTTP**: Ensure `curl` (or `wget`) is working and the access token is valid.
