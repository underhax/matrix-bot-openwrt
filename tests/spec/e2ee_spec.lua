-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["cjson"] = require("tests.mocks.cjson")
-- luacheck: pop

-- luacheck: push ignore 113
local rawset = rawset
-- luacheck: pop
local e2ee = require("matrixbot.transport.e2ee")
local nixio_mock = require("tests.mocks.nixio")

describe("e2ee transport", function()
    local cfg

    before_each(function()
        cfg = {
            e2ee = {
                mode = "ssh",
                ssh_host = "192.168.1.10",
                ssh_port = "22",
                ssh_user = "router",
                ssh_key = "/root/.ssh/router-matrix",
                data_dir = "",
            },
        }
        nixio_mock.reset()
    end)

    it("should include --html flag in send_message", function()
        nixio_mock.next_fork_results = { 0, 0 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(_code)
            exit_called = true
        end)

        e2ee.send_message_async(cfg, "!room1:matrix.example", "Hello World")

        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)

        assert.is_true(1 == #nixio_mock.exec_calls)
        local args = nixio_mock.exec_calls[1]
        assert.is_true("ssh" == args[1])
        local last_arg = args[#args]
        assert.matches("--html", last_arg)
        local expected = "matrix%-cli %-%-mode send %-%-json %-%-rooms "
            .. "'!room1:matrix.example' %-%-message 'Hello World' %-%-html"
        assert.matches(expected, last_arg)
    end)

    it("should include --html flag in send_message_checked", function()
        nixio_mock.next_fork_results = { 0 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(_code)
            exit_called = true
        end)

        e2ee.send_message(cfg, "!room1:matrix.example", "Hello HTML")

        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)
        assert.is_true(1 == #nixio_mock.exec_calls)
        local args = nixio_mock.exec_calls[1]
        local last_arg = args[#args]
        assert.matches("--html", last_arg)
    end)

    it("should gracefully parse dirty JSON responses from matrix-cli", function()
        nixio_mock.next_fork_results = { 123 }

        local dirty_json = "Warning: Permanently added '192.168.1.10' to the list of known hosts.\\n"
            .. "Welcome to Ubuntu 20.04!\\n"
            .. '[ { "room_id": "!room1:matrix.example", "encrypted": true } ]\\n'

        local read_count = 0
        local old_pipe = nixio_mock.pipe
        ---@diagnostic disable-next-line: duplicate-set-field
        nixio_mock.pipe = function()
            local r, w = old_pipe()
            r.read = function()
                if read_count == 0 then
                    read_count = 1
                    return dirty_json
                end
                return nil
            end
            return r, w
        end

        local cjson_mock = require("tests.mocks.cjson")
        local old_decode = cjson_mock.decode
        ---@diagnostic disable-next-line: duplicate-set-field
        cjson_mock.decode = function(str)
            if str:match("encrypted") then
                return { { room_id = "!room1:matrix.example", encrypted = true } }
            end
            return old_decode(str)
        end

        local result = e2ee.get_rooms_encryption_status(cfg, { "!room1:matrix.example" })

        cjson_mock.decode = old_decode
        nixio_mock.pipe = old_pipe

        assert.is_not_nil(result)
        if result then
            assert.is_true(result["!room1:matrix.example"])
        end
    end)

    it("should exponentially backoff when SSH fails to connect", function()
        nixio_mock.next_fork_results = { 123, 123, 123, 123, 123, 123, 123 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(_code)
            exit_called = true
            error("mock_exit")
        end)

        local original_time = os.time
        rawset(os, "time", function()
            return 10000
        end)

        local iteration = 0
        local old_pipe = nixio_mock.pipe
        ---@diagnostic disable-next-line: duplicate-set-field
        nixio_mock.pipe = function()
            local r, w = old_pipe()
            r.read = function()
                iteration = iteration + 1
                if iteration == 6 then
                    return "Permission denied (publickey).\n"
                end
                return nil
            end
            return r, w
        end

        local _, err = pcall(function()
            e2ee.poll(cfg, function() end)
        end)

        nixio_mock.pipe = old_pipe
        rawset(os, "time", original_time)
        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)
        assert.is_string(err)
        if type(err) == "string" then
            assert.are.equal("mock_exit", err:match("mock_exit"))
        end

        assert.is_true(#nixio_mock.nanosleep_calls >= 5)
        assert.are.equal(5, nixio_mock.nanosleep_calls[1].sec)
        assert.are.equal(10, nixio_mock.nanosleep_calls[2].sec)
        assert.are.equal(20, nixio_mock.nanosleep_calls[3].sec)
        assert.are.equal(40, nixio_mock.nanosleep_calls[4].sec)
        assert.are.equal(80, nixio_mock.nanosleep_calls[5].sec)
    end)

    it("should build correct local_bin commands in send_message_async", function()
        cfg.e2ee.mode = "local"
        cfg.e2ee.local_bin = "/usr/bin/matrix-cli"
        cfg.e2ee.local_data_dir = "/mnt/sda1/data"
        nixio_mock.next_fork_results = { 0, 0 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(_code)
            exit_called = true
            error("mock_exit")
        end)

        pcall(function()
            e2ee.send_message_async(cfg, "!room1:matrix.example", "Hello Local")
        end)

        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)
        assert.is_true(1 == #nixio_mock.exec_calls)
        local args = nixio_mock.exec_calls[1]
        assert.is_true("/usr/bin/matrix-cli" == args[1])
        assert.are.equal("-data-dir", args[2])
        assert.are.equal("/mnt/sda1/data", args[3])
        assert.are.equal("--mode", args[4])
        assert.are.equal("send", args[5])
        assert.are.equal("--json", args[6])
        assert.are.equal("--rooms", args[7])
        assert.are.equal("!room1:matrix.example", args[8])
        assert.are.equal("--message", args[9])
        assert.are.equal("Hello Local", args[10])
        assert.are.equal("--html", args[11])
    end)

    it("should build correct local_bin command in get_rooms_encryption_status", function()
        cfg.e2ee.mode = "local"
        cfg.e2ee.local_bin = "/usr/bin/matrix-cli"
        cfg.e2ee.local_data_dir = "/mnt/sda1/data"
        nixio_mock.next_fork_results = { 0, 0 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(_code)
            exit_called = true
            error("mock_exit")
        end)

        pcall(function()
            e2ee.get_rooms_encryption_status(cfg, { "!room1:matrix.example" })
        end)

        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)
        assert.is_true(1 == #nixio_mock.exec_calls)
        local args = nixio_mock.exec_calls[1]
        assert.is_true("/usr/bin/matrix-cli" == args[1])
        assert.are.equal("-data-dir", args[2])
        assert.are.equal("/mnt/sda1/data", args[3])
        assert.are.equal("--mode", args[4])
        assert.are.equal("room-info", args[5])
        assert.are.equal("--json", args[6])
        assert.are.equal("--rooms", args[7])
        assert.are.equal("!room1:matrix.example", args[8])
    end)
end)
