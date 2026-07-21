local assert = require("luassert")
local spy = require("luassert.spy")

-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
-- luacheck: pop
local nixio_mock = require("tests.mocks.nixio")

describe("logger utility", function()
    local logger
    local old_execute

    before_each(function()
        nixio_mock.reset()
        old_execute = os.execute

        -- luacheck: push ignore 121 122
        os.execute = spy.new(function()
            return true
        end)
        package.loaded["matrixbot.utils.logger"] = nil
        -- luacheck: pop

        logger = require("matrixbot.utils.logger")
    end)

    after_each(function()
        -- luacheck: push ignore 121 122
        os.execute = old_execute
        -- luacheck: pop
    end)

    it("should log info messages to syslog", function()
        logger.info("Test message")
        assert.are.equal(1, #nixio_mock.syslog_calls)
        assert.are.equal("info", nixio_mock.syslog_calls[1].priority)
        assert.are.equal("matrixbot: Test message", nixio_mock.syslog_calls[1].message)
    end)

    it("should log error messages to syslog without stopping service", function()
        logger.error("Error message")
        assert.are.equal(1, #nixio_mock.syslog_calls)
        assert.are.equal("err", nixio_mock.syslog_calls[1].priority)
        assert.are.equal("matrixbot: Error message", nixio_mock.syslog_calls[1].message)
        assert.spy(os.execute).was_not_called()
    end)

    it("should trigger service stop on FATAL errors", function()
        logger.error("FATAL: Something went horribly wrong")
        assert.are.equal(1, #nixio_mock.syslog_calls)
        assert.are.equal("err", nixio_mock.syslog_calls[1].priority)
        assert.are.equal("matrixbot: FATAL: Something went horribly wrong", nixio_mock.syslog_calls[1].message)
        assert.spy(os.execute).was_called_with("(/etc/init.d/matrixbot stop) >/dev/null 2>&1 &")
    end)
end)
