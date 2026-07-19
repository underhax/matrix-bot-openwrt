local nixio = require("nixio")

local M = {}
local level_num = 1

function M.set_level(level)
    if level == "debug" then
        level_num = 0
    end
end

function M.info(msg)
    if not msg or level_num > 1 then
        return
    end
    nixio.syslog("info", "matrixbot: " .. tostring(msg))
end

function M.warn(msg)
    if not msg or level_num > 2 then
        return
    end
    nixio.syslog("warning", "matrixbot: " .. tostring(msg))
end

function M.error(msg)
    if not msg then
        return
    end
    nixio.syslog("err", "matrixbot: " .. tostring(msg))
end

function M.debug(msg)
    if not msg or level_num > 0 then
        return
    end
    nixio.syslog("debug", "matrixbot: " .. tostring(msg))
end

return M
