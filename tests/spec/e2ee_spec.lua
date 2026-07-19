-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["cjson"] = require("tests.mocks.cjson")
-- luacheck: pop

local e2ee = require("matrixbot.transport.e2ee")
local nixio_mock = require("tests.mocks.nixio")

describe("e2ee transport", function()
    local cfg

    before_each(function()
        cfg = {
            e2ee = {
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
        rawset(os, "exit", function(code)
            exit_called = true
        end)

        local ok = e2ee.send_message_async(cfg, "!room1:matrix.example", "Hello World")

        rawset(os, "exit", original_exit)

        assert.is_true(exit_called)

        assert.is_true(1 == #nixio_mock.exec_calls)
        local args = nixio_mock.exec_calls[1]
        assert.is_true("ssh" == args[1])
        local last_arg = args[#args]
        assert.matches("--html", last_arg)
        assert.matches("matrix%-cli %-%-mode send %-%-rooms '!room1:matrix.example' %-%-message 'Hello World' %-%-html", last_arg)
    end)

    it("should include --html flag in send_message_checked", function()
        nixio_mock.next_fork_results = { 0 }

        local original_exit = os.exit
        local exit_called = false
        rawset(os, "exit", function(code)
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
end)
