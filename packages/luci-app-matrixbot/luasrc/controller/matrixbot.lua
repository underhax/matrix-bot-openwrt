module("luci.controller.matrixbot", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/matrixbot") then
        return
    end

    local page = entry({ "admin", "services", "matrixbot" }, cbi("matrixbot"), _("Matrix Bot"), 60)
    page.dependent = true
end
