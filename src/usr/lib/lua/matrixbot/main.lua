local nixio = require("nixio")
local ubus = require("ubus")
local uloop = require("uloop")
local config = require("matrixbot.config")
local logger = require("matrixbot.utils.logger")
local security = require("matrixbot.utils.security")

local sysinfo = require("matrixbot.command.sysinfo")
local network = require("matrixbot.command.network")
local service = require("matrixbot.command.service")
local wifi = require("matrixbot.command.wifi")
local wol = require("matrixbot.command.wol")

local function sanitize(str)
    if not str then
        return ""
    end
    return str:gsub("[^%w%s%.:_%-]", "")
end

local function html_escape(str)
    if not str then
        return ""
    end
    return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function handle_command(cfg, transport, room_id, sender, body, event_type)
    logger.debug(string.format("CMD: %s | Room: %s", tostring(body or ""), room_id))

    local is_http_encrypted = not cfg.e2ee.enabled and event_type == "m.room.encrypted"
    if not security.authorize_sender(cfg, transport, room_id, sender, body, is_http_encrypted) then
        return
    end

    if is_http_encrypted then
        logger.debug("Encrypted message from Admin in HTTP mode. Room: " .. tostring(room_id))
        transport.send_message(cfg, room_id, "⛔ In HTTP mode, I cannot process messages in this encrypted room.")
        return
    end

    if not body or body == "" then
        return
    end

    if cfg.e2ee.enabled and cfg.rooms_encryption and not cfg.rooms_encryption[room_id] then
        logger.debug("PLAINTEXT command in E2EE mode. Room: " .. tostring(room_id))
        transport.send_message(
            cfg,
            room_id,
            "⚠️ <b>Warning:</b> The bot is in strict E2EE mode. Please enable encryption for this room."
        )
    end

    local cmd, args = body:match("^(%S+)%s*(.*)$")
    if not cmd then
        cmd = body
        args = ""
    end
    cmd = sanitize(cmd)
    local safe_args = sanitize(args)

    local res

    if cmd == "help" or cmd == "start" then
        local svc_list = service.get_services_list(cfg)

        local nginx_help = ""
        if service.is_service_allowed("nginx", cfg) and service.service_exists("nginx") then
            nginx_help = "reload nginx<br>\n"
        end

        local wol_pc_help = ""
        if cfg.features.mac_pc and cfg.features.mac_pc ~= "" then
            wol_pc_help = "2. Wake PC<br>\nUsage: wol_pc"
        end

        local function get_iface_list()
            local uci = require("uci")
            local cursor = uci.cursor()
            local ifaces = {}
            cursor:foreach("network", "interface", function(s)
                if s[".name"] ~= "loopback" then
                    table.insert(ifaces, s[".name"])
                end
            end)
            table.sort(ifaces)
            return table.concat(ifaces, ", ")
        end

        res = "🤖 <b>HELP</b><br>\n<br>\n"
            .. "<b>INFO:</b><br>\n1. Router uptime<br>\nUsage: uptime<br>\n"
            .. "2. RAM (MB)<br>\nUsage: memory<br>\n3. Memory Detail (MB)<br>\nUsage: meminfo<br>\n"
            .. "4. IPv4 (WAN)<br>\nUsage: wan_ip<br>\n"
            .. "5. DHCP clients<br>\nUsage: clients / wifi_clients / wired_clients<br>\n<br>\n"
            .. "<b>SERVICES:</b><br>\nAvailable: "
            .. svc_list
            .. "<br>\n"
            .. "Usage: restart [service]<br>\n"
            .. nginx_help
            .. "<br>\n"
            .. "<b>INTERFACES:</b><br>\nAvailable: "
            .. get_iface_list()
            .. "<br>\n"
            .. "Usage: ifup [interface]<br>\nUsage: ifdown [interface]<br>\n<br>\n"
            .. "<b>WIFI:</b><br>\nUsage: wifi_info / wifi_up_2_4 / wifi_down_2_4 / wifi_reload_2_4<br>\n"
            .. "wifi_up_5 / wifi_down_5 / wifi_reload_5<br>\n<br>\n"
            .. "<b>WOL:</b><br>\n1. Wake-on-LAN<br>\nUsage: wol [mac]<br>\n"
            .. wol_pc_help
    elseif cmd == "uptime" or cmd == "memory" or cmd == "meminfo" or cmd == "wan_ip" then
        res = sysinfo.execute(cmd, safe_args, cfg, transport, room_id)
    elseif cmd == "clients" or cmd == "wifi_clients" or cmd == "wired_clients" then
        res = network.execute(cmd, safe_args, cfg)
    elseif cmd == "restart" or cmd == "reload" or cmd == "ifup" or cmd == "ifdown" then
        res = service.execute(cmd, safe_args, cfg, transport, room_id)
    elseif cmd:sub(1, 4) == "wifi" then
        res = wifi.execute(cmd, safe_args, cfg)
    elseif cmd == "wol" or cmd == "wol_pc" then
        res = wol.execute(cmd, safe_args, cfg)
    else
        res = "🤖 Unknown command: <code>" .. html_escape(cmd) .. "</code>.<br>Try <code>help</code>"
    end

    if res and res ~= "" then
        transport.send_message(cfg, room_id, res)
    end
end

local function on_event(cfg, transport, room_id, event)
    local allowed = false
    for _, r in ipairs(cfg.main.rooms) do
        if r == room_id then
            allowed = true
            break
        end
    end

    if not allowed then
        logger.warn("Message from unauthorized room: " .. tostring(room_id))
        return
    end

    local body = event.body
    if not body and event.content then
        body = event.content.body
    end

    local pid = nixio.fork()
    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            local ok, err = pcall(function()
                handle_command(cfg, transport, room_id, event.sender, body, event.type)
            end)
            if not ok then
                logger.error("Command execution crashed: " .. tostring(err))
            end
            os.exit(0)
        else
            os.exit(0)
        end
    elseif pid then
        nixio.waitpid(pid)
    end
end

local function start_poller(cfg, transport)
    local pid = nixio.fork()
    if pid == 0 then
        logger.info("Starting Matrix Poller (PID: " .. tostring(nixio.getpid()) .. ")")

        local ok, err = pcall(function()
            transport.poll(cfg, function(room_id, event)
                on_event(cfg, transport, room_id, event)
            end)
        end)

        if not ok then
            logger.error("Matrix Poller crashed: " .. tostring(err))
        end

        nixio.kill(nixio.getpid(), 9)
    end
    return pid
end

local function init_encryption_cache(cfg)
    logger.info("Initializing: Checking room encryption status via API...")
    local http = require("matrixbot.transport.http")
    cfg.rooms_encryption = {}

    local rooms_to_check = {}
    for _, r in ipairs(cfg.main.rooms) do
        rooms_to_check[r] = true
    end
    if cfg.main.admin_room and cfg.main.admin_room ~= "" then
        rooms_to_check[cfg.main.admin_room] = true
    end

    if cfg.e2ee.enabled then
        local e2ee = require("matrixbot.transport.e2ee")
        local rlist = {}
        for room_id, _ in pairs(rooms_to_check) do
            table.insert(rlist, room_id)
        end
        local result = e2ee.get_rooms_encryption_status(cfg, rlist)
        if result then
            for room_id, _ in pairs(rooms_to_check) do
                local encrypted = result[room_id] or false
                cfg.rooms_encryption[room_id] = encrypted
                if encrypted then
                    logger.info("Room State [" .. room_id .. "]: 🔒 ENCRYPTED (E2EE/SSH)")
                else
                    logger.info("Room State [" .. room_id .. "]: 🔓 PLAINTEXT (E2EE/SSH)")
                end
            end
        else
            logger.warn("Failed to retrieve room encryption status via SSH/matrix-cli")
        end
        return
    end

    for room_id, _ in pairs(rooms_to_check) do
        local enc_room = room_id:gsub("!", "%%21"):gsub(":", "%%3A")
        local endpoint = "/_matrix/client/v3/rooms/" .. enc_room .. "/state/m.room.encryption"
        local res = http.request(cfg, "GET", endpoint, nil, nil, true)

        if res and res.algorithm == "m.megolm.v1.aes-sha2" then
            cfg.rooms_encryption[room_id] = true
            logger.info("Room State [" .. room_id .. "]: 🔒 ENCRYPTED")
        else
            local algo = res and res.algorithm or "none"
            cfg.rooms_encryption[room_id] = false
            logger.info("Room State [" .. room_id .. "]: 🔓 PLAINTEXT (algo: " .. algo .. ")")
        end
    end
end

local function start()
    logger.info("Initializing Matrix Bot")

    local cfg = config.load()
    if not cfg then
        os.exit(1)
    end

    if cfg.main.debug then
        logger.set_level("debug")
        logger.debug("Debug mode enabled")
    end

    local transport
    if cfg.e2ee.enabled then
        transport = require("matrixbot.transport.e2ee")
        logger.info("Transport: E2EE (SSH)")
    else
        transport = require("matrixbot.transport.http")
        logger.info("Transport: HTTP")
    end

    init_encryption_cache(cfg)

    uloop.init()

    local conn = ubus.connect()
    if not conn then
        logger.error("Failed to connect to ubus")
        os.exit(1)
    end

    conn:add({
        matrixbot = {
            send = {
                function(_req, msg)
                    if not msg or not msg.text then
                        return ubus.STATUS_INVALID_ARGUMENT
                    end

                    if msg.room and msg.room ~= "" then
                        if transport.send_message_async(cfg, msg.room, msg.text) then
                            return 0
                        end
                        return ubus.STATUS_UNKNOWN_ERROR
                    end

                    if not cfg.main.rooms or #cfg.main.rooms == 0 then
                        return ubus.STATUS_NOT_FOUND
                    end

                    for _, room_id in ipairs(cfg.main.rooms) do
                        if transport.send_message_async(cfg, room_id, msg.text) then
                            return 0
                        end
                    end

                    return ubus.STATUS_UNKNOWN_ERROR
                end,
                { room = ubus.STRING, text = ubus.STRING },
            },
        },
    })

    local poller_pid = start_poller(cfg, transport)

    local pf = io.open("/var/run/matrixbot_poller.pid", "w")
    if pf then
        pf:write(tostring(poller_pid) .. "\n")
        pf:close()
    end

    local watchdog
    watchdog = uloop.timer(function()
        local wpid, _, code = nixio.waitpid(poller_pid, "nohang")
        if wpid == poller_pid then
            logger.warn("Matrix Poller process died (Code: " .. tostring(code) .. "), restarting...")
            poller_pid = start_poller(cfg, transport)
            local f = io.open("/var/run/matrixbot_poller.pid", "w")
            if f then
                f:write(tostring(poller_pid) .. "\n")
                f:close()
            end
        end
        watchdog:set(5000)
    end)
    watchdog:set(5000)

    logger.info("Main daemon loop started")
    uloop.run()
end

start()
