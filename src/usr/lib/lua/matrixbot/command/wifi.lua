local nixio = require("nixio")
local uci = require("uci")
require("nixio.fs")

local M = {}

local function get_wifi_info(cfg)
    local iwinfo = require("iwinfo")
    local lines = { "🤖 <b>WiFi Status:</b>" }

    local netdir = nixio.fs.dir("/sys/class/net")
    if not netdir then
        return "❌ <b>Error:</b> Could not enumerate network interfaces"
    end

    local ifaces = {}
    for ifname in netdir do
        table.insert(ifaces, ifname)
    end
    table.sort(ifaces)

    local found = false
    for _, ifname in ipairs(ifaces) do
        local t = iwinfo.type(ifname)
        if t and iwinfo[t] then
            found = true
            local assoc = iwinfo[t].assoclist(ifname)
            local chan = iwinfo[t].channel(ifname) or 0
            local ssid_val = iwinfo[t].ssid(ifname)
            local ssid = (ssid_val and ssid_val ~= "" and ssid_val ~= "unknown") and ssid_val or "Hidden"
            local bssid = iwinfo[t].bssid(ifname) or "Unknown"
            local rate_raw = iwinfo[t].bitrate(ifname)
            local rate = rate_raw and string.format("%.1f Mbit/s", rate_raw / 1000) or "Unknown"
            local icon = chan > 14 and "🚀 5G" or "📡 2.4G"

            local enc_info = iwinfo[t].encryption(ifname)
            local enc = enc_info and enc_info.description or "Unknown"
            local enc_live = enc
            if enc_live:match("WPA3%-SAE") and enc_live:match("WPA2%-PSK") then
                enc_live = "WPA2-PSK/WPA3-SAE Mixed Mode"
            elseif enc_live:match("WPA3%-SAE") then
                enc_live = "WPA3-SAE"
            elseif enc_live:match("WPA2%-PSK") and enc_live:match("WPA%-PSK") then
                enc_live = "WPA-PSK/WPA2-PSK Mixed Mode"
            elseif enc_live:match("WPA2%-PSK") then
                enc_live = "WPA2-PSK"
            end

            local mode_raw = iwinfo[t].mode(ifname)
            local mode = mode_raw or "Unknown"
            if mode == "AP" or mode == "Access Point" then
                mode = "Master"
            end
            if mode == "Client" or mode == "Managed" then
                mode = "Client"
            end

            local uci_key = nil
            local uci_ocv = "0"
            local target_device = nil

            local cursor = uci.cursor()
            cursor:foreach("wireless", "wifi-iface", function(s)
                if s.ifname == ifname or (ssid_val and s.ssid == ssid_val) then
                    target_device = s.device
                    if s.key and s.key ~= "" and s.key ~= "-" then
                        uci_key = s.key
                    end
                    if s.ocv and s.ocv ~= "" then
                        uci_ocv = s.ocv
                    end
                end
            end)

            local uci_country = nil
            if target_device then
                uci_country = cursor:get("wireless", target_device, "country")
            end

            local key = "********"
            if cfg.features and cfg.features.wifi_show_key and uci_key then
                key = uci_key
            end

            local clients = 0
            if assoc then
                for _ in pairs(assoc) do
                    clients = clients + 1
                end
            end

            if cfg.features and cfg.features.wifi_detailed then
                local hw = iwinfo[t].hardware_name and iwinfo[t].hardware_name(ifname) or "Unknown"
                local country = iwinfo[t].country(ifname) or "World"
                if country == "World" and type(uci_country) == "string" and uci_country ~= "" then
                    country = uci_country
                end
                local signal_val = iwinfo[t].signal(ifname)
                local signal = signal_val and string.format("%d dBm", signal_val) or "Unknown"
                local noise_val = iwinfo[t].noise(ifname)
                local noise = noise_val and string.format("%d dBm", noise_val) or "0 dBm"
                local txpwr_val = iwinfo[t].txpower(ifname)
                local txpwr = txpwr_val and string.format("%d dBm", txpwr_val) or "Unknown"

                local htmode = target_device and cursor:get("wireless", target_device, "htmode") or ""
                local width = htmode:match("%d+") or "Legacy"
                if width ~= "Legacy" then
                    width = width .. " MHz"
                end

                local standard
                if chan > 14 then
                    if htmode:match("VHT") then
                        standard = "802.11 ac/n/a"
                    elseif htmode:match("HE") then
                        standard = "802.11 ax/ac"
                    elseif htmode:match("HT") then
                        standard = "802.11 n/a"
                    else
                        standard = "802.11 a"
                    end
                else
                    if htmode:match("HE") then
                        standard = "802.11 ax/n/g"
                    elseif htmode:match("HT") then
                        standard = "802.11 b/g/n"
                    else
                        standard = "802.11 b/g"
                    end
                end

                local freq = iwinfo[t].frequency and iwinfo[t].frequency(ifname) or 0
                local chan_str = tostring(chan)
                if freq > 0 then
                    chan_str = string.format("%d (%d MHz)", chan, freq)
                end

                table.insert(lines, string.format("<br><br><b>%s %s</b><br>", icon, ifname))
                table.insert(lines, string.format("<i>%s</i><br>", hw))
                table.insert(lines, string.format("SSID: <code>%s</code><br>", ssid))
                table.insert(lines, string.format("BSSID: %s | Country: %s<br>", bssid, country))
                table.insert(lines, string.format("Mode: %s (%s)<br>", standard, width))
                table.insert(lines, string.format("Crypt: %s<br>", enc_live))
                if key ~= "" then
                    table.insert(lines, string.format("Key: <code>%s</code><br>", key))
                end
                table.insert(lines, string.format("Clients: <b>%d</b> | OCV: %s<br>", clients, uci_ocv))
                table.insert(lines, string.format("Channel: %s<br>", chan_str))
                table.insert(lines, string.format("Tx: %s | Rate: %s<br>", txpwr, rate))
                table.insert(lines, string.format("Signal: %s | Noise: %s", signal, noise))
            else
                table.insert(lines, string.format("<br><br><b>%s</b><br>", ifname))
                table.insert(lines, string.format("SSID: <code>%s</code> (%s)<br>", ssid, mode))
                table.insert(lines, string.format("Crypt: %s<br>", enc))
                if key ~= "" then
                    table.insert(lines, string.format("Key: <code>%s</code><br>", key))
                end
                table.insert(lines, string.format("Channel: %d<br>", chan))
                table.insert(lines, string.format("Rate: %s", rate))
            end
        end
    end

    if not found then
        return "🤖 No wireless interfaces found."
    end

    return table.concat(lines, "<br>")
end

local function radio_exists(radio_name)
    local cursor = uci.cursor()
    return cursor:get("wireless", radio_name) ~= nil
end

local function radio_action(action, radio_name)
    if not radio_exists(radio_name) then
        return false
    end

    local pid = nixio.fork()
    if pid == 0 then
        local gpid = nixio.fork()
        if gpid == 0 then
            local devnull = nixio.open("/dev/null", nixio.O_RDWR)
            nixio.dup(devnull, nixio.stdout)
            nixio.dup(devnull, nixio.stderr)
            devnull:close()
            nixio.execp("wifi", action, radio_name)
            nixio.kill(nixio.getpid(), 9)
        end
        nixio.kill(nixio.getpid(), 9)
    elseif pid then
        nixio.waitpid(pid)
    end

    return true
end

function M.execute(cmd, _args, cfg)
    if cmd == "wifi_info" or cmd == "wifi" then
        return get_wifi_info(cfg)
    elseif cmd == "wifi_up_2_4" then
        if not radio_action("up", "radio0") then
            return "❌ <b>Error:</b> radio0 not found in config."
        end
        return "🤖⏳ 2.4GHz (radio0) starting..."
    elseif cmd == "wifi_down_2_4" then
        if not radio_action("down", "radio0") then
            return "❌ <b>Error:</b> radio0 not found in config."
        end
        return "🤖⏳ 2.4GHz (radio0) stopping..."
    elseif cmd == "wifi_reload_2_4" then
        if not radio_action("reload", "radio0") then
            return "❌ <b>Error:</b> radio0 not found in config."
        end
        return "🤖⏳ 2.4GHz (radio0) reloading..."
    elseif cmd == "wifi_up_5" then
        if not radio_action("up", "radio1") then
            return "❌ <b>Error:</b> radio1 not found in config."
        end
        return "🤖⏳ 5GHz (radio1) starting..."
    elseif cmd == "wifi_down_5" then
        if not radio_action("down", "radio1") then
            return "❌ <b>Error:</b> radio1 not found in config."
        end
        return "🤖⏳ 5GHz (radio1) stopping..."
    elseif cmd == "wifi_reload_5" then
        if not radio_action("reload", "radio1") then
            return "❌ <b>Error:</b> radio1 not found in config."
        end
        return "🤖⏳ 5GHz (radio1) reloading..."
    end

    return "🤖 Unknown wifi command"
end

return M
