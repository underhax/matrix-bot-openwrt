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

    it("gracefully handles missing iwinfo type for an interface", function()
        local iwinfo_mock = require("tests.mocks.iwinfo")
        local old_type = iwinfo_mock.type
        ---@diagnostic disable-next-line: duplicate-set-field
        iwinfo_mock.type = function(_ifname)
            return nil
        end

        local result = wifi.execute("wifi_info", "", {})
        iwinfo_mock.type = old_type

        assert.are.equal("🤖 No wireless interfaces found.", result)
    end)

    it("gracefully handles missing iwinfo table despite type returning something", function()
        local iwinfo_mock = require("tests.mocks.iwinfo")
        local old_type = iwinfo_mock.type
        ---@diagnostic disable-next-line: duplicate-set-field
        iwinfo_mock.type = function(_ifname)
            return "ghost_type"
        end

        local result = wifi.execute("wifi_info", "", {})
        iwinfo_mock.type = old_type

        assert.are.equal("🤖 No wireless interfaces found.", result)
    end)

    it("generates detailed info and handles strange signal values without crashing", function()
        local iwinfo_mock = require("tests.mocks.iwinfo")
        local old_signal = iwinfo_mock.nl80211.signal
        iwinfo_mock.nl80211.signal = function(ifname)
            if ifname == "wlan0" then
                return -200
            end
            return nil
        end
        iwinfo_mock.nl80211.bssid = function() return "aa:bb:cc:dd:ee:ff" end
        iwinfo_mock.nl80211.bitrate = function() return 100000 end
        iwinfo_mock.nl80211.encryption = function() return { description = "WPA2-PSK" } end
        iwinfo_mock.nl80211.mode = function() return "Master" end
        iwinfo_mock.nl80211.hardware_name = function() return "Generic MAC" end
        iwinfo_mock.nl80211.country = function() return "US" end
        iwinfo_mock.nl80211.noise = function() return -95 end
        iwinfo_mock.nl80211.txpower = function() return 20 end
        iwinfo_mock.nl80211.frequency = function() return 2412 end

        local cfg = {
            features = {
                wifi_detailed = true,
                wifi_show_key = true
            }
        }

        local result = wifi.execute("wifi_info", "", cfg)
        iwinfo_mock.nl80211.signal = old_signal
        iwinfo_mock.nl80211.bssid = nil
        iwinfo_mock.nl80211.bitrate = nil
        iwinfo_mock.nl80211.encryption = nil
        iwinfo_mock.nl80211.mode = nil
        iwinfo_mock.nl80211.hardware_name = nil
        iwinfo_mock.nl80211.country = nil
        iwinfo_mock.nl80211.noise = nil
        iwinfo_mock.nl80211.txpower = nil
        iwinfo_mock.nl80211.frequency = nil

        assert.is_not_nil(result:find("Signal: %-200 dBm"))
        assert.is_not_nil(result:find("Clients: <b>1</b>"))
        assert.is_not_nil(result:find("🚀 5G wlan0"))
    end)
end)
