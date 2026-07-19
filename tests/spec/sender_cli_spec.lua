local sender_cli = require("matrixbot.sender.cli")

describe("sender cli", function()
    local cfg
    local http_calls
    local ssh_calls
    local stderr_lines

    local function stderr_writer(chunk)
        table.insert(stderr_lines, chunk)
    end

    local function config_loader()
        return cfg
    end

    before_each(function()
        cfg = {
            main = {
                rooms = { "!room1:matrix.example", "!room2:matrix.example" },
            },
            e2ee = {
                enabled = false,
                ssh_host = "192.168.1.10",
                ssh_port = "22",
                ssh_user = "router",
                ssh_key = "/root/.ssh/router-matrix",
            },
        }
        http_calls = {}
        ssh_calls = {}
        stderr_lines = {}
    end)

    local function make_http_transport(results)
        return {
            send_message = function(_, room_id, message)
                table.insert(http_calls, { room_id = room_id, message = message })
                return table.remove(results, 1)
            end,
        }
    end

    local function make_e2ee_transport(results)
        return {
            send_message = function(_, room_id, message)
                table.insert(ssh_calls, { room_id = room_id, message = message })
                return table.remove(results, 1)
            end,
        }
    end

    it("uses ssh-only mode without http fallback", function()
        local code = sender_cli.run({ "--ssh-only", "--room-id", "!admin:matrix.example", "Hello" }, {
            stderr = stderr_writer,
            config_loader = config_loader,
            http_transport = make_http_transport({ true }),
            e2ee_transport = make_e2ee_transport({ true }),
        })

        assert.are.equal(0, code)
        assert.are.equal(1, #ssh_calls)
        assert.are.equal(0, #http_calls)
        assert.are.equal("!admin:matrix.example", ssh_calls[1].room_id)
    end)

    it("uses http-only mode without ssh attempts", function()
        cfg.e2ee.enabled = true

        local code = sender_cli.run({ "--http-only", "--room-id", "!admin:matrix.example", "Hello" }, {
            stderr = stderr_writer,
            config_loader = config_loader,
            http_transport = make_http_transport({ true }),
            e2ee_transport = make_e2ee_transport({ true }),
        })

        assert.are.equal(0, code)
        assert.are.equal(0, #ssh_calls)
        assert.are.equal(1, #http_calls)
        assert.are.equal("!admin:matrix.example", http_calls[1].room_id)
    end)

    it("falls back from ssh to http in auto mode", function()
        cfg.e2ee.enabled = true

        local code = sender_cli.run({ "--room-id", "!admin:matrix.example", "Hello" }, {
            stderr = stderr_writer,
            config_loader = config_loader,
            http_transport = make_http_transport({ true }),
            e2ee_transport = make_e2ee_transport({ false }),
        })

        assert.are.equal(0, code)
        assert.are.equal(1, #ssh_calls)
        assert.are.equal(1, #http_calls)
        assert.are.equal("!admin:matrix.example", ssh_calls[1].room_id)
        assert.are.equal("!admin:matrix.example", http_calls[1].room_id)
    end)

    it("tries configured rooms in order when room is not provided", function()
        local code = sender_cli.run({ "--http-only", "Hello" }, {
            stderr = stderr_writer,
            config_loader = config_loader,
            http_transport = make_http_transport({ false, true }),
            e2ee_transport = make_e2ee_transport({ true }),
        })

        assert.are.equal(0, code)
        assert.are.equal(2, #http_calls)
        assert.are.equal("!room1:matrix.example", http_calls[1].room_id)
        assert.are.equal("!room2:matrix.example", http_calls[2].room_id)
    end)

    it("fails when no default rooms are configured", function()
        cfg.main.rooms = {}

        local code = sender_cli.run({ "--http-only", "Hello" }, {
            stderr = stderr_writer,
            config_loader = config_loader,
            http_transport = make_http_transport({ true }),
            e2ee_transport = make_e2ee_transport({ true }),
        })

        assert.are.equal(1, code)
        assert.matches("MATRIX_ROOM_IDS is empty", table.concat(stderr_lines))
    end)
end)
