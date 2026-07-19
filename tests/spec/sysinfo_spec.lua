-- luacheck: push ignore 121 122
package.loaded["ubus"] = require("tests.mocks.ubus")
package.loaded["ssl.https"] = {
    request = function(req)
        return 1, 200, nil, nil
    end,
}
package.loaded["ltn12"] = {
    source = { string = function() end },
    sink = {
        table = function(t)
            return function(chunk)
                if chunk then
                    table.insert(t, chunk)
                end
                return 1
            end
        end,
    },
}

package.loaded["uci"] = require("tests.mocks.uci")
package.loaded["iwinfo"] = require("tests.mocks.iwinfo")
package.loaded["nixio"] = require("tests.mocks.nixio")
-- luacheck: pop

local sysinfo = require("matrixbot.command.sysinfo")
local io = require("io")
local os = require("os")

describe("sysinfo command", function()
    it("should return formatted sysinfo based on ubus", function()
        local tmp_meminfo = os.tmpname()
        local f = io.open(tmp_meminfo, "w")
        if f then
            f:write("MemTotal:       131072 kB\n")
            f:write("MemFree:         65536 kB\n")
            f:write("MemAvailable:    65536 kB\n")
            f:write("Buffers:         10240 kB\n")
            f:write("Cached:          20480 kB\n")
            f:close()

            local tmp_uptime = os.tmpname()
            local f_up = io.open(tmp_uptime, "w")
            if f_up then
                f_up:write("123456.78 98765.43\n")
                f_up:close()
            end

            local tmp_loadavg = os.tmpname()
            local f_load = io.open(tmp_loadavg, "w")
            if f_load then
                f_load:write("0.02 0.03 0.05 1/123 4567\n")
                f_load:close()
            end
            local original_open = _G.io.open
            -- luacheck: push ignore 122
            ---@diagnostic disable-next-line: duplicate-set-field
            _G.io.open = function(filename, mode)
                if filename == "/proc/meminfo" then
                    return original_open(tmp_meminfo, mode)
                elseif filename == "/proc/uptime" then
                    return original_open(tmp_uptime, mode)
                elseif filename == "/proc/loadavg" then
                    return original_open(tmp_loadavg, mode)
                end
                return original_open(filename, mode)
            end
            -- luacheck: pop

            local last_msg = nil
            local transport_mock = {
                send_message = function(c, r, msg)
                    last_msg = msg
                    return true
                end,
            }

            local out_mem = sysinfo.execute("memory", {}, {}, transport_mock, "room1")
            assert.is_string(out_mem)
            assert.matches("Total:%s+128 MB", out_mem)

            local out_meminfo = sysinfo.execute("meminfo", {}, {}, transport_mock, "room1")
            assert.is_string(out_meminfo)
            assert.matches("MemTotal:%s+128 MB", out_meminfo)
            assert.matches("MemFree:%s+64 MB", out_meminfo)

            local out_wan = sysinfo.execute("wan_ip", {}, {}, transport_mock, "room1")
            assert.is_nil(out_wan)
            assert.matches("Resolving WAN IP", last_msg)

            local out_uptime = sysinfo.execute("uptime", {}, {}, transport_mock, "room1")
            assert.matches("load average:%s+0%.02,%s+0%.03,%s+0%.05", out_uptime)

            local out_invalid = sysinfo.execute("invalid_cmd", {}, {}, transport_mock, "room1")
            assert.is_nil(out_invalid)

            -- luacheck: push ignore 122
            ---@diagnostic disable-next-line: duplicate-set-field
            _G.io.open = original_open
            -- luacheck: pop
            os.remove(tmp_meminfo)
            os.remove(tmp_uptime)
            os.remove(tmp_loadavg)
        end
    end)
end)
