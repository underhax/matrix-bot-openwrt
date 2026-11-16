local nixio = require("nixio")
local logger = require("matrixbot.utils.logger")
local os = require("os")
local io = require("io")

local M = {}

function M.set_backoff(backoff, max_backoff)
    local f = io.open("/tmp/matrixbot_backoff", "w")
    if f then
        f:write(tostring(backoff))
        f:close()
    end

    logger.warn("Network issue, backing off for " .. tostring(backoff) .. "s")
    nixio.nanosleep(backoff, 0)

    local next_backoff = backoff * 2
    if max_backoff and next_backoff > max_backoff then
        return max_backoff
    end
    return next_backoff
end

function M.clear_backoff()
    os.remove("/tmp/matrixbot_backoff")
end

local function is_service_running()
    local ubus_ok, ubus_mod = pcall(require, "ubus")
    if ubus_ok and ubus_mod then
        local conn = ubus_mod.connect()
        if conn then
            local res = conn:call("service", "list", { name = "matrixbot" })
            pcall(function()
                conn:close()
            end)
            if type(res) == "table" then
                local svc = res.matrixbot
                if type(svc) == "table" and type(svc.instances) == "table" then
                    for _, inst in pairs(svc.instances) do
                        if type(inst) == "table" and inst.running then
                            return true
                        end
                    end
                end
                return false
            end
        end
    end
    return os.execute("/etc/init.d/matrixbot running >/dev/null 2>&1") == 0
end

local function is_service_enabled()
    local fs = nixio.fs
    if fs and type(fs.dir) == "function" then
        local iter = fs.dir("/etc/rc.d")
        if iter then
            for entry_name in iter do
                if entry_name:match("^S%d+matrixbot$") and fs.access("/etc/rc.d/" .. entry_name) then
                    return true
                end
            end
            return false
        end
    end
    return os.execute("/etc/init.d/matrixbot enabled >/dev/null 2>&1") == 0
end

local function read_backoff_sec()
    local f = io.open("/tmp/matrixbot_backoff", "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    return tonumber(content and content:match("%d+"))
end

function M.format_uptime(uptime_sec)
    local m = math.floor(uptime_sec / 60)
    local h = math.floor(m / 60)
    local d = math.floor(h / 24)
    m = m % 60
    h = h % 24
    if d > 0 then
        return string.format(" (Uptime: %dd %dh %dm)", d, h, m)
    elseif h > 0 then
        return string.format(" (Uptime: %dh %dm)", h, m)
    end
    return string.format(" (Uptime: %dm)", m)
end

function M.get_status()
    local running = is_service_running()
    local enabled = is_service_enabled()

    if not running then
        return {
            running = false,
            enabled = enabled,
            state = "stopped",
        }
    end

    local fs = nixio.fs
    local backoff_stat = fs and type(fs.stat) == "function" and fs.stat("/tmp/matrixbot_backoff") or nil
    if backoff_stat then
        return {
            running = true,
            enabled = enabled,
            state = "backoff",
            backoff_sec = read_backoff_sec(),
        }
    end

    local pid_stat = fs and type(fs.stat) == "function" and fs.stat("/var/run/matrixbot_poller.pid") or nil
    if pid_stat and pid_stat.mtime then
        local diff = os.time() - pid_stat.mtime
        if diff < 0 then
            diff = 0
        end
        return {
            running = true,
            enabled = enabled,
            state = "running",
            uptime_sec = diff,
        }
    end

    return {
        running = true,
        enabled = enabled,
        state = "starting",
    }
end

return M
