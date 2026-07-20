local security = require("matrixbot.utils.security")

describe("security utils", function()
    local sent_messages
    local transport
    local cfg

    before_each(function()
        sent_messages = {}
        transport = {
            send_message = function(_, room_id, text)
                table.insert(sent_messages, { room_id = room_id, text = text })
                return true
            end,
        }
        cfg = {
            main = {
                admin_user = "@admin:matrix.example",
                admin_room = "!alert:matrix.example",
            },
        }
    end)

    it("authorizes the admin user without sending alerts", function()
        local ok = security.authorize_sender(
            cfg,
            transport,
            "!control:matrix.example",
            "@admin:matrix.example",
            "uptime",
            false
        )

        assert.is_true(ok)
        assert.are.equal(0, #sent_messages)
    end)

    it("sends only a security alert to admin_room for unauthorized commands", function()
        local ok = security.authorize_sender(
            cfg,
            transport,
            "!control:matrix.example",
            "@intruder:matrix.example",
            "restart network",
            false
        )

        assert.is_false(ok)
        assert.are.equal(1, #sent_messages)
        assert.are.equal("!alert:matrix.example", sent_messages[1].room_id)
        assert.matches("SECURITY WARNING", sent_messages[1].text)
        assert.matches("Unauthorized user:</b> @intruder:matrix%.example", sent_messages[1].text)
        assert.matches("matrix%.to/#/!control:matrix%.example", sent_messages[1].text)
        assert.matches("Attempted Payload:</b> <code>restart network</code>", sent_messages[1].text)
    end)

    it("uses encrypted placeholder for hidden HTTP payloads", function()
        local ok = security.authorize_sender(
            cfg,
            transport,
            "!control:matrix.example",
            "@intruder:matrix.example",
            "",
            true
        )

        assert.is_false(ok)
        assert.are.equal(1, #sent_messages)
        assert.matches("%[Encrypted Message %- Content Hidden%]", sent_messages[1].text)
    end)

    it("uses empty placeholder for missing non-encrypted payloads", function()
        local ok = security.authorize_sender(
            cfg,
            transport,
            "!control:matrix.example",
            "@intruder:matrix.example",
            nil,
            false
        )

        assert.is_false(ok)
        assert.are.equal(1, #sent_messages)
        assert.matches("%[Empty/Unknown%]", sent_messages[1].text)
    end)

    it("does not send anything when admin_room is empty", function()
        cfg.main.admin_room = ""

        local ok = security.authorize_sender(
            cfg,
            transport,
            "!control:matrix.example",
            "@intruder:matrix.example",
            "uptime",
            false
        )

        assert.is_false(ok)
        assert.are.equal(0, #sent_messages)
    end)
end)
