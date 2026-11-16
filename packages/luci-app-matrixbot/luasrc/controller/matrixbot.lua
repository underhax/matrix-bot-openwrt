module("luci.controller.matrixbot", package.seeall)
local M = require("luci.controller.matrixbot")

function M.index()
    if not nixio.fs.access("/etc/config/matrixbot") then
        return
    end

    local page = entry({ "admin", "services", "matrixbot" }, cbi("matrixbot"), _("Matrix Bot"), 60)
    page.dependent = true

    local status = entry({ "admin", "services", "matrixbot", "status" }, call("action_status"))
    status.dependent = true
    status.leaf = true
end

function M.action_status()
    local http = require("luci.http")
    local state = require("matrixbot.utils.state")
    local st = state.get_status()
    if st.state == "running" and st.uptime_sec then
        st.uptime_text = state.format_uptime(st.uptime_sec)
    end

    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json(st)
end
