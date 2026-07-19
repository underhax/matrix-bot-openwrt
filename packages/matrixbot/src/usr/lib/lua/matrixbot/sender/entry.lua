local sender_cli = require("matrixbot.sender.cli")

local M = {}

local function try_ubus_send(ubus_module, room_id, message)
    local conn = ubus_module.connect()
    if not conn or not conn.call then
        return false
    end

    local ok, res, err = pcall(conn.call, conn, "matrixbot", "send", {
        room = room_id,
        text = message,
    })

    if not ok then
        return false
    end

    if res == nil and type(err) == "number" and err ~= 0 then
        return false
    end

    return true
end

function M.run(argv, deps)
    deps = deps or {}

    local parsed = sender_cli.parse_args(argv)
    if not parsed then
        return sender_cli.run(argv, deps)
    end

    if parsed.mode == "auto" then
        local ubus_module = deps.ubus_module or require("ubus")
        if try_ubus_send(ubus_module, parsed.target_room, parsed.message) then
            return 0
        end
    end

    local direct_runner = deps.direct_runner
    if direct_runner then
        return direct_runner(parsed, deps)
    end

    return sender_cli.run_parsed(parsed, deps)
end

return M
