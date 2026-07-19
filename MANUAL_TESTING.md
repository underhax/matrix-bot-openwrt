# Manual Testing & Development Guide

This guide provides step-by-step instructions for developers and power users who want to safely install, test, and develop the Lua Matrix Bot on an OpenWrt router from source, bypassing the standard `.apk` package installation.

## 1. Stop the Old Service (If Applicable)
If you are migrating from the old Bash version, stop the old bot to prevent conflicts on the Matrix room side:
```sh
service matrixbot stop
```
*Optional:* Rename the old daemon script if you wish to keep it safely out of the way:
```sh
mv /etc/init.d/matrixbot /etc/init.d/matrixbot_old
```

## 2. Install Native Dependencies
Since you are transferring files manually and not using a compiled `.apk` package (which resolves dependencies automatically), you must install them directly on the router. OpenWrt 25.12 uses `apk`:
```sh
apk update
apk add libubox-lua libubus-lua libiwinfo-lua luci-lib-nixio luasec libuci-lua lua-cjson
```

*(Note: Older OpenWrt versions may use `opkg` instead of `apk`).*

## 3. Transfer Files to the Router
You can transfer the repository files using `scp` or `rsync`. Since this is a pure Lua project, no C-compilation is needed.

1. Copy the `usr` and `etc` folders (located inside `packages/matrixbot/src/`) to the root of the router (`/`).
2. Copy the `controller` and `model` folders (located inside `packages/luci-app-matrixbot/luasrc/`) to `/usr/lib/lua/luci/`.

## 4. Set Proper Permissions
Permissions must be strictly locked down to ensure security on the router.

```sh
# 1. Daemon and Executables (chmod 700)
# Restricts execution strictly to the root owner.
chmod 700 /etc/init.d/matrixbot
chmod 700 /usr/bin/matrix_send
chmod 700 /usr/lib/lua/matrixbot/main.lua

# 2. Lua Modules (chmod 644)
# Internal modules only need read permissions.
chmod 644 /usr/lib/lua/matrixbot/*.lua
chmod 644 /usr/lib/lua/matrixbot/*/*.lua

# 3. Configuration File (Secrets)
# Must be strictly 600 to prevent any non-root users from reading the token.
chmod 600 /etc/config/matrixbot

# 4. LuCI Web UI Files
# Standard permissions are sufficient, as these are executed internally by the uhttpd server.
chmod 644 /usr/lib/lua/luci/controller/matrixbot.lua
chmod 644 /usr/lib/lua/luci/model/cbi/matrixbot.lua
```

## 5. Configuration
You can configure the bot in two ways:
- **Web UI:** Navigate to your OpenWrt router's admin panel (**Services -> Matrix Bot**) and enter your tokens and settings.
- **CLI:** Manually edit the `/etc/config/matrixbot` file via SSH.

## 6. E2EE Host Verification (Optional)
If you are using the End-to-End Encryption (E2EE) method via SSH to `matrix-cli`, you must register the remote host key securely.
Run the following command from the router to save the signature to your `known_hosts` file (it will automatically use the credentials you just configured):

```sh
ssh -i "$(uci -q get matrixbot.e2ee.ssh_key)" -p "$(uci -q get matrixbot.e2ee.ssh_port)" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/etc/matrix_bot_known_hosts \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$(uci -q get matrixbot.e2ee.ssh_user)@$(uci -q get matrixbot.e2ee.ssh_host)" exit 2>&1 && \
printf "Host key saved.\n" && chmod 600 /etc/matrix_bot_known_hosts
```

## 7. Real-time Debugging (Recommended)
Before starting the bot, it is highly recommended to open a **second terminal window (SSH session)** to your router and run the system log reader in follow mode. This allows you to observe the entire startup sequence and immediately catch any configuration errors:
```sh
logread -e matrixbot -f
```
**Tip:** Enable the `Debug Logging` checkbox in the LuCI configuration (or `option debug '1'` in `/etc/config/matrixbot`) to see detailed HTTP payloads, JSON parsing errors, and UBUS debugging output.

## 8. Start/Stop the Service
Now, in your primary terminal window, you can start the service and verify it is running:
```sh
service matrixbot enable
service matrixbot stop && ps | grep matrix | grep -v logread | grep -v grep
service matrixbot start && sleep 1 && ps | grep matrix | grep -v logread | grep -v grep
```

If you skipped step 7, you can manually check the recent logs to verify the bot started successfully:
```sh
logread -e matrixbot
```

## 9. Testing the Standalone CLI Sender
To test the standalone notification script:
```sh
/usr/bin/matrix_send [--ssh-only|--http-only] [--room-id '!room_id[:server]'] [--] 'Message text'
```
