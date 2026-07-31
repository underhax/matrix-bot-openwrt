local assert = require("luassert")
local spy = require("luassert.spy")

-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
-- luacheck: pop
local nixio_mock = require("tests.mocks.nixio")

describe("state utility", function()
    local state
    local old_io_open
    local old_os_remove
    local logger
    local old_logger_warn
    local mock_file

    before_each(function()
        nixio_mock.reset()

        old_io_open = io.open
        old_os_remove = os.remove

        mock_file = {
            write = spy.new(function() end),
            close = spy.new(function() end),
        }

        -- luacheck: push ignore 121 122
        io.open = spy.new(function(path, mode)
            if path == "/tmp/matrixbot_backoff" then
                return mock_file
            end
            return old_io_open(path, mode)
        end)

        os.remove = spy.new(function()
            return true
        end)

        package.loaded["matrixbot.utils.logger"] = nil
        -- luacheck: pop
        logger = require("matrixbot.utils.logger")
        old_logger_warn = logger.warn
        logger.warn = spy.new(function() end)

        -- luacheck: push ignore 121 122
        package.loaded["matrixbot.utils.state"] = nil
        -- luacheck: pop
        state = require("matrixbot.utils.state")
    end)

    after_each(function()
        -- luacheck: push ignore 121 122
        io.open = old_io_open
        os.remove = old_os_remove
        logger.warn = old_logger_warn
        -- luacheck: pop
    end)

    it("should set backoff, write file, and sleep", function()
        local next_backoff = state.set_backoff(5, 120)

        assert.spy(io.open).was_called_with("/tmp/matrixbot_backoff", "w")
        assert.spy(mock_file.write).was_called_with(mock_file, "5")
        assert.spy(mock_file.close).was_called_with(mock_file)

        assert.spy(logger.warn).was_called_with("Network issue, backing off for 5s")
        assert.are.equal(1, #nixio_mock.nanosleep_calls)
        assert.are.equal(5, nixio_mock.nanosleep_calls[1].sec)
        assert.are.equal(10, next_backoff)
    end)

    it("should cap backoff to max_backoff", function()
        local next_backoff = state.set_backoff(100, 120)
        assert.are.equal(120, next_backoff)
    end)

    it("should not error if max_backoff is nil", function()
        local next_backoff = state.set_backoff(100)
        assert.are.equal(200, next_backoff)
    end)

    it("should clear backoff file", function()
        state.clear_backoff()
        assert.spy(os.remove).was_called_with("/tmp/matrixbot_backoff")
    end)
end)
