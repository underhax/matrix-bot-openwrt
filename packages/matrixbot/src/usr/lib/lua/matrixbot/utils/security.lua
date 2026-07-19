local M = {}

local function html_escape(str)
    if not str then
        return ""
    end

    return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function build_alert_message(room_id, sender, body, is_http_encrypted)
    local display_payload = body
    if not display_payload or display_payload == "" then
        if is_http_encrypted then
            display_payload = "[Encrypted Message - Content Hidden]"
        else
            display_payload = "[Empty/Unknown]"
        end
    end

    local safe_sender = html_escape(sender)
    local safe_payload = html_escape(display_payload)

    return "⚠️ <b>SECURITY WARNING!</b><br><br><b>Unauthorized user:</b> "
        .. safe_sender
        .. '<br><b>Room:</b> <a href="https://matrix.to/#/'
        .. room_id
        .. '">room</a><br><b>Attempted Payload:</b> <code>'
        .. safe_payload
        .. "</code>"
end

function M.authorize_sender(cfg, transport, room_id, sender, body, is_http_encrypted)
    if sender == cfg.main.admin_user then
        return true
    end

    local alert_dst = cfg.main.admin_room
    if alert_dst and alert_dst ~= "" then
        transport.send_message(cfg, alert_dst, build_alert_message(room_id, sender, body, is_http_encrypted))
    end

    return false
end

return M
