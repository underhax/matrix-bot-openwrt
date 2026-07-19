local nixio = require("nixio")

local M = {}

local function create_magic_packet(mac)
    local hex = mac:gsub(":", "")
    if #hex ~= 12 then
        return nil
    end

    local mac_bytes = hex:gsub("..", function(cc)
        return string.char(tonumber(cc, 16))
    end)

    return string.rep(string.char(0xff), 6) .. string.rep(mac_bytes, 16)
end

function M.execute(cmd, args, cfg)
    local target_mac = ""

    if cmd == "wol_pc" then
        if cfg.features.mac_pc and cfg.features.mac_pc ~= "" then
            target_mac = cfg.features.mac_pc
        else
            return "🤖 Error: MAC_PC variable is not set in config"
        end
    elseif cmd == "wol" then
        if args and args ~= "" then
            target_mac = args
        else
            return "🤖 Usage: wol AA:BB:CC:DD:EE:FF"
        end
    end

    if not target_mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return "⛔ <b>Error:</b> Invalid MAC address format. Expected: AA:BB:CC:DD:EE:FF"
    end

    local magic_packet = create_magic_packet(target_mac)
    if not magic_packet then
        return "❌ <b>Error:</b> Failed to construct magic packet."
    end

    local iface_list = cfg.features.wol_interfaces or {}
    if type(iface_list) == "string" then
        iface_list = { iface_list }
    end
    if #iface_list == 0 then
        table.insert(iface_list, "br-lan")
    end

    local success = false
    local err = ""

    for _, iface in ipairs(iface_list) do
        local sock = nixio.socket("inet", "dgram")
        if sock then
            ---@diagnostic disable-next-line: redundant-parameter
            sock:setopt("socket", "broadcast", 1)
            ---@diagnostic disable-next-line: redundant-parameter
            sock:setopt("socket", "bindtodevice", iface)
            ---@diagnostic disable-next-line: redundant-parameter
            local sent = sock:sendto(magic_packet, "255.255.255.255", 9)
            if sent then
                success = true
            else
                err = err .. "[" .. iface .. "] send failed "
            end
            sock:close()
        else
            err = err .. "[" .. iface .. "] socket fail "
        end
    end

    if success then
        if cmd == "wol_pc" then
            return "🤖 Waking PC (<code>" .. target_mac .. "</code>)..."
        else
            return "🤖 Magic packet sent to <code>" .. target_mac .. "</code>"
        end
    else
        return "❌ <b>Error:</b> Failed to send WOL.<br>Output: " .. err
    end
end

return M
