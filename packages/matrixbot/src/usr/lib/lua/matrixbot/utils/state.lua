local nixio = require("nixio")
local logger = require("matrixbot.utils.logger")
local os = require("os")
local io = require("io")

local M = {}

function M.set_backoff(backoff, max_backoff)
    local f = io.open("/tmp/matrixbot_backoff", "w")
    if f then
        f:write(tostring(backoff))
        f:close()
    end

    logger.warn("Network issue, backing off for " .. tostring(backoff) .. "s")
    nixio.nanosleep(backoff, 0)

    local next_backoff = backoff * 2
    if max_backoff and next_backoff > max_backoff then
        return max_backoff
    end
    return next_backoff
end

function M.clear_backoff()
    os.remove("/tmp/matrixbot_backoff")
end

return M
