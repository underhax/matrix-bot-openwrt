local assert = require("luassert")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

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

    describe("service status", function()
        local old_ubus
        local old_fs_dir
        local old_fs_access
        local time_stub
        local open_stub
        local ubus_running
        local rc_entries
        local backoff_content

        before_each(function()
            old_ubus = package.loaded["ubus"]
            old_fs_dir = nixio_mock.fs.dir
            old_fs_access = nixio_mock.fs.access

            ubus_running = false
            rc_entries = {}
            backoff_content = nil

            local ubus_mock = {
                connect = function()
                    return {
                        call = function(_self, namespace, method, args)
                            if namespace == "service" and method == "list" and args and args.name == "matrixbot" then
                                if ubus_running then
                                    return { matrixbot = { instances = { instance1 = { running = true } } } }
                                end
                                return {}
                            end
                            return nil
                        end,
                    }
                end,
            }
            package.loaded["ubus"] = ubus_mock -- luacheck: ignore 122
            time_stub = stub(os, "time", function()
                return 10000
            end)
            local base_open = io.open
            open_stub = stub(io, "open", function(path, mode)
                if path == "/tmp/matrixbot_backoff" and mode == "r" and backoff_content ~= nil then
                    return {
                        read = function()
                            return backoff_content
                        end,
                        close = function() end,
                    }
                end
                return base_open(path, mode)
            end)

            nixio_mock.fs.dir = function(path)
                if path == "/etc/rc.d" then
                    local i = 0
                    return function()
                        i = i + 1
                        return rc_entries[i]
                    end
                end
                return old_fs_dir(path)
            end

            nixio_mock.fs.access = function(path)
                for _, entry in ipairs(rc_entries) do
                    if path == "/etc/rc.d/" .. entry then
                        return true
                    end
                end
                return old_fs_access(path)
            end
        end)

        after_each(function()
            package.loaded["ubus"] = old_ubus -- luacheck: ignore 122
            time_stub:revert()
            open_stub:revert()
            nixio_mock.fs.dir = old_fs_dir
            nixio_mock.fs.access = old_fs_access
        end)

        it("returns stopped when service is not running", function()
            ubus_running = false
            rc_entries = { "S99matrixbot" }

            local st = state.get_status()
            assert.is_false(st.running)
            assert.is_true(st.enabled)
            assert.are.equal("stopped", st.state)
        end)

        it("returns starting when running without poller pid file", function()
            ubus_running = true

            local st = state.get_status()
            assert.is_true(st.running)
            assert.is_false(st.enabled)
            assert.are.equal("starting", st.state)
        end)

        it("returns running with uptime when poller pid exists", function()
            ubus_running = true
            nixio_mock.fs_stats["/var/run/matrixbot_poller.pid"] = { mtime = 6340 }

            local st = state.get_status()
            assert.is_true(st.running)
            assert.are.equal("running", st.state)
            assert.are.equal(3660, st.uptime_sec)
            assert.are.equal(" (Uptime: 1h 1m)", state.format_uptime(st.uptime_sec))
        end)

        it("returns backoff with parsed seconds when backoff file exists", function()
            ubus_running = true
            nixio_mock.fs_stats["/tmp/matrixbot_backoff"] = { mtime = 9990 }
            backoff_content = "40\n"

            local st = state.get_status()
            assert.is_true(st.running)
            assert.are.equal("backoff", st.state)
            assert.are.equal(40, st.backoff_sec)
        end)
    end)
end)
