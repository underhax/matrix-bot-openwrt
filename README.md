# Matrix Bot for OpenWrt
[![ShellCheck Lint](https://github.com/underhax/matrix-bot-openwrt/actions/workflows/ci.yml/badge.svg)](https://github.com/underhax/matrix-bot-openwrt/actions/workflows/ci.yml)
[![GitHub last commit](https://img.shields.io/github/last-commit/underhax/matrix-bot-openwrt)](https://github.com/underhax/matrix-bot-openwrt/commits/main)
[![GitHub issues](https://img.shields.io/github/issues/underhax/matrix-bot-openwrt)](https://github.com/underhax/matrix-bot-openwrt/issues)
[![GitHub repo size](https://img.shields.io/github/repo-size/underhax/matrix-bot-openwrt)](https://github.com/underhax/matrix-bot-openwrt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight, native **Lua 5.1** bot for remote router management over the [Matrix protocol](https://matrix.org/). Designed specifically for OpenWrt, providing a secure, efficient, and memory-safe way to control your router from any Matrix client.

**Key Features:**
- **Native OpenWrt Integration**: Built on robust OpenWrt C-bindings (`ubus`, `uci`, `iwinfo`, `cjson`, etc.) for minimal CPU footprint, zero-allocation performance, and deep system interaction.
- **Web UI Configuration**: Fully integrated with OpenWrt's **LuCI** web interface. Configure tokens, rooms, and services directly from your browser.
- **Remote Control**: Monitor system metrics (uptime, RAM) and public WAN IP. Manage services (restart/reload), network interfaces (up/down), Wi-Fi radios (toggle/reload), Wake-on-LAN (WOL), and view detailed network clients (DHCP, ARP, IPv6, Wi-Fi) directly from chat.
- **Dual Transport Architecture**: Choose between a high-security E2EE version (via SSH) or a lightweight HTTP-only version.
- **Standalone Sender**: The CLI notification script (`matrix_send`) can be used independently in your crontabs or custom scripts to push alerts to Matrix (with auto-fallback from E2EE to HTTP).
- **Security-First**: Unauthorized access attempts trigger instant security alerts to a dedicated Admin Room. Managed natively by `procd`.

**Compatibility:** Successfully tested on OpenWrt 25.12.4 using **Xiaomi Mi Router 3G** (and expected to work seamlessly on all newer 25.x releases).

---

## Matrix Setup

### 1. Register a bot account
Register a dedicated Matrix account for the bot on your homeserver (e.g. `@matrixbot:your-matrix-domain.tld`). Do **not** use your personal account.

### Obtaining an Access Token

If you don't have an access token for your bot account, you can generate one using `curl` or `wget` from any terminal.

> [!TIP]
> Unsure about your Matrix API URL?
> <br />Replace `your-matrix-domain.tld` with the domain from your `@matrixbot:your-matrix-domain.tld` ID.
> <br />Open `https://your-matrix-domain.tld/.well-known/matrix/client` in a browser and copy the `base_url`.

Set your credentials as environment variables *(remember to replace the placeholders with your actual values)*:

```sh
MATRIX_URL='https://synapse.your-matrix-domain.tld'
BOT_USER='@matrixbot:your-matrix-domain.tld'
BOT_PASS='Ch4nge-Th1s_BotPa$sw0rd!'
```

Then run one of the following commands:

**Using curl:**
```sh
curl -s -X POST "${MATRIX_URL}/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"m.login.password\",\"user\":\"${BOT_USER}\",\"password\":\"${BOT_PASS}\"}"
```

**Or using wget:**
```sh
wget -q -O - --header="Content-Type: application/json" \
  --post-data="{\"type\":\"m.login.password\",\"user\":\"${BOT_USER}\",\"password\":\"${BOT_PASS}\"}" \
  "${MATRIX_URL}/_matrix/client/v3/login"
```
Copy the `access_token` field from the response. It usually starts with `syt_` or `mct_`.

> [!NOTE]
> **E2EE Method:** If you are using [`matrix-cli`](https://github.com/underhax/matrix-cli#usage), you can also find the `access_token` in your `session.json` file on the external host.

### 3. Create rooms
Create (or reuse) the following rooms in your Matrix client:

| Room | Purpose | Variable |
|---|---|---|
| **Command rooms** | Where you send commands to the bot. Can be E2EE-encrypted or plaintext. | `rooms` |
| **Admin Alert room** | Where the bot sends security alerts (unauthorized access). Does **not** accept commands. | `admin_room` |

Invite the bot account to all rooms. Get room IDs from your client (usually under Room Settings → Advanced) — they look like `!AbCdEfGhIj:matrix-example.tld` or the newer domain-less format `!0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs`.

---

## Installation

The easiest way to install the bot is by adding our custom APK repository. This allows for seamless installations and future updates via the standard OpenWrt package manager.

### Option 1: Custom APK Repository (Recommended)

#### For Active Routers (Running System)
Execute these commands sequentially via SSH on your OpenWrt router:

1. **Download and install the public key:**
   ```sh
   wget -O /etc/apk/keys/underhax-owrt.rsa.pub https://underhax.github.io/matrix-bot-openwrt/underhax-owrt.rsa.pub
   ```
2. **Add the repository to custom feeds:**
   ```sh
   echo 'https://underhax.github.io/matrix-bot-openwrt/packages/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
   ```
3. **Update the package index and install:**
   ```sh
   apk update && apk add matrixbot luci-app-matrixbot
   ```

#### For OpenWrt Image Builder
Run these commands sequentially in your Image Builder root directory:

1. **Download the public key:**
   ```sh
   wget -O keys/underhax-owrt.rsa.pub https://underhax.github.io/matrix-bot-openwrt/underhax-owrt.rsa.pub
   ```
2. **Remove existing entry to avoid duplicates (optional):**
   ```sh
   sed -i '/underhax.github.io\/matrix-bot-openwrt/d' repositories
   ```
3. **Add the repository:**
   ```sh
   echo 'https://underhax.github.io/matrix-bot-openwrt/packages/packages.adb' >> repositories
   ```

### Option 2: Direct Package Install (Manual)

<details>
<summary>Click here to view manual installation instructions</summary>

To install the packages manually, you need to download them into your router's `/tmp` directory.

**Using curl:**
```sh
cd /tmp && \
TAG=$(curl -sSL "https://api.github.com/repos/underhax/matrix-bot-openwrt/releases/latest" | grep '"tag_name":' | head -n 1 | awk -F'"' '{print $4}') && \
curl -sSL -O "https://github.com/underhax/matrix-bot-openwrt/releases/download/${TAG}/matrixbot-${TAG#v}-r1.apk" && \
curl -sSL -O "https://github.com/underhax/matrix-bot-openwrt/releases/download/${TAG}/luci-app-matrixbot-${TAG#v}-r1.apk"
```

**Or using wget:**
```sh
cd /tmp && \
TAG=$(wget -qO- "https://api.github.com/repos/underhax/matrix-bot-openwrt/releases/latest" | grep '"tag_name":' | head -n 1 | awk -F'"' '{print $4}') && \
wget -q "https://github.com/underhax/matrix-bot-openwrt/releases/download/${TAG}/matrixbot-${TAG#v}-r1.apk" && \
wget -q "https://github.com/underhax/matrix-bot-openwrt/releases/download/${TAG}/luci-app-matrixbot-${TAG#v}-r1.apk"
```

**Method B: Manual Download & SCP**
1. Download the latest release packages (`matrixbot-*.apk` and `luci-app-matrixbot-*.apk`) to your computer from the [Releases page](https://github.com/underhax/matrix-bot-openwrt/releases).
2. Transfer them to your router (e.g. via `scp` into `/tmp/`).

#### Step 2: Install via SSH

Once the files are in `/tmp`, connect to your router via SSH (if you haven't already) and run the following to install and clean up:
```sh
apk update && \
cd /tmp && \
apk add --allow-untrusted matrixbot-*.apk luci-app-matrixbot-*.apk && \
rm -f matrixbot-*.apk luci-app-matrixbot-*.apk
```
</details>

### Option 3: Build from Source & Manual Testing
If you are a developer or want to test the latest `main` branch, refer to our detailed [**Manual Testing Guide**](MANUAL_TESTING.md).

---

## Configuration

The recommended way to configure the bot is through the OpenWrt Web GUI.

1. Open your router's LuCI web interface in your browser. *(Note: If the menu doesn't appear immediately after installation, log out and log back in to clear the LuCI cache).*
2. Navigate to **Services → Matrix Bot**.
3. Fill in your Matrix URL, Access Token, Bot User, Admin User, and Room IDs. *(See [Obtaining an Access Token](#obtaining-an-access-token) if you are unsure about your Matrix URL).*
4. If using **E2EE**, enable it and provide your SSH credentials.
5. Configure optional features such as **Allowed Services** (for the `restart` command), **WOL PC MAC**, **WOL Interfaces**, and Wi-Fi preferences (**Detailed WiFi Output** and **Show WiFi Key**).
6. Click **Save & Apply**. The `procd` daemon will automatically reload the bot with the new settings.

*Alternatively, you can edit `/etc/config/matrixbot` manually via SSH and run `service matrixbot reload`.*

---

## Transport Methods

### Method A: E2EE (Maximum Security)
Recommended for privacy. Uses End-to-End Encryption (E2EE) via an SSH tunnel to an external host running [`matrix-cli`](https://github.com/underhax/matrix-cli).
- **External Host**: A VPS, Raspberry Pi, or Docker container running `matrix-cli` logged into the bot account.
- **Key Setup**: Generate an SSH key on your router (`ssh-keygen -t ed25519 -f /root/.ssh/router-matrix`) and add the public key to your external host.
- **Verification**: After configuring the bot in LuCI, you must save the remote host's signature securely before enabling the service:
  ```sh
  ssh -i "$(uci -q get matrixbot.e2ee.ssh_key)" -p "$(uci -q get matrixbot.e2ee.ssh_port)" \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      "$(uci -q get matrixbot.e2ee.ssh_user)@$(uci -q get matrixbot.e2ee.ssh_host)" exit 2>&1 && \
  printf "Host key saved.\n" && chmod 600 /etc/matrix_bot_known_hosts
  ```

### Method B: HTTP (Simple)
Communicates directly with the Matrix API. Best for unencrypted rooms or when you cannot maintain an external host.
- No external host required.
- The Matrix access token is passed securely in memory to native transports, preventing credential leaks in process lists.

---

## Usage & Commands

Once the bot is running and invited to your rooms, send commands as the **Admin User** in the command room.

Send `help` or `start` to get the full command list from the bot itself.

### Command Reference

| Command | Description |
|---|---|
| &nbsp; | &nbsp; |
| **SYSTEM** | |
| `uptime` | Router uptime and load average |
| `memory` | RAM usage in MB (total / used / free) |
| `meminfo` | Detailed `/proc/meminfo` |
| `wan_ip` | Public WAN IP address (multi-fallback resolution) |
| &nbsp; | &nbsp; |
| **NETWORK** | |
| `clients` | Full network report: Wi-Fi + wired clients |
| `wifi_clients` | Wi-Fi associated clients |
| `wired_clients` | Wired LAN clients |
| &nbsp; | &nbsp; |
| **SERVICES** | |
| `restart <service>` | Restart a whitelisted service (e.g. `restart dnsmasq`) |
| `reload nginx` | Test Nginx config, then reload if valid |
| &nbsp; | &nbsp; |
| **INTERFACES** | |
| `ifup <iface>` | Bring up a UCI interface (e.g. `ifup wan`) |
| `ifdown <iface>` | Bring down a UCI interface |
| &nbsp; | &nbsp; |
| **WI-FI** | |
| `wifi` / `wifi_info` | Wi-Fi information |
| `wifi_up_2_4` / `wifi_down_2_4` | Enable/Disable 2.4 GHz radio (radio0) |
| `wifi_up_5` / `wifi_down_5` | Enable/Disable 5 GHz radio (radio1) |
| `wifi_reload_2_4` / `wifi_reload_5` | Reload 2.4 GHz or 5 GHz radio |
| &nbsp; | &nbsp; |
| **WOL** | |
| `wol <MAC>` | Send WOL magic packet to any MAC (format: `AA:BB:CC:DD:EE:FF`) |
| `wol_pc` | Send WOL magic packet to pre-configured PC |

---

## Standalone Sender

The CLI script can be used independently for your own system alerts or crontab notifications.

**Auto-Fallback (E2EE → HTTP):**
```sh
/usr/bin/matrix_send --room-id '!RoomID:server.tld' 'Alert: WAN link is down!'
```
*Note: You can force a transport by passing `--ssh-only` or `--http-only`.*

**Example:** OpenWrt Hotplug Script (`/etc/hotplug.d/iface/97-get_ip`)
```sh
#!/bin/sh
# Send a Matrix notification when the WAN interface comes up
# ipv4=$(ifstatus wan | jsonfilter -e '@["ipv4-address"][0].address')

[ "$ACTION" = "ifup" -a "$INTERFACE" = "wan" ] && {
    (
        sleep 30
        ipv4=$(curl --interface "$INTERFACE" -s 4.ipquail.com/ip)
        /usr/bin/matrix_send "<b>WAN is UP</b> <br>IPv4: <code>$ipv4</code>"
    ) &
}
exit 0
```

---

## Security Model
- **Process Isolation**: Native Lua modules are loaded dynamically. No slow shell `fork()` calls.
- **Single admin**: only `Admin User` can issue commands. Any other sender triggers an immediate alert to the `Admin Alert Room`.
- **Strict Validation**: Service names, network interface names, MAC addresses, IP addresses, domains, ports, Matrix User IDs, tokens, and Room IDs are all validated against strict Lua patterns before execution, entirely preventing command injection.
- **SSH Verification**: SSH Verification: Enforces StrictHostKeyChecking=yes with a dedicated known_hosts file. Strict owner/mode checks (chmod 600/400) on SSH keys prevent MITM attacks.

---

## Troubleshooting
- **Logs**: View real-time activity via OpenWrt's system log: `logread -e matrixbot -f`.
- **Debug Mode**: Enable "Debug Logging" in LuCI (or set `option debug '1'` in `/etc/config/matrixbot`) to see verbose HTTP payloads, JSON parsing errors, and UBUS debugging output.
- **E2EE Checks**: If E2EE fails, manually verify SSH connectivity from the router to your `matrix-cli` host using the key defined in LuCI.
