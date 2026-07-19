local nixio = require("nixio")
local notifier = require("matrixbot.utils.notifier")
require("nixio.fs")

local M = {}

function M.service_exists(name)
    return nixio.fs.access("/etc/init.d/" .. name, "x")
end

function M.get_services_list(cfg)
    local sorted_svc = {}
    for _, s in ipairs(cfg.features.svc_wanted or {}) do
        if s ~= "nginx" and M.service_exists(s) then
            table.insert(sorted_svc, s)
        end
    end
    table.sort(sorted_svc)
    return table.concat(sorted_svc, ", ")
end

function M.is_service_allowed(svc, cfg)
    for _, s in ipairs(cfg.features.svc_wanted) do
        if s == svc then
            return true
        end
    end
    return false
end

local function run_sync(prog, ...)
    local pid = nixio.fork()
    if pid == 0 then
        local devnull = nixio.open("/dev/null", nixio.O_RDWR)
        if devnull then
            nixio.dup(devnull, nixio.stdout)
            nixio.dup(devnull, nixio.stderr)
            devnull:close()
        end
        nixio.execp(prog, ...)
        nixio.kill(nixio.getpid(), 9)
    end
    local _, _, code = nixio.waitpid(pid)
    return code
end

local function background_task(task_fn)
    local pid = nixio.fork()
    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            task_fn()
            nixio.kill(nixio.getpid(), 9)
        end
        nixio.kill(nixio.getpid(), 9)
    elseif pid then
        nixio.waitpid(pid)
    end
end

function M.execute(cmd, args, cfg, transport, room_id)
    if cmd == "restart" then
        if not args or args == "" then
            return "🤖 Usage: restart [service]<br>Available: " .. M.get_services_list(cfg)
        end

        if args == "nginx" or not M.is_service_allowed(args, cfg) then
            return "⛔ <b>Access Denied:</b><br>Service '"
                .. args
                .. "' is not in the allowed list: "
                .. M.get_services_list(cfg)
        end

        if not M.service_exists(args) then
            return "❌ <b>Error:</b> Service '" .. args .. "' not found."
        end

        background_task(function()
            local code = run_sync("/etc/init.d/" .. args, "restart")
            nixio.nanosleep(1, 500000000)
            if code == 0 then
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "✅ <b>Service '" .. args .. "'</b> restarted successfully."
                )
            else
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "❌ <b>Service '" .. args .. "'</b> failed to restart (Exit code: " .. tostring(code) .. ")."
                )
            end
        end)

        return "🤖⏳ Service " .. args .. " restarting..."
    elseif cmd == "reload" and args == "nginx" then
        if not M.is_service_allowed("nginx", cfg) then
            return "⛔ <b>Access Denied:</b><br>Service 'nginx' is not in the allowed list."
        end

        background_task(function()
            local test_code = run_sync("nginx", "-t")
            if test_code ~= 0 then
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "❌ <b>Nginx Error:</b> Config check failed! Run 'nginx -t' in terminal to see details."
                )
                return
            end

            local reload_code = run_sync("nginx", "-s", "reload")
            nixio.nanosleep(1, 500000000)
            if reload_code == 0 then
                notifier.send_with_retry(cfg, transport, room_id, "✅ <b>Nginx</b> reloaded successfully.")
            else
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "❌ <b>Nginx Error:</b> Reload failed (Exit code: " .. tostring(reload_code) .. ")."
                )
            end
        end)

        return "🤖⏳ Config OK. Nginx reloading..."
    elseif cmd == "ifup" or cmd == "ifdown" then
        if not args or args == "" then
            return "🤖 Usage: " .. cmd .. " interface_name"
        end

        if args:match("[^%w%_%-]") then
            return "⛔ <b>Error:</b> Invalid interface name. "
                .. "Only alphanumeric characters, dashes, and underscores are allowed."
        end

        local uci = require("uci")
        local cursor = uci.cursor()
        if not cursor:get("network", args) then
            return "❌ <b>Error:</b> Interface '" .. args .. "' not found in configuration."
        end

        background_task(function()
            local code = run_sync(cmd, args)
            local action_text = cmd == "ifup" and "started" or "stopped"
            nixio.nanosleep(1, 500000000)
            if code == 0 then
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "✅ <b>Interface '" .. args .. "'</b> " .. action_text .. " successfully."
                )
            else
                notifier.send_with_retry(
                    cfg,
                    transport,
                    room_id,
                    "❌ <b>Interface '" .. args .. "'</b> failed to " .. (cmd == "ifup" and "start" or "stop") .. "."
                )
            end
        end)

        local action_text = cmd == "ifup" and "starting" or "stopping"
        return "🤖⏳ Interface " .. args .. " " .. action_text .. "..."
    end

    return ""
end

return M
