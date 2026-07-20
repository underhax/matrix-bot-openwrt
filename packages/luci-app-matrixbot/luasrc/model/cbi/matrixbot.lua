-- luacheck: ignore 212 631
local map = Map(
    "matrixbot",
    translate("Matrix Bot"),
    translate("Configure your OpenWrt Matrix Bot.")
        .. [[<style>.cbi-value-field input[type="text"], ]]
        .. [[.cbi-value-field input[type="password"] { min-width: 350px !important; }</style>]]
)
local sys = require("luci.sys")
local http = require("luci.http")

local action = http.formvalue("cbid.matrixbot.main._action")
if action then
    if action == "start" then
        sys.call("/etc/init.d/matrixbot start >/dev/null 2>&1")
    elseif action == "restart" then
        sys.call("/etc/init.d/matrixbot restart >/dev/null 2>&1")
    elseif action == "stop" then
        sys.call("/etc/init.d/matrixbot stop >/dev/null 2>&1")
    elseif action == "enable" then
        sys.call("/etc/init.d/matrixbot enable >/dev/null 2>&1")
    elseif action == "disable" then
        sys.call("/etc/init.d/matrixbot disable >/dev/null 2>&1")
    end
    http.redirect(http.getenv("REQUEST_URI"))
end

local control_section = map:section(NamedSection, "main", "matrixbot", translate("Service Status & Control"))
control_section.anonymous = true
control_section.addremove = false

local version = control_section:option(DummyValue, "_version", translate("Package Version"))
version.rawhtml = true
version.cfgvalue = function(_self, _section)
    local v = sys.exec("apk list -I matrixbot 2>/dev/null") or ""
    local ver = v:match("^matrixbot%-([^%s]+)")
    if ver then
        v = ver
    else
        v = "Unknown"
    end
    return string.format('<span style="font-weight:bold">%s</span>', v)
end

local status = control_section:option(DummyValue, "_status", translate("Service Status"))
status.rawhtml = true
status.cfgvalue = function(_self, _section)
    local running = (sys.call("/etc/init.d/matrixbot running >/dev/null 2>&1") == 0)
    local enabled = (sys.call("/etc/init.d/matrixbot enabled >/dev/null 2>&1") == 0)

    local uptime_str = ""
    if running then
        local fs = require("nixio.fs")
        local stat = fs.stat("/var/run/matrixbot_poller.pid")
        if stat and stat.mtime then
            local diff = os.time() - stat.mtime
            local m = math.floor(diff / 60)
            local h = math.floor(m / 60)
            local d = math.floor(h / 24)
            m = m % 60
            h = h % 24
            if d > 0 then
                uptime_str = string.format(" (Uptime: %dd %dh %dm)", d, h, m)
            elseif h > 0 then
                uptime_str = string.format(" (Uptime: %dh %dm)", h, m)
            else
                uptime_str = string.format(" (Uptime: %dm)", m)
            end
        end
    end

    local stat_str = running
            and '<span style="color:green;font-weight:bold">' .. translate("Running") .. uptime_str .. "</span>"
        or '<span style="color:red;font-weight:bold">' .. translate("Stopped") .. "</span>"
    local en_str = enabled and translate("Enabled") or translate("Disabled")

    return string.format("%s (%s)", stat_str, en_str)
end

local control = control_section:option(DummyValue, "_control", translate("Service Control"))
control.rawhtml = true
-- luacheck: push ignore 631
control.cfgvalue = function(_self, _section)
    return [[
        <button class="btn cbi-button cbi-button-apply" type="submit" name="cbid.matrixbot.main._action" value="start">]] .. translate(
        "Start"
    ) .. [[</button>
        <button class="btn cbi-button cbi-button-apply" type="submit" name="cbid.matrixbot.main._action" value="restart">]] .. translate(
        "Restart"
    ) .. [[</button>
        <button class="btn cbi-button cbi-button-remove" type="submit" name="cbid.matrixbot.main._action" value="stop">]] .. translate(
        "Stop"
    ) .. [[</button>
        <span style="margin: 0 10px;"></span>
        <button class="btn cbi-button cbi-button-apply" type="submit" name="cbid.matrixbot.main._action" value="enable">]] .. translate(
        "Enable"
    ) .. [[</button>
        <button class="btn cbi-button cbi-button-remove" type="submit" name="cbid.matrixbot.main._action" value="disable">]] .. translate(
        "Disable"
    ) .. [[</button>
    ]]
end
-- luacheck: pop

local function validate_matrix_localpart(value)
    if value:match("[^%w%.%_%=/%-]") then
        return nil, translate("Localpart contains invalid characters")
    end
    return value
end

local function validate_matrix_user_id(self, value, section)
    if not value or value == "" then
        return value
    end
    if value:sub(1, 1) ~= "@" then
        return nil, translate("Must start with '@'")
    end

    local body = value:sub(2)
    local localpart, serverpart = body:match("^([^:]+):(.+)$")
    if not localpart or not serverpart then
        return nil, translate("Invalid format. Expected: @localpart:server")
    end

    local ok, err = validate_matrix_localpart(localpart)
    if not ok then
        return nil, err
    end

    return value
end

local function validate_matrix_room_id(self, value, section)
    if not value or value == "" then
        return value
    end
    if value:sub(1, 1) ~= "!" then
        return nil, translate("Must start with '!'")
    end

    local body = value:sub(2)
    local localpart = body
    if body:find(":", 1, true) then
        local matched_localpart, serverpart = body:match("^([^:]+):(.+)$")
        if not matched_localpart or not serverpart then
            return nil, translate("Invalid format. Expected: !localpart or !localpart:server")
        end
        localpart = matched_localpart
    end

    local ok, err = validate_matrix_localpart(localpart)
    if not ok then
        return nil, err
    end

    return value
end

local main_section = map:section(NamedSection, "main", "matrixbot", translate("Main Configuration"))
main_section.anonymous = true
main_section.addremove = false

local function validate_ipv4(ip)
    local octets = { ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
    if #octets ~= 4 then
        return false
    end
    for _, octet in ipairs(octets) do
        local n = tonumber(octet)
        if not n or n > 255 then
            return false
        end
    end
    return true
end

local function validate_ipv6(ip)
    if ip:sub(1, 1) == "[" and ip:sub(-1) == "]" then
        ip = ip:sub(2, -2)
    end
    if ip == "" then
        return false
    end

    local _, double_colon_count = ip:gsub("::", "")
    if double_colon_count > 1 then
        return false
    end

    local groups = {}
    for group in (ip .. ":"):gmatch("([^:]*):") do
        groups[#groups + 1] = group
    end

    if double_colon_count == 0 and #groups ~= 8 then
        return false
    end
    if #groups > 8 then
        return false
    end

    for _, hextet in ipairs(groups) do
        if #hextet > 4 then
            return false
        end
        if #hextet > 0 and hextet:match("[^%x]") then
            return false
        end
    end
    return true
end

local function validate_domain(domain)
    if domain:match("[^%w%.%-]") then
        return false
    end
    if domain:sub(1, 1) == "-" or domain:sub(-1) == "-" then
        return false
    end
    if domain:sub(1, 1) == "." or domain:sub(-1) == "." then
        return false
    end
    if domain:find("..", 1, true) then
        return false
    end
    return true
end

local function validate_port(port_str)
    if port_str:match("[^%d]") then
        return false
    end
    local n = tonumber(port_str)
    if not n or n < 1 or n > 65535 then
        return false
    end
    return true
end

local function validate_domain_ip(host)
    if host:find(":", 1, true) then
        return validate_ipv6(host)
    end
    if not host:match("[^%d%.]") then
        return validate_ipv4(host)
    end
    return validate_domain(host)
end

local function validate_domain_port(val)
    local host, port

    if val:match("^%[.+%]:%d+$") then
        host = val:match("^(%[.+%]):")
        port = val:match(":(%d+)$")
    elseif val:match("^%[.+%]$") then
        host = val
    elseif val:match("^[^:]+:[^:]+:[^:]*") then
        host = val
    elseif val:find(":", 1, true) then
        host = val:match("^(.-):([^:]+)$")
        port = val:match(":([^:]+)$")
    else
        host = val
    end

    if not validate_domain_ip(host) then
        return false
    end
    if port and not validate_port(port) then
        return false
    end
    return true
end

local url_option = main_section:option(
    Value,
    "url",
    translate("Matrix Homeserver URL"),
    translate("The Client-Server API URL. Do not use the base domain if your API is hosted on a subdomain.<br />Unsure? Check <code>https://matrix.org/.well-known/matrix/client</code> and use the <code>base_url</code>.<br />Note: Replace <code>matrix.org</code> with the domain from your <code>@user:your-matrix-domain.tld</code> ID.<br />Example: <code>https://matrix-client.matrix.org</code>")
)
url_option.size = 60
url_option.rmempty = false
function url_option.validate(_self, value, _section)
    if not value or value == "" then
        return nil, translate("Homeserver URL is required")
    end

    local body
    if value:match("^https?://") then
        body = value:gsub("^https?://", "")
    else
        return nil, translate("URL must start with 'http://' or 'https://'")
    end

    body = body:gsub("/+$", "")
    if body == "" then
        return nil, translate("URL must contain a valid hostname")
    end

    if not validate_domain_port(body) then
        return nil, translate("URL contains an invalid hostname or port")
    end

    return value
end

local bot_user_option =
    main_section:option(Value, "bot_user", translate("Bot User ID"), translate("The Matrix ID of the bot.<br />Example: <code>@mybot:your-matrix-domain.tld</code>"))
bot_user_option.size = 60
bot_user_option.rmempty = false
function bot_user_option.validate(self, value, section)
    if not value or value == "" then
        return nil, translate("Bot User ID is required")
    end
    return validate_matrix_user_id(self, value, section)
end

local token_option = main_section:option(Value, "token", translate("Access Token"))
token_option.password = true
token_option.size = 60
token_option.rmempty = false
function token_option.validate(_self, value, _section)
    if not value or value == "" then
        return nil, translate("Access token is required")
    end
    if not value:match("^syt_") and not value:match("^mct_") then
        return nil, translate("Token must start with 'syt_' or 'mct_'")
    end
    if value:match("[^%w_]") then
        return nil, translate("Token contains invalid characters")
    end
    return value
end

local admin_user_option = main_section:option(
    Value,
    "admin_user",
    translate("Admin User ID"),
    translate("The Matrix ID of the administrator. Only this user is allowed to send commands.<br />Example: <code>@admin:your-matrix-domain.tld</code>")
)
admin_user_option.size = 60
admin_user_option.rmempty = false
function admin_user_option.validate(self, value, section)
    if not value or value == "" then
        return nil, translate("Admin User ID is required")
    end
    return validate_matrix_user_id(self, value, section)
end

local admin_room_option = main_section:option(
    Value,
    "admin_room",
    translate("Admin Alert Room"),
    translate("Room ID for security alerts.<br />Examples: <code>!roomid:your-matrix-domain.tld</code> or <code>!opaque-v12_roomid</code>")
)
admin_room_option.size = 60
admin_room_option.rmempty = false
function admin_room_option.validate(self, value, section)
    if not value or value == "" then
        return nil, translate("Admin Alert Room is required")
    end
    return validate_matrix_room_id(self, value, section)
end

local rooms_option = main_section:option(
    DynamicList,
    "rooms",
    translate("Command Rooms"),
    translate("Room IDs where the bot accepts commands.<br />Examples: <code>!roomid:your-matrix-domain.tld</code> or <code>!opaque-v12_roomid</code>")
)
rooms_option.size = 60
rooms_option.rmempty = false
function rooms_option.validate(self, value, section)
    if type(value) == "table" then
        for _, entry in ipairs(value) do
            local ok, err = validate_matrix_room_id(self, entry, section)
            if not ok then
                return nil, err
            end
        end
        return value
    end
    return validate_matrix_room_id(self, value, section)
end

local debug_option = main_section:option(
    Flag,
    "debug",
    translate("Enable Debug Logging"),
    translate("Logs detailed debug info to system log (logread).")
)
debug_option.rmempty = false

local e2ee_section = map:section(NamedSection, "e2ee", "matrixbot", translate("E2EE Settings (SSH Tunnel)"))
e2ee_section.anonymous = true
e2ee_section.addremove = false

local e2ee_enabled_option = e2ee_section:option(Flag, "enabled", translate("Enable E2EE (SSH Tunnel)"))
e2ee_enabled_option.rmempty = false

local ssh_host_option = e2ee_section:option(Value, "ssh_host", translate("SSH Host"))
ssh_host_option.datatype = "host"
ssh_host_option.rmempty = true

local ssh_port_option = e2ee_section:option(Value, "ssh_port", translate("SSH Port"))
ssh_port_option.datatype = "port"
ssh_port_option.default = "22"
ssh_port_option.rmempty = false

local ssh_user_option = e2ee_section:option(Value, "ssh_user", translate("SSH User"))
ssh_user_option.rmempty = true
function ssh_user_option.validate(_self, value, _section)
    if not value or value == "" then
        return value
    end
    if value:match("[^%w%_%-%.%@]") then
        return nil, translate("SSH user contains invalid characters")
    end
    return value
end

local ssh_key_option = e2ee_section:option(Value, "ssh_key", translate("SSH Private Key Path"))
ssh_key_option.datatype = "string"
ssh_key_option.default = "/root/.ssh/router-matrix"
ssh_key_option.rmempty = true

local data_dir_option = e2ee_section:option(
    Value,
    "data_dir",
    translate("matrix-cli Data Directory"),
    translate("Optional path to the matrix-cli data directory on the remote host.<br />Example: <code>/home/bot/.config/matrix-cli</code>")
)
data_dir_option.datatype = "string"
data_dir_option.rmempty = true

local features_section = map:section(NamedSection, "features", "matrixbot", translate("Features Configuration"))
features_section.anonymous = true
features_section.addremove = false

local allowed_services_option = features_section:option(
    DynamicList,
    "svc_wanted",
    translate("Allowed Services"),
    translate("Services that can be restarted via chat. Only alphanumeric, dash, underscore.")
)
allowed_services_option.rmempty = false
function allowed_services_option.validate(_self, value, _section)
    if type(value) == "table" then
        for _, service_name in ipairs(value) do
            if service_name:match("[^%w%_%-]") then
                return nil, translate("Service name '") .. service_name .. translate("' contains invalid characters")
            end
        end
        return value
    end
    if value and value:match("[^%w%_%-]") then
        return nil, translate("Service name contains invalid characters")
    end
    return value
end

local mac_pc_option = features_section:option(
    Value,
    "mac_pc",
    translate("WOL PC MAC"),
    translate("MAC Address to wake up via 'wol_pc' command.")
)
mac_pc_option.datatype = "macaddr"
mac_pc_option.rmempty = true

local wol_interfaces_option = features_section:option(
    DynamicList,
    "wol_interfaces",
    translate("WOL Interfaces"),
    translate("List of interfaces for WOL broadcasting (defaults to br-lan if empty).")
)
wol_interfaces_option.rmempty = true

local wifi_detailed_option = features_section:option(Flag, "wifi_detailed", translate("Detailed WiFi Output"))
wifi_detailed_option.rmempty = false

local wifi_show_key_option = features_section:option(Flag, "wifi_show_key", translate("Show WiFi Key in Chat"))
wifi_show_key_option.rmempty = false

return map
