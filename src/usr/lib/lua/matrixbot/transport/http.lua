local https = require("ssl.https")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local logger = require("matrixbot.utils.logger")
local nixio = require("nixio")

local M = {}
local tx_id = 0

local function sleep(sec)
    nixio.nanosleep(sec, 0)
end

local function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

function M.request(cfg, method, endpoint, query, body, ignore_errors)
    local url = cfg.main.url .. endpoint
    if query then
        local q = {}
        for k, v in pairs(query) do
            table.insert(q, urlencode(tostring(k)) .. "=" .. urlencode(tostring(v)))
        end
        if #q > 0 then
            url = url .. "?" .. table.concat(q, "&")
        end
    end

    local resp_body = {}
    local req = {
        url = url,
        method = method,
        headers = {
            ["Authorization"] = "Bearer " .. cfg.main.token,
            ["Accept"] = "application/json",
        },
        sink = ltn12.sink.table(resp_body),
        protocol = "any",
    }

    if body then
        req.source = ltn12.source.string(body)
        req.headers["Content-Type"] = "application/json"
        req.headers["Content-Length"] = tostring(#body)
    end

    local ok, res, code, _, _ = pcall(https.request, req)
    if not ok then
        logger.error("HTTP request failed: " .. tostring(res))
        return nil
    end

    if not res then
        logger.error("HTTP error: " .. tostring(code))
        return nil
    end

    local raw_resp = table.concat(resp_body)
    local success, json = pcall(cjson.decode, raw_resp)

    if not success then
        logger.error("Failed to parse JSON response: " .. tostring(json))
        return nil
    end

    if code < 200 or code >= 300 then
        if not ignore_errors then
            local err_msg = json.error or "Unknown error"
            logger.error(string.format("API Error %s: %s", tostring(code), err_msg))
        end

        if code == 429 then
            local retry_ms = tonumber(json.retry_after_ms) or 5000
            local retry_sec = math.floor(retry_ms / 1000)
            if retry_sec < 1 then
                retry_sec = 1
            end
            logger.warn("Rate limited, sleeping for " .. tostring(retry_sec) .. " seconds")
            sleep(retry_sec)
        end
        return nil
    end

    return json
end

function M.send_message(cfg, room_id, text)
    tx_id = tx_id + 1
    local endpoint = string.format(
        "/_matrix/client/v3/rooms/%s/send/m.room.message/%s",
        urlencode(room_id),
        tostring(os.time()) .. tostring(tx_id)
    )

    local plain = string.gsub(text, "<[bB][rR][^>]*>", "\n")
    plain = string.gsub(plain, "<[^>]+>", "")

    local payload = cjson.encode({
        msgtype = "m.text",
        format = "org.matrix.custom.html",
        body = plain,
        formatted_body = text,
    })

    local res = M.request(cfg, "PUT", endpoint, nil, payload)
    if res and res.event_id then
        return true
    end
    return false
end

function M.send_message_async(cfg, room_id, text)
    local pid = nixio.fork()
    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            M.send_message(cfg, room_id, text)
            os.exit(0)
        else
            os.exit(0)
        end
    elseif pid then
        nixio.waitpid(pid)
        return true
    end
    return false
end

function M.poll(cfg, on_event)
    local next_batch = nil

    local init_res = M.request(cfg, "GET", "/_matrix/client/v3/sync", { timeout = 0 })
    if init_res and init_res.next_batch then
        next_batch = init_res.next_batch
    end

    while true do
        local query = {
            timeout = 30000,
            set_presence = "online",
        }
        if next_batch then
            query.since = next_batch
        end

        local filter = {
            room = {
                timeline = {
                    types = { "m.room.message", "m.room.encrypted" },
                },
            },
        }
        query.filter = cjson.encode(filter)

        local res = M.request(cfg, "GET", "/_matrix/client/v3/sync", query)

        if res then
            if res.next_batch then
                next_batch = res.next_batch
            end

            if res.rooms and res.rooms.join then
                for room_id, room_data in pairs(res.rooms.join) do
                    if room_data.timeline and room_data.timeline.events then
                        for _, event in ipairs(room_data.timeline.events) do
                            if
                                (event.type == "m.room.message" or event.type == "m.room.encrypted")
                                and event.sender ~= cfg.main.bot_user
                            then
                                local ok, err = pcall(on_event, room_id, event)
                                if not ok then
                                    logger.error("Event handler crashed: " .. tostring(err))
                                end
                            end
                        end
                    end
                end
            end

            sleep(1)
        else
            logger.warn("Sync failed, sleeping 5 seconds...")
            sleep(5)
        end
    end
end

return M
