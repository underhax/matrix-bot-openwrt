local nixio = require("nixio")
local cjson = require("cjson")
local logger = require("matrixbot.utils.logger")

local M = {}

local function shell_quote(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

local function build_ssh_args(cfg, remote_command, tty_mode)
    local args = {
        "ssh",
        "-i",
        cfg.e2ee.ssh_key,
        "-p",
        cfg.e2ee.ssh_port,
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "UserKnownHostsFile=/etc/matrix_bot_known_hosts",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "BatchMode=yes",
    }
    if tty_mode and tty_mode ~= "" then
        table.insert(args, tty_mode)
    end
    table.insert(args, cfg.e2ee.ssh_user .. "@" .. cfg.e2ee.ssh_host)
    table.insert(args, remote_command)
    return args
end

local function build_mc_cmd(base_cmd, cfg)
    if cfg.e2ee.data_dir and cfg.e2ee.data_dir ~= "" then
        return string.format("matrix-cli --data-dir %s %s", shell_quote(cfg.e2ee.data_dir), base_cmd)
    end
    return string.format("matrix-cli %s", base_cmd)
end

function M.get_rooms_encryption_status(cfg, rooms_list)
    local rooms_arg = ""
    for _, r in ipairs(rooms_list) do
        if rooms_arg ~= "" then
            rooms_arg = rooms_arg .. " "
        end
        rooms_arg = rooms_arg .. r
    end

    local mc_cmd = build_mc_cmd(string.format("--mode room-info --rooms %s 2>/dev/null", shell_quote(rooms_arg)), cfg)

    local pin, pout = nixio.pipe()
    local pid = nixio.fork()

    if pid == 0 then
        pin:close()
        nixio.dup(pout, nixio.stdout)
        pout:close()

        local args = build_ssh_args(cfg, mc_cmd, "-T")
        nixio.execp("ssh", unpack(args, 2))
        os.exit(1)
    elseif pid then
        pout:close()

        local buffer = ""
        while true do
            local chunk = pin:read(4096)
            if not chunk or #chunk == 0 then
                break
            end
            buffer = buffer .. chunk
        end
        pin:close()
        nixio.waitpid(pid)

        local json_start = buffer:find("%[%s*{")
        if not json_start then
            return nil
        end

        local ok, data = pcall(cjson.decode, buffer:sub(json_start))
        if ok and type(data) == "table" then
            local result = {}
            for _, item in ipairs(data) do
                if item.room_id and item.encrypted ~= nil then
                    result[item.room_id] = item.encrypted
                end
            end
            return result
        end
    end

    if pin then
        pcall(pin.close, pin)
    end
    if pout then
        pcall(pout.close, pout)
    end
    return nil
end

function M.poll(cfg, on_event)
    local start_time = os.time()
    local backoff = 5
    local max_backoff = 120
    local processed_events = {}

    local mc_cmd = build_mc_cmd("--mode listen 2>/dev/null", cfg)

    while true do
        local pin, pout = nixio.pipe()
        if not pin then
            logger.error("Failed to create pipe")
            nixio.nanosleep(5, 0)
            return
        end

        logger.debug(string.format("Spawning SSH process to %s@%s...", cfg.e2ee.ssh_user, cfg.e2ee.ssh_host))
        local pid = nixio.fork()
        if not pid then
            logger.error("Failed to fork")
            nixio.nanosleep(5, 0)
            return
        end

        if pid > 0 then
            local f = io.open("/var/run/matrixbot_ssh.pid", "w")
            if f then
                f:write(tostring(pid) .. "\n")
                f:close()
            end
        end

        if pid == 0 then
            pin:close()
            nixio.dup(pout, nixio.stdout)
            pout:close()

            local args = {
                "ssh",
                "-i",
                cfg.e2ee.ssh_key,
                "-p",
                cfg.e2ee.ssh_port,
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                "UserKnownHostsFile=/etc/matrix_bot_known_hosts",
                "-o",
                "ConnectTimeout=15",
                "-o",
                "ServerAliveInterval=5",
                "-o",
                "ServerAliveCountMax=2",
                "-o",
                "BatchMode=yes",
                "-tt",
                cfg.e2ee.ssh_user .. "@" .. cfg.e2ee.ssh_host,
                mc_cmd,
            }

            nixio.execp("ssh", unpack(args, 2))
            os.exit(1)
        else
            pout:close()
            local session_start = os.time()
            local connected = false

            local buffer = ""
            while true do
                local chunk, _ = pin:read(4096)
                if not chunk or #chunk == 0 then
                    break
                end

                buffer = buffer .. chunk
                local nl = buffer:find("\n")
                while nl do
                    local line = buffer:sub(1, nl - 1)
                    buffer = buffer:sub(nl + 1)
                    nl = buffer:find("\n")

                    line = line:gsub("\r", "")

                    if line:sub(1, 1) == "{" then
                        connected = true
                        logger.debug("RAW SSH JSON: " .. line)
                        local ok, json = pcall(cjson.decode, line)
                        if ok and json and json.room_id and json.sender and json.content and json.content.body then
                            logger.debug(
                                "Parsed - ROOM: "
                                    .. json.room_id
                                    .. " | SENDER: "
                                    .. json.sender
                                    .. " | BODY: "
                                    .. tostring(json.content.body)
                            )
                            local ts = tonumber(json.origin_server_ts)
                            local sec = ts and math.floor(ts / 1000) or 0

                            if sec >= start_time then
                                if not (json.event_id and processed_events[json.event_id]) then
                                    if json.event_id then
                                        processed_events[json.event_id] = true
                                    end
                                    if json.sender ~= cfg.main.bot_user then
                                        local ev_ok, ev_err = pcall(on_event, json.room_id, json)
                                        if not ev_ok then
                                            logger.error("Event handler crashed: " .. tostring(ev_err))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            pin:close()

            logger.debug(string.format("Waiting for SSH process (PID: %d) to terminate...", pid))
            nixio.waitpid(pid)
            os.remove("/var/run/matrixbot_ssh.pid")
            logger.debug("SSH process terminated.")

            local session_duration = os.time() - session_start
            if connected or session_duration > 10 then
                logger.info("SSH session ended (duration: " .. tostring(session_duration) .. "s). Resetting backoff.")
                backoff = 5
            else
                logger.warn(
                    "SSH listener closed without receiving events, backing off for " .. tostring(backoff) .. "s"
                )
                nixio.nanosleep(backoff, 0)
                backoff = backoff * 2
                if backoff > max_backoff then
                    backoff = max_backoff
                end
            end
        end
    end
end

function M.send_message_async(cfg, room_id, text)
    local mc_cmd = build_mc_cmd(
        string.format("--mode send --rooms %s --message %s --html", shell_quote(room_id), shell_quote(text)),
        cfg
    )

    local pid = nixio.fork()

    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            local devnull = nixio.open("/dev/null", nixio.O_RDWR)
            nixio.dup(devnull, nixio.stdin)
            nixio.dup(devnull, nixio.stdout)
            nixio.dup(devnull, nixio.stderr)
            devnull:close()

            local args = build_ssh_args(cfg, mc_cmd, "-T")
            nixio.execp("ssh", unpack(args, 2))
            os.exit(1)
        else
            os.exit(0)
        end
    elseif pid then
        nixio.waitpid(pid)
        return true
    end

    return false
end

function M.send_message(cfg, room_id, text)
    local mc_cmd = build_mc_cmd(
        string.format(
            "--mode send --rooms %s --message %s --html 2>/dev/null",
            shell_quote(room_id),
            shell_quote(text)
        ),
        cfg
    )

    local pin, pout = nixio.pipe()
    if not pin then
        return false
    end

    local pid = nixio.fork()
    if pid == 0 then
        pin:close()

        local devnull = nixio.open("/dev/null", nixio.O_RDWR)
        nixio.dup(devnull, nixio.stdin)
        nixio.dup(devnull, nixio.stderr)
        devnull:close()

        nixio.dup(pout, nixio.stdout)
        pout:close()

        local args = build_ssh_args(cfg, mc_cmd, "-T")
        nixio.execp("ssh", unpack(args, 2))
        os.exit(1)
    elseif pid then
        pout:close()

        local buffer = ""
        while true do
            local chunk = pin:read(4096)
            if not chunk or #chunk == 0 then
                break
            end
            buffer = buffer .. chunk
        end
        pin:close()
        local _, _, code = nixio.waitpid(pid)

        if code ~= 0 then
            return false
        end

        local json_start = buffer:find("%[%s*{")
        if not json_start then
            return false
        end

        local ok, data = pcall(cjson.decode, buffer:sub(json_start))
        if ok and type(data) == "table" and data[1] then
            return data[1].status == "success"
        end

        return false
    end

    if pin then
        pcall(pin.close, pin)
    end
    if pout then
        pcall(pout.close, pout)
    end
    return false
end

return M
