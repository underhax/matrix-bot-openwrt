local assert = require("luassert")
local stub = require("luassert.stub")

local luci_sys_mock = {
    exec = function(_cmd)
        return ""
    end,
}

-- luacheck: push ignore
package.loaded["luci.sys"] = luci_sys_mock

local nixio_mock = require("tests.mocks.nixio")
package.loaded["nixio"] = nixio_mock
package.loaded["nixio.fs"] = nixio_mock.fs
-- luacheck: pop

local matrix_cli = require("matrixbot.utils.matrix_cli")

describe("matrix_cli module", function()
    before_each(function()
        nixio_mock.reset()
        luci_sys_mock.exec = function(_cmd)
            return ""
        end
    end)

    it("should get arch correctly", function()
        local arch = matrix_cli.get_arch()
        assert.is_string(arch)
    end)

    it("should return correct status for supported arch", function()
        local ok, arch = matrix_cli.is_supported_arch()
        assert.is_boolean(ok)
        assert.is_string(arch)
    end)

    it("should ensure run user without errors", function()
        local ok, pw = matrix_cli.ensure_run_user("matrix-cli", "/etc/matrix-cli")
        assert.is_true(ok)
        assert(pw)
        assert.are.equal(1000, pw.uid)
    end)

    it("should fail if run user does not exist in passwd", function()
        local ok, err = matrix_cli.ensure_run_user("non-existent-user", "/etc/matrix-cli")
        assert.is_false(ok)
        assert.is_nil(err)
    end)

    it("should parse installed version correctly", function()
        nixio_mock.fs.access = function(path)
            return path == "/usr/bin/matrix-cli"
        end
        luci_sys_mock.exec = function(_cmd)
            return " v0.4.0 \n"
        end
        local ver = matrix_cli.get_installed_version()
        assert.are.equal("v0.4.0", ver)
    end)

    it("should return Unknown if version string is empty", function()
        nixio_mock.fs.access = function(path)
            return path == "/usr/bin/matrix-cli"
        end
        luci_sys_mock.exec = function(_cmd)
            return ""
        end
        local ver = matrix_cli.get_installed_version()
        assert.are.equal("Unknown", ver)
    end)

    describe("update", function()
        local exec_stub
        local old_uci
        local old_readfile
        local exec_calls
        local exec_exit_code

        before_each(function()
            old_uci = package.loaded["uci"]
            old_readfile = nixio_mock.fs.readfile
            exec_calls = {}
            exec_exit_code = 0

            package.loaded["uci"] = require("tests.mocks.uci") -- luacheck: ignore 122
            exec_stub = stub(os, "execute", function(cmd)
                table.insert(exec_calls, cmd)
                return exec_exit_code
            end)
        end)

        after_each(function()
            exec_stub:revert()
            package.loaded["uci"] = old_uci -- luacheck: ignore 122
            nixio_mock.fs.readfile = old_readfile
        end)

        it("applies ownership and permissions after successful update", function()
            exec_exit_code = 0

            local ok = matrix_cli.update()
            assert.is_true(ok)
            assert.are.equal("/usr/bin/matrix-cli update > /tmp/matrixbot_updater.log 2>&1", exec_calls[1])
            assert.are.equal("chown matrix-cli:matrix-cli /usr/bin/matrix-cli", exec_calls[2])
            assert.are.equal("chmod 500 /usr/bin/matrix-cli", exec_calls[3])
        end)

        it("returns error and skips permission changes when update fails", function()
            exec_exit_code = 1
            nixio_mock.fs.readfile = function()
                return "network timeout"
            end

            local ok, err = matrix_cli.update()
            assert.is_false(ok)
            assert.are.equal("Update failed: network timeout", err)
            assert.are.equal(1, #exec_calls)
        end)
    end)
end)
