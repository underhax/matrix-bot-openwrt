-- luacheck: push ignore 121 122
package.loaded["nixio"] = require("tests.mocks.nixio")
package.loaded["nixio.fs"] = require("tests.mocks.nixio").fs
package.loaded["uci"] = require("tests.mocks.uci")
-- luacheck: pop

local nixio_mock = require("tests.mocks.nixio")
local uci_mock = require("tests.mocks.uci")
local config = require("matrixbot.config")

describe("config module", function()
    before_each(function()
        nixio_mock.reset()
        uci_mock.reset()
    end)

    it("trims trailing slash from main.url", function()
        uci_mock.data.matrixbot.main.url = "https://matrix.example/"
        local cfg = config.load()

        assert.is_not_nil(cfg)
        assert.is_table(cfg)
        ---@cast cfg { main: { url: string } }
        assert.are.equal("https://matrix.example", cfg.main.url)
    end)

    it("accepts room ids without domain suffix", function()
        uci_mock.data.matrixbot.main.admin_room = "!0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs"
        uci_mock.data.matrixbot.main.rooms = {
            "!AbCdEfGhIj:matrix-example.tld",
            "!0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs",
        }

        local cfg = config.load()
        assert.is_not_nil(cfg)
        assert.is_table(cfg)
    end)

    it("rejects empty bot_user", function()
        uci_mock.data.matrixbot.main.bot_user = ""

        assert.is_nil(config.load())
    end)

    it("rejects empty admin_user", function()
        uci_mock.data.matrixbot.main.admin_user = ""

        assert.is_nil(config.load())
    end)

    it("rejects empty admin_room", function()
        uci_mock.data.matrixbot.main.admin_room = ""

        assert.is_nil(config.load())
    end)

    it("rejects invalid ssh_host when e2ee is enabled", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_host = "bad host"

        assert.is_nil(config.load())
    end)

    it("rejects invalid ssh_port when e2ee is enabled", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_port = "70000"

        assert.is_nil(config.load())
    end)

    it("rejects invalid ssh_user when e2ee is enabled", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_user = "bad user"

        assert.is_nil(config.load())
    end)

    it("rejects insecure ssh_key permissions when e2ee is enabled", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_key = "/root/.ssh/router-matrix"
        nixio_mock.fs_stats["/root/.ssh/router-matrix"].modedec = 644

        assert.is_nil(config.load())
    end)

    it("rejects insecure known_hosts permissions when e2ee is enabled", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_host = "matrix-gateway.example"
        nixio_mock.fs_stats["/etc/matrix_bot_known_hosts"].uid = 1000

        assert.is_nil(config.load())
    end)

    it("loads wol_interfaces from config", function()
        uci_mock.data.matrixbot.features.wol_interfaces = { "br-lan", "eth1" }

        local cfg = config.load()
        assert.is_not_nil(cfg)
        assert.is_table(cfg)
        ---@cast cfg { features: { wol_interfaces: string[] } }
        assert.are.equal("br-lan", cfg.features.wol_interfaces[1])
        assert.are.equal("eth1", cfg.features.wol_interfaces[2])
    end)

    it("rejects invalid wol_interfaces entries", function()
        uci_mock.data.matrixbot.features.wol_interfaces = { "br-lan", "eth0;reboot" }

        assert.is_nil(config.load())
    end)

    it("accepts valid e2ee ssh configuration", function()
        uci_mock.data.matrixbot.e2ee.enabled = "1"
        uci_mock.data.matrixbot.e2ee.ssh_host = "192.168.1.10"
        uci_mock.data.matrixbot.e2ee.ssh_port = "22"
        uci_mock.data.matrixbot.e2ee.ssh_user = "router-admin"
        uci_mock.data.matrixbot.e2ee.ssh_key = "/root/.ssh/router-matrix"

        local cfg = config.load()
        assert.is_not_nil(cfg)
        assert.is_table(cfg)
    end)
end)
