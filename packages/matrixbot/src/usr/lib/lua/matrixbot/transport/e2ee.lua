local nixio = require("nixio")
local cjson = require("cjson")
local logger = require("matrixbot.utils.logger")
local state = require("matrixbot.utils.state")

local function handle_transport_error(cfg, error_buffer)
    if not error_buffer then
        return
    end
    local is_fatal = error_buffer:match("Permission denied")
        or error_buffer:match("Host key verification failed")
        or error_buffer:match("not accessible")
        or error_buffer:match("fatal")
        or error_buffer:match("error")
        or error_buffer:match("panic")
        or error_buffer:match("failed")
        or error_buffer:match("refused")
        or error_buffer:match("denied")

    if error_buffer:match("Could not resolve hostname") then
        local dns_alive = false
        for _, domain in ipairs({ "google.com", "cloudflare.com", "openwrt.org" }) do
            if nixio.getaddrinfo(domain, "inet") then
                dns_alive = true
                break
            end
        end
        if dns_alive then
            is_fatal = true
        end
    end

    if is_fatal then
        local error_prefix = cfg.e2ee.mode == "local" and "FATAL LOCAL MATRIX-CLI ERROR:" or "FATAL SSH ERROR:"
        logger.error(error_prefix .. "\n" .. error_buffer)
        os.exit(1)
    end
end

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

local function build_local_args(cfg, mode_args)
    local args = { "/usr/bin/matrix-cli" }
    if cfg.e2ee.local_data_dir and cfg.e2ee.local_data_dir ~= "" then
        table.insert(args, "-data-dir")
        table.insert(args, cfg.e2ee.local_data_dir)
    end
    for _, a in ipairs(mode_args) do
        table.insert(args, a)
    end
    return args
end

local function exec_local(cfg, args)
    nixio.umask(63)
    if cfg.e2ee.run_user then
        local uid, gid
        local f = io.open("/etc/passwd", "r")
        if f then
            for line in f:lines() do
                local u, _, i, g = line:match("^([^:]+):([^:]*):(%d+):(%d+):")
                if u == cfg.e2ee.run_user then
                    uid = tonumber(i)
                    gid = tonumber(g)
                    break
                end
            end
            f:close()
        end
        if uid and gid and type(nixio.setgid) == "function" and type(nixio.setuid) == "function" then
            nixio.setgid(gid)
            nixio.setuid(uid)
        end
    end
    nixio.execp("/usr/bin/matrix-cli", unpack(args, 2))
end

function M.get_rooms_encryption_status(cfg, rooms_list)
    local rooms_arg = ""
    for _, r in ipairs(rooms_list) do
        if rooms_arg ~= "" then
            rooms_arg = rooms_arg .. " "
        end
        rooms_arg = rooms_arg .. r
    end

    local mc_cmd = build_mc_cmd(string.format("--mode room-info --json --rooms %s", shell_quote(rooms_arg)), cfg)
    local local_args = build_local_args(cfg, { "--mode", "room-info", "--json", "--rooms", rooms_arg })

    local backoff = 5
    while true do
        local pin, pout = nixio.pipe()
        if not pin then
            logger.error("Failed to create pipe in get_rooms_encryption_status")
            backoff = state.set_backoff(backoff, 900)
        else
            if cfg.e2ee.mode == "local" then
                logger.debug("Requesting room encryption status via local matrix-cli...")
            else
                logger.debug(
                    string.format(
                        "Requesting room encryption status via SSH to %s@%s...",
                        cfg.e2ee.ssh_user,
                        cfg.e2ee.ssh_host
                    )
                )
            end
            local pid = nixio.fork()
            if not pid then
                logger.error("Failed to fork in get_rooms_encryption_status")
                pin:close()
                pout:close()
                backoff = state.set_backoff(backoff, 900)
            elseif pid == 0 then
                pin:close()
                nixio.dup(pout, nixio.stdout)
                nixio.dup(pout, nixio.stderr)
                pout:close()

                if cfg.e2ee.mode == "local" then
                    exec_local(cfg, local_args)
                else
                    local args = build_ssh_args(cfg, mc_cmd, "-T")
                    nixio.execp("ssh", unpack(args, 2))
                end
                os.exit(1)
            else
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
                if json_start then
                    local ok, data = pcall(cjson.decode, buffer:sub(json_start))
                    if ok and type(data) == "table" then
                        local result = {}
                        for _, item in ipairs(data) do
                            if item.room_id and item.encrypted ~= nil then
                                result[item.room_id] = item.encrypted
                            end
                        end
                        state.clear_backoff()
                        return result
                    end
                end

                handle_transport_error(cfg, buffer)
                backoff = state.set_backoff(backoff, 900)
            end
        end
    end
end

function M.poll(cfg, on_event)
    local start_time = os.time()
    local backoff = 5
    local processed_events = {}

    local mc_cmd = build_mc_cmd("--mode listen --json", cfg)
    local local_args = build_local_args(cfg, { "--mode", "listen", "--json" })

    while true do
        local pin, pout = nixio.pipe()
        if not pin then
            logger.error("Failed to create pipe")
            nixio.nanosleep(5, 0)
            return
        end

        if cfg.e2ee.mode == "local" then
            logger.debug("Spawning local matrix-cli process: /usr/bin/matrix-cli")
        else
            logger.debug(string.format("Spawning SSH process to %s@%s...", cfg.e2ee.ssh_user, cfg.e2ee.ssh_host))
        end
        local pid = nixio.fork()
        if not pid then
            logger.error("Failed to fork")
            nixio.nanosleep(5, 0)
            return
        end

        if pid > 0 then
            local pid_file = cfg.e2ee.mode == "local" and "/var/run/matrixbot_local.pid" or "/var/run/matrixbot_ssh.pid"
            local f = io.open(pid_file, "w")
            if f then
                f:write(tostring(pid) .. "\n")
                f:close()
            end
        end

        if pid == 0 then
            pin:close()
            nixio.dup(pout, nixio.stdout)
            nixio.dup(pout, nixio.stderr)
            pout:close()

            if cfg.e2ee.mode == "local" then
                exec_local(cfg, local_args)
            else
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
            end
            os.exit(1)
        else
            pout:close()
            local session_start = os.time()
            local connected = false

            local error_buffer = ""
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
                        if not connected then
                            connected = true
                            state.clear_backoff()
                        end
                        logger.debug("RAW SSH JSON: " .. line)
                        local ok, json = pcall(cjson.decode, line)
                        if ok and json then
                            if json.level == "fatal" or json.error then
                                logger.error("matrix-cli error: " .. tostring(json.error or "fatal error"))
                            elseif json.room_id and json.sender and json.content and json.content.body then
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
                    else
                        if os.time() - session_start < 5 then
                            error_buffer = error_buffer .. line .. "\n"
                        end
                    end
                end
            end

            pin:close()

            local pid_file = cfg.e2ee.mode == "local" and "/var/run/matrixbot_local.pid" or "/var/run/matrixbot_ssh.pid"
            local process_name = cfg.e2ee.mode == "local" and "local matrix-cli process" or "SSH process"
            logger.debug(string.format("Waiting for %s (PID: %d) to terminate...", process_name, pid))
            nixio.waitpid(pid)
            os.remove(pid_file)
            logger.debug(process_name:gsub("^%l", string.upper) .. " terminated.")

            local session_duration = os.time() - session_start
            local session_name = cfg.e2ee.mode == "local" and "Local session" or "SSH session"
            if connected or session_duration > 10 then
                logger.info(
                    session_name .. " ended (duration: " .. tostring(session_duration) .. "s). Resetting backoff."
                )
                backoff = 5
            else
                handle_transport_error(cfg, error_buffer)
                backoff = state.set_backoff(backoff, 900)
            end
        end
    end
end

function M.send_message_async(cfg, room_id, text)
    local mc_cmd = build_mc_cmd(
        string.format("--mode send --json --rooms %s --message %s --html", shell_quote(room_id), shell_quote(text)),
        cfg
    )
    local local_args =
        build_local_args(cfg, { "--mode", "send", "--json", "--rooms", room_id, "--message", text, "--html" })

    if cfg.e2ee.mode == "local" then
        logger.debug(string.format("Sending message (async) via local matrix-cli to room %s...", room_id))
    else
        logger.debug(
            string.format(
                "Sending message (async) via SSH to %s@%s for room %s...",
                cfg.e2ee.ssh_user,
                cfg.e2ee.ssh_host,
                room_id
            )
        )
    end
    local pid = nixio.fork()

    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            local devnull = nixio.open("/dev/null", nixio.O_RDWR)
            nixio.dup(devnull, nixio.stdin)
            nixio.dup(devnull, nixio.stdout)
            nixio.dup(devnull, nixio.stderr)
            devnull:close()

            if cfg.e2ee.mode == "local" then
                exec_local(cfg, local_args)
            else
                local args = build_ssh_args(cfg, mc_cmd, "-T")
                nixio.execp("ssh", unpack(args, 2))
            end
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
    local fmt = "--mode send --json --rooms %s --message %s --html"
    local mc_cmd = build_mc_cmd(string.format(fmt, shell_quote(room_id), shell_quote(text)), cfg)
    local local_args =
        build_local_args(cfg, { "--mode", "send", "--json", "--rooms", room_id, "--message", text, "--html" })

    local pin, pout = nixio.pipe()
    if not pin then
        return false
    end

    if cfg.e2ee.mode == "local" then
        logger.debug(string.format("Sending message via local matrix-cli to room %s...", room_id))
    else
        logger.debug(
            string.format(
                "Sending message via SSH to %s@%s for room %s...",
                cfg.e2ee.ssh_user,
                cfg.e2ee.ssh_host,
                room_id
            )
        )
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

        if cfg.e2ee.mode == "local" then
            exec_local(cfg, local_args)
        else
            local args = build_ssh_args(cfg, mc_cmd, "-T")
            nixio.execp("ssh", unpack(args, 2))
        end
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
