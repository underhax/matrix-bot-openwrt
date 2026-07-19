-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
-- luacheck: pop

local nixio_mock = require("tests.mocks.nixio")
local notifier = require("matrixbot.utils.notifier")

describe("notifier utils", function()
    before_each(function()
        nixio_mock.reset()
    end)

    it("retries until send succeeds", function()
        local attempts = 0
        local transport = {
            send_message = function()
                attempts = attempts + 1
                return attempts == 3
            end,
        }

        local ok = notifier.send_with_retry({}, transport, "!room:matrix.example", "done")

        assert.is_true(ok)
        assert.are.equal(3, attempts)
        assert.are.equal(3, #nixio_mock.nanosleep_calls)
        assert.are.equal(2, nixio_mock.nanosleep_calls[1].sec)
        assert.are.equal(4, nixio_mock.nanosleep_calls[2].sec)
        assert.are.equal(8, nixio_mock.nanosleep_calls[3].sec)
    end)

    it("returns false after all attempts fail", function()
        local attempts = 0
        local transport = {
            send_message = function()
                attempts = attempts + 1
                return false
            end,
        }

        local ok = notifier.send_with_retry({}, transport, "!room:matrix.example", "done")

        assert.is_false(ok)
        assert.are.equal(5, attempts)
        assert.are.equal(5, #nixio_mock.nanosleep_calls)
        assert.are.equal(1, #nixio_mock.syslog_calls)
        assert.matches("Failed to send notification after 5 attempts", nixio_mock.syslog_calls[1].message)
    end)

    it("can skip sleeping before the first attempt", function()
        local attempts = 0
        local transport = {
            send_message = function()
                attempts = attempts + 1
                return attempts == 2
            end,
        }

        local ok = notifier.send_with_retry({}, transport, "!room:matrix.example", "done", {
            sleep_before_first = false,
        })

        assert.is_true(ok)
        assert.are.equal(2, attempts)
        assert.are.equal(1, #nixio_mock.nanosleep_calls)
        assert.are.equal(4, nixio_mock.nanosleep_calls[1].sec)
    end)
end)
