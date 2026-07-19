-- luacheck: push ignore 121 122
package.loaded["ssl.https"] = require("tests.mocks.ssl_https")
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["ltn12"] = require("tests.mocks.ltn12")
package.loaded["cjson"] = require("tests.mocks.cjson")
-- luacheck: pop

local http = require("matrixbot.transport.http")
local https_mock = require("tests.mocks.ssl_https")

describe("http transport", function()
    local cfg = {
        main = {
            url = "https://matrix.example",
            token = "fake",
            bot_user = "@bot:matrix.example",
        },
    }
    local original_request = http.request

    before_each(function()
        https_mock.next_response = nil
        https_mock.next_code = 200
        https_mock.next_error = nil
        http.request = original_request
    end)

    after_each(function()
        http.request = original_request
    end)

    it("should handle valid JSON response", function()
        https_mock.next_response = '{"success": true}'
        local res = http.request(cfg, "GET", "/test")
        assert.is_table(res)
        assert(res)
        assert.is_true(res.success)
    end)

    it("should handle malformed JSON gracefully", function()
        https_mock.next_response = '{"success": true'
        local res = http.request(cfg, "GET", "/test")
        assert.is_nil(res)
    end)

    it("should handle HTTP 429 rate limit safely", function()
        https_mock.next_code = 429
        https_mock.next_response = '{"error": "Rate limit exceeded", "retry_after_ms": 1000}'
        local res = http.request(cfg, "GET", "/test")
        assert.is_nil(res)
    end)

    it("should handle https request crash gracefully", function()
        https_mock.next_error = "DNS resolution failed"
        local res = http.request(cfg, "GET", "/test")
        assert.is_nil(res)
    end)

    it("should send message successfully", function()
        https_mock.next_response = '{"event_id": "$event123"}'
        local success = http.send_message(cfg, "!room:matrix.example", "Hello")
        assert.is_true(success)
    end)

    it("should forward m.room.encrypted events to the callback", function()
        local call_index = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        http.request = function(_, _, endpoint)
            call_index = call_index + 1
            if call_index == 1 then
                return { next_batch = "batch1" }
            elseif call_index == 2 then
                return {
                    next_batch = "batch2",
                    rooms = {
                        join = {
                            ["!room:matrix.example"] = {
                                timeline = {
                                    events = {
                                        {
                                            type = "m.room.encrypted",
                                            sender = "@admin:matrix.example",
                                            content = {},
                                        },
                                        {
                                            type = "m.room.message",
                                            sender = "@admin:matrix.example",
                                            content = { body = "uptime" },
                                        },
                                        {
                                            type = "m.room.encrypted",
                                            sender = "@bot:matrix.example",
                                            content = {},
                                        },
                                    },
                                },
                            },
                        },
                    },
                }
            end
            error("stop")
        end

        local events = {}
        local ok, err = pcall(function()
            http.poll(cfg, function(room_id, event)
                table.insert(events, { room_id = room_id, event = event })
            end)
        end)

        assert.is_false(ok)
        assert.matches("stop", err)
        assert.are.equal(2, #events)
        assert.are.equal("m.room.encrypted", events[1].event.type)
        assert.are.equal("m.room.message", events[2].event.type)
        assert.are.equal("!room:matrix.example", events[1].room_id)
    end)
end)
