local sender_entry = require("matrixbot.sender.entry")

describe("sender entry", function()
    it("uses ubus first in auto mode and skips direct fallback on success", function()
        local ubus_calls = {}
        local direct_called = false
        local ubus_module = {
            connect = function()
                return {
                    call = function(_, namespace, method, args)
                        table.insert(ubus_calls, {
                            namespace = namespace,
                            method = method,
                            args = args,
                        })
                        return {}
                    end,
                }
            end,
        }

        local code = sender_entry.run({ "--room-id", "!room:matrix.example", "Hello" }, {
            ubus_module = ubus_module,
            direct_runner = function()
                direct_called = true
                return 1
            end,
        })

        assert.are.equal(0, code)
        assert.is_false(direct_called)
        assert.are.equal(1, #ubus_calls)
        assert.are.equal("matrixbot", ubus_calls[1].namespace)
        assert.are.equal("send", ubus_calls[1].method)
        assert.are.equal("!room:matrix.example", ubus_calls[1].args.room)
        assert.are.equal("Hello", ubus_calls[1].args.text)
    end)

    it("falls back to direct mode when ubus send fails", function()
        local direct_parsed = nil
        local ubus_module = {
            connect = function()
                return {
                    call = function()
                        return nil, 1
                    end,
                }
            end,
        }

        local code = sender_entry.run({ "Hello" }, {
            ubus_module = ubus_module,
            direct_runner = function(parsed)
                direct_parsed = parsed
                return 0
            end,
        })

        assert.are.equal(0, code)
        assert.is_not_nil(direct_parsed)
        ---@cast direct_parsed { mode: string, target_room: string, message: string }
        assert.are.equal("auto", direct_parsed.mode)
        assert.are.equal("", direct_parsed.target_room)
        assert.are.equal("Hello", direct_parsed.message)
    end)

    it("bypasses ubus for forced transport modes", function()
        local ubus_called = false
        local direct_parsed = nil
        local ubus_module = {
            connect = function()
                ubus_called = true
                return nil
            end,
        }

        local code = sender_entry.run({ "--http-only", "Hello" }, {
            ubus_module = ubus_module,
            direct_runner = function(parsed)
                direct_parsed = parsed
                return 0
            end,
        })

        assert.are.equal(0, code)
        assert.is_false(ubus_called)
        assert.is_not_nil(direct_parsed)
        ---@cast direct_parsed { mode: string }
        assert.are.equal("http", direct_parsed.mode)
    end)
end)
