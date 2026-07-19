-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["nixio.fs"] = require("tests.mocks.nixio").fs
package.loaded["uci"] = require("tests.mocks.uci")
package.loaded["iwinfo"] = require("tests.mocks.iwinfo")
-- luacheck: pop

local nixio_mock = require("tests.mocks.nixio")
local uci_mock = require("tests.mocks.uci")
local wifi = require("matrixbot.command.wifi")

describe("wifi command", function()
    before_each(function()
        nixio_mock.reset()
        uci_mock.reset()
    end)

    it("runs 2.4GHz actions against radio0", function()
        nixio_mock.next_fork_results = { 0, 0 }

        local result = wifi.execute("wifi_up_2_4", "", {})

        assert.are.equal("🤖⏳ 2.4GHz (radio0) starting...", result)
        assert.are.equal(1, #nixio_mock.exec_calls)
        assert.are.equal("wifi", nixio_mock.exec_calls[1][1])
        assert.are.equal("up", nixio_mock.exec_calls[1][2])
        assert.are.equal("radio0", nixio_mock.exec_calls[1][3])
    end)

    it("runs 5GHz actions against radio1", function()
        nixio_mock.next_fork_results = { 0, 0 }

        local result = wifi.execute("wifi_reload_5", "", {})

        assert.are.equal("🤖⏳ 5GHz (radio1) reloading...", result)
        assert.are.equal(1, #nixio_mock.exec_calls)
        assert.are.equal("wifi", nixio_mock.exec_calls[1][1])
        assert.are.equal("reload", nixio_mock.exec_calls[1][2])
        assert.are.equal("radio1", nixio_mock.exec_calls[1][3])
    end)

    it("rejects missing radio configuration", function()
        uci_mock.data.wireless.radio0 = nil

        local result = wifi.execute("wifi_down_2_4", "", {})

        assert.are.equal("❌ <b>Error:</b> radio0 not found in config.", result)
        assert.are.equal(0, #nixio_mock.exec_calls)
    end)
end)
