-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
-- luacheck: pop
local wol = require("matrixbot.command.wol")

describe("wol command", function()
    local cfg

    before_each(function()
        cfg = {
            features = {
                mac_pc = "aa:bb:cc:dd:ee:ff",
                wol_interfaces = { "br-lan" }
            }
        }
    end)

    it("rejects invalid mac addresses for wol command", function()
        local result = wol.execute("wol", "zz:yy:xx", cfg)
        assert.matches("Invalid MAC", result)
    end)

    it("handles missing target mac for wol", function()
        local result = wol.execute("wol", "", cfg)
        assert.matches("Usage: wol AA:BB:CC:DD:EE:FF", result)
    end)

    it("accepts valid mac address for wol", function()
        local nixio_mock = require("tests.mocks.nixio")
        nixio_mock.reset()
        nixio_mock.next_fork_results = { 0, 0 }

        local result = wol.execute("wol", "11:22:33:44:55:66", cfg)
        assert.matches("Magic packet sent to <code>11:22:33:44:55:66</code>", result)
    end)

    it("rejects wol_pc if mac_pc is missing", function()
        cfg.features.mac_pc = ""
        local result = wol.execute("wol_pc", "", cfg)
        assert.matches("MAC_PC variable is not set in config", result)
    end)
end)
