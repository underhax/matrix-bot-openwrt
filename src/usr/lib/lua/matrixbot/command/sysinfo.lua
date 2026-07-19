local nixio = require("nixio")
local notifier = require("matrixbot.utils.notifier")

local M = {}

local function format_uptime(uptime_sec)
    local d = math.floor(uptime_sec / 86400)
    local h = math.floor((uptime_sec % 86400) / 3600)
    local m = math.floor((uptime_sec % 3600) / 60)
    if d > 0 then
        return string.format("%d days, %02d:%02d", d, h, m)
    else
        return string.format("%02d:%02d", h, m)
    end
end

local function get_uptime_seconds()
    local f = io.open("/proc/uptime", "r")
    if not f then
        return nil
    end
    local line = f:read("*l")
    f:close()
    if not line then
        return nil
    end
    local sec = line:match("^(%S+)")
    return tonumber(sec)
end

local function get_loadavg()
    local f = io.open("/proc/loadavg", "r")
    if not f then
        return "0.00", "0.00", "0.00"
    end
    local line = f:read("*l")
    f:close()
    if not line then
        return "0.00", "0.00", "0.00"
    end
    local l1, l5, l15 = line:match("^(%S+)%s+(%S+)%s+(%S+)")
    return l1 or "0.00", l5 or "0.00", l15 or "0.00"
end

local function get_memory_info()
    local mem = {}
    local f = io.open("/proc/meminfo", "r")
    if not f then
        return nil
    end
    for line in f:lines() do
        local key, val = line:match("^(%S+):%s+(%d+)")
        if key and val then
            mem[key] = tonumber(val)
        end
        if mem.MemTotal and mem.MemFree then
            break
        end
    end
    f:close()
    return mem
end

function M.execute(cmd, _args, cfg, transport, room_id)
    if cmd == "uptime" then
        local uptime_sec = get_uptime_seconds()
        if not uptime_sec then
            return "❌ <b>Error:</b> Could not read /proc/uptime"
        end
        local up = format_uptime(math.floor(uptime_sec))
        local l1, l5, l15 = get_loadavg()

        return string.format(
            "🤖 <b>Uptime:</b><br>time: %s<br>up: %s<br>load average: %s, %s, %s",
            os.date("%H:%M:%S"),
            up,
            l1,
            l5,
            l15
        )
    elseif cmd == "memory" then
        local mem = get_memory_info()
        if not mem or not mem.MemTotal or not mem.MemFree then
            return "❌ <b>Error:</b> Could not read /proc/meminfo"
        end
        local total = math.floor(mem.MemTotal / 1024)
        local free = math.floor(mem.MemFree / 1024)
        local used = total - free
        return string.format("🤖 <b>Memory:</b><br>Total: %d MB Used: %d MB Free: %d MB", total, used, free)
    elseif cmd == "meminfo" then
        local lines = {}
        local f = io.open("/proc/meminfo", "r")
        if f then
            for _ = 1, 5 do
                local line = f:read("*l")
                if not line then
                    break
                end
                local k, v, unit = line:match("([^:]+):%s+(%d+)%s*(%a*)")
                if k and v and unit == "kB" then
                    table.insert(lines, string.format("%s: %d MB", k, math.floor(tonumber(v) / 1024)))
                else
                    table.insert(lines, line)
                end
            end
            f:close()
            return "🤖 <b>Memory Detail:</b><br>" .. table.concat(lines, "<br>")
        else
            return "❌ <b>Error:</b> Could not read /proc/meminfo"
        end
    elseif cmd == "wan_ip" then
        transport.send_message(cfg, room_id, "🤖⏳ Resolving WAN IP...")

        local pid = nixio.fork()
        if pid == 0 then
            local ip = nil
            local uci = require("uci")
            local cursor = uci.cursor()

            local iface = cursor:get("network", "wan", "device")
            if not iface or iface == "" then
                iface = cursor:get("network", "wan", "ifname")
            end

            local function get_curl(url, ifc)
                local r, w = nixio.pipe()
                local cpid = nixio.fork()
                if cpid == 0 then
                    r:close()
                    nixio.dup(w, nixio.stdout)
                    w:close()
                    if ifc then
                        nixio.execp(
                            "curl",
                            "-4",
                            "-s",
                            "--interface",
                            ifc,
                            "--connect-timeout",
                            "5",
                            "--max-time",
                            "5",
                            url
                        )
                    end
                    nixio.execp("curl", "-4", "-s", "--connect-timeout", "5", "--max-time", "5", url)
                    nixio.execp("wget", "-4", "-qO-", "--timeout=5", url)
                    nixio.kill(nixio.getpid(), 9)
                end
                w:close()
                local out = r:read(1024) or ""
                r:close()
                nixio.waitpid(cpid)
                return out:match("^%s*([%d%.]+)%s*$")
            end

            local urls = {
                "https://4.ipquail.com/ip",
                "https://ifconfig.me/ip",
                "https://api64.ipify.org",
            }

            for _, u in ipairs(urls) do
                ip = get_curl(u, iface)
                if ip and ip ~= "" then
                    break
                end
            end

            if not ip or ip == "" then
                local ubus = require("ubus")
                local conn = ubus.connect()
                if conn then
                    local status = conn:call("network.interface.wan", "status", {})
                    if status and status["ipv4-address"] and status["ipv4-address"][1] then
                        ip = status["ipv4-address"][1].address
                    end
                end
            end

            local res = ip and string.format("🤖 <b>WAN IP:</b> <code>%s</code>", ip)
                or "❌ <b>WAN IP:</b> Could not determine (all sources failed)"
            notifier.send_with_retry(cfg, transport, room_id, res)

            nixio.kill(nixio.getpid(), 9)
        end
        return nil
    end
    return nil
end

return M
