local logger = require("matrixbot.utils.logger")
local nixio = require("nixio")

local M = {}

function M.send_with_retry(cfg, transport, room_id, message, opts)
    opts = opts or {}

    local attempts = opts.attempts or 5
    local delay_sec = opts.initial_delay_sec or 2
    local sleep_before_first = opts.sleep_before_first
    if sleep_before_first == nil then
        sleep_before_first = true
    end

    local attempt = 1
    while attempt <= attempts do
        if sleep_before_first or attempt > 1 then
            nixio.nanosleep(delay_sec, 0)
        end

        if transport.send_message(cfg, room_id, message) then
            return true
        end

        delay_sec = delay_sec * 2
        attempt = attempt + 1
    end

    logger.warn("Failed to send notification after " .. tostring(attempts) .. " attempts")
    return false
end

return M
