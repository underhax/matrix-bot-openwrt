-- luacheck: push ignore 121 122
package.loaded["ubus"] = require("tests.mocks.ubus")
package.loaded["uci"] = require("tests.mocks.uci")
package.loaded["iwinfo"] = require("tests.mocks.iwinfo")
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["nixio.fs"] = require("tests.mocks.nixio").fs
-- luacheck: pop

local network = require("matrixbot.command.network")
local io = require("io")
local os = require("os")

describe("network command", function()
    local tmp_leases, tmp_arp
    local original_open = io.open

    before_each(function()
        tmp_leases = os.tmpname()
        local f = original_open(tmp_leases, "w")
        if f then
            f:write("123456789 aa:bb:cc:dd:ee:ff 192.168.1.100 iPhone 01:aa:bb:cc\n")
            f:write("123456789 11:22:33:44:55:66 192.168.1.101 Desktop 01:11:22\n")
            f:close()
        end

        tmp_arp = os.tmpname()
        f = original_open(tmp_arp, "w")
        if f then
            f:write("IP address       HW type     Flags       HW address            Mask     Device\n")
            f:write("192.168.1.100    0x1         0x2         aa:bb:cc:dd:ee:ff     *        br-lan\n")
            f:write("192.168.1.101    0x1         0x2         11:22:33:44:55:66     *        br-lan\n")
            f:close()
        end

        io.open = function(filename, mode)
            if filename == "/tmp/dhcp.leases" then
                return original_open(tmp_leases, mode)
            elseif filename == "/proc/net/arp" then
                return original_open(tmp_arp, mode)
            end
            return original_open(filename, mode)
        end
    end)

    after_each(function()
        io.open = original_open
        os.remove(tmp_leases)
        os.remove(tmp_arp)
    end)

    it("should list wifi_clients", function()
        local output = network.execute("wifi_clients", {}, {})
        assert.matches("WiFi %(LAN%) Clients", output)
        assert.matches("iPhone", output)
        assert.matches("192.168.1.100", output)
        assert.matches("aa:bb:cc:dd:ee:ff", output)
        assert.not_matches("Desktop", output)
    end)

    it("should list wired_clients", function()
        local output = network.execute("wired_clients", {}, {})
        assert.matches("Wired %(LAN%) Clients", output)
        assert.matches("Desktop", output)
        assert.matches("192.168.1.101", output)
        assert.matches("2001:db8::101", output)
        assert.matches("11:22:33:44:55:66", output)
        assert.not_matches("iPhone", output)
    end)

    it("should list all clients when command is 'clients'", function()
        local output = network.execute("clients", {}, {})
        assert.matches("WiFi %(LAN%) Clients", output)
        assert.matches("iPhone", output)
        assert.matches("Wired %(LAN%) Clients", output)
        assert.matches("Desktop", output)
    end)
end)
