local io = require("io")

local M = {}

local function write_line(writer, message)
    writer((message or "") .. "\n")
end

local function print_usage(writer)
    write_line(
        writer,
        "Usage: matrix_send [--ssh-only|--http-only] [--room-id '!room_id:server.tld'] [--] 'Message text'"
    )
end

local function parse_args(argv)
    local mode = "auto"
    local target_room = ""
    local message_parts = {}
    local i = 1
    local parsing_options = true

    while i <= #argv do
        local arg = argv[i]

        if parsing_options and arg == "--" then
            parsing_options = false
        elseif parsing_options and (arg == "--room-id" or arg == "-r") then
            i = i + 1
            target_room = argv[i]
            if not target_room or target_room == "" then
                return nil, "[Error] --room-id requires an argument"
            end
        elseif parsing_options and arg == "--ssh-only" then
            mode = "ssh"
        elseif parsing_options and arg == "--http-only" then
            mode = "http"
        elseif parsing_options and arg:sub(1, 1) == "-" then
            return nil, "Unknown option: " .. arg
        else
            table.insert(message_parts, arg)
        end

        i = i + 1
    end

    local message = table.concat(message_parts, " ")
    if message == "" then
        return nil, nil, true
    end

    return {
        mode = mode,
        target_room = target_room,
        message = message,
    }
end

local function has_complete_ssh_config(cfg)
    return cfg
        and cfg.e2ee
        and cfg.e2ee.ssh_host ~= ""
        and cfg.e2ee.ssh_port ~= ""
        and cfg.e2ee.ssh_user ~= ""
        and cfg.e2ee.ssh_key ~= ""
end

local function collect_rooms(cfg, target_room)
    if target_room ~= "" then
        return { target_room }
    end

    local rooms = cfg.main and cfg.main.rooms or {}
    if #rooms == 0 then
        return nil, "[Error] No room ID specified and MATRIX_ROOM_IDS is empty in config"
    end

    return rooms
end

local function try_http(http_transport, cfg, room_id, message)
    return http_transport.send_message(cfg, room_id, message)
end

local function try_ssh(e2ee_transport, cfg, room_id, message)
    return e2ee_transport.send_message(cfg, room_id, message)
end

M.parse_args = parse_args

function M.run_parsed(parsed, deps)
    deps = deps or {}

    local stderr = deps.stderr or function(chunk)
        io.stderr:write(chunk)
    end

    local config_loader = deps.config_loader
    if not config_loader then
        config_loader = require("matrixbot.config").load
    end

    local cfg = config_loader()
    if not cfg then
        write_line(stderr, "Failed to load configuration")
        return 1
    end

    local rooms, room_err = collect_rooms(cfg, parsed.target_room)
    if not rooms then
        write_line(stderr, room_err)
        return 1
    end

    local should_try_ssh = parsed.mode == "ssh" or (parsed.mode == "auto" and cfg.e2ee and cfg.e2ee.enabled)
    local should_try_http = parsed.mode ~= "ssh"

    local e2ee_transport = deps.e2ee_transport
    local http_transport = deps.http_transport

    if should_try_ssh and not e2ee_transport then
        e2ee_transport = require("matrixbot.transport.e2ee")
    end
    if should_try_http and not http_transport then
        http_transport = require("matrixbot.transport.http")
    end

    local ssh_available = should_try_ssh and has_complete_ssh_config(cfg)

    for _, room_id in ipairs(rooms) do
        if ssh_available then
            if try_ssh(e2ee_transport, cfg, room_id, parsed.message) then
                return 0
            end
        end

        if parsed.mode ~= "ssh" and should_try_http and try_http(http_transport, cfg, room_id, parsed.message) then
            return 0
        end
    end

    write_line(stderr, "[Error] Failed to send message to any of the target rooms")
    return 1
end

function M.run(argv, deps)
    deps = deps or {}

    local stderr = deps.stderr or function(chunk)
        io.stderr:write(chunk)
    end

    local parsed, parse_err, show_usage = parse_args(argv)
    if show_usage then
        print_usage(stderr)
        return 1
    end
    if not parsed then
        write_line(stderr, parse_err)
        return 1
    end

    return M.run_parsed(parsed, deps)
end

return M
