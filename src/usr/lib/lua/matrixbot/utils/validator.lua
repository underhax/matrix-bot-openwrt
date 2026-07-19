local logger = require("matrixbot.utils.logger")
local nixio = require("nixio")

local M = {}

local fs = nixio.fs
if not fs then
    local ok, nixio_fs = pcall(require, "nixio.fs")
    if ok then
        fs = nixio_fs
    end
end

local function split(str, delim)
    local t = {}
    for part in string.gmatch(str, "([^" .. delim .. "]+)") do
        table.insert(t, part)
    end
    return t
end

function M.is_ipv4(ip)
    if not ip or ip:match("[^%d%.]") then
        return false
    end
    local parts = split(ip, "%.")
    if #parts ~= 4 then
        return false
    end
    for _, part in ipairs(parts) do
        local num = tonumber(part)
        if not num or num < 0 or num > 255 then
            return false
        end
        if tostring(num) ~= part then
            return false
        end
    end
    return true
end

function M.is_ipv6(ip)
    if not ip or ip:match("[^%x%:]") then
        return false
    end
    if ip:match("::.*::") or ip:match(":::") then
        return false
    end
    if ip:sub(1, 1) == ":" and ip:sub(2, 2) ~= ":" then
        return false
    end
    if ip:sub(-1) == ":" and ip:sub(-2, -1) ~= "::" then
        return false
    end

    local parts = split(ip, ":")
    if #parts > 8 then
        return false
    end
    for _, part in ipairs(parts) do
        if #part > 4 then
            return false
        end
    end
    return true
end

function M.is_domain(domain)
    if not domain or domain == "" then
        return false
    end
    if domain:match("[^%w%.%-]") then
        return false
    end
    if domain:match("%.%.") or domain:match("%-%-") then
        return false
    end
    if domain:sub(1, 1) == "." or domain:sub(-1) == "." then
        return false
    end
    if domain:sub(1, 1) == "-" or domain:sub(-1) == "-" then
        return false
    end
    return true
end

function M.is_domain_ip(val)
    if not val or val == "" then
        return false
    end
    if val:find(":") then
        return M.is_ipv6(val)
    elseif val:match("[^%d%.]") then
        return M.is_domain(val)
    else
        return M.is_ipv4(val) or M.is_domain(val)
    end
end

function M.is_port(port)
    if not port or port == "" then
        return false
    end
    if port:match("[^%d]") then
        return false
    end
    local p = tonumber(port)
    if not p or p < 1 or p > 65535 then
        return false
    end
    return true
end

function M.is_domain_port(val)
    if not val or val == "" then
        return false
    end
    local host, port = val, nil

    if val:match("^%[.*%]:%d+$") then
        host = val:match("^%[(.*)%]:%d+$")
        port = val:match(":(%d+)$")
        if not M.is_ipv6(host) then
            return false
        end
    elseif val:match("^%[.*%]$") then
        host = val:match("^%[(.*)%]$")
        if not M.is_ipv6(host) then
            return false
        end
    elseif val:match("^[^:]+:%d+$") then
        host = val:match("^([^:]+)")
        port = val:match(":(%d+)$")
    end

    if not M.is_domain_ip(host) then
        return false
    end
    if port and not M.is_port(port) then
        return false
    end
    return true
end

function M.validate_url(url)
    if not url or url == "" then
        logger.error("FATAL: URL is empty.")
        return false
    end

    local protocol, body = url:match("^(https?://)(.+)$")
    if not protocol or not body then
        logger.error("FATAL: URL must start with 'http://' or 'https://'.")
        return false
    end

    if not M.is_domain_port(body) then
        logger.error("FATAL: URL domain/IP is invalid.")
        return false
    end
    return true
end

function M.validate_token(token)
    if not token or token == "" then
        logger.error("FATAL: Access token is empty.")
        return false
    end
    if not token:match("^syt_") and not token:match("^mct_") then
        logger.error("FATAL: Access token must start with 'syt_' or 'mct_'.")
        return false
    end
    if token:match("[^%w_]") then
        logger.error("FATAL: Access token contains invalid characters.")
        return false
    end
    return true
end

local function validate_matrix_localpart(localpart, var_name)
    if not localpart or localpart == "" then
        logger.error(string.format("FATAL: %s has missing localpart or domain.", var_name))
        return false
    end

    if localpart:match("[^%w%.%_%=/%-]") then
        logger.error(string.format("FATAL: %s localpart contains invalid characters.", var_name))
        return false
    end

    return true
end

local function validate_matrix_user_id(val, var_name)
    if not val or val == "" then
        logger.error(string.format("FATAL: %s is empty.", var_name))
        return false
    end

    if val:sub(1, 1) ~= "@" then
        logger.error(string.format("FATAL: %s must start with '@'.", var_name))
        return false
    end

    local body = val:sub(2)
    local localpart, serverpart = body:match("^([^:]+):(.+)$")
    if not localpart or not serverpart then
        logger.error(string.format("FATAL: %s has missing localpart or domain.", var_name))
        return false
    end

    if not validate_matrix_localpart(localpart, var_name) then
        return false
    end

    if not M.is_domain_port(serverpart) then
        logger.error(string.format("FATAL: %s domain/IP is invalid.", var_name))
        return false
    end

    return true
end

local function validate_matrix_room_id(val, var_name)
    if not val or val == "" then
        logger.error(string.format("FATAL: %s is empty.", var_name))
        return false
    end

    if val:sub(1, 1) ~= "!" then
        logger.error(string.format("FATAL: %s must start with '!'.", var_name))
        return false
    end

    local body = val:sub(2)
    local localpart = body
    local serverpart = nil

    if body:find(":", 1, true) then
        local matched_localpart, matched_serverpart = body:match("^([^:]+):(.+)$")
        if not matched_localpart or not matched_serverpart then
            logger.error(string.format("FATAL: %s has missing localpart or domain.", var_name))
            return false
        end
        localpart = matched_localpart
        serverpart = matched_serverpart
    end

    if not validate_matrix_localpart(localpart, var_name) then
        return false
    end

    if serverpart and not M.is_domain_port(serverpart) then
        logger.error(string.format("FATAL: %s domain/IP is invalid.", var_name))
        return false
    end

    return true
end

function M.validate_matrix_user(val, var_name)
    if not val or val == "" then
        return true
    end
    return validate_matrix_user_id(val, var_name)
end

function M.validate_matrix_room(val, var_name)
    if not val or val == "" then
        return true
    end
    return validate_matrix_room_id(val, var_name)
end

function M.validate_mac(mac, var_name)
    if not mac or mac == "" then
        return true
    end
    if not mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        logger.error(string.format("FATAL: %s is not a valid MAC address.", var_name))
        return false
    end
    return true
end

function M.validate_domain_ip_value(val, var_name)
    if not val or val == "" then
        return true
    end
    if not M.is_domain_ip(val) then
        logger.error(string.format("FATAL: %s contains invalid domain/IP structure.", var_name))
        return false
    end
    return true
end

function M.validate_port_value(val, var_name)
    if not val or val == "" then
        return true
    end
    if not M.is_port(val) then
        logger.error(string.format("FATAL: %s must be between 1 and 65535.", var_name))
        return false
    end
    return true
end

function M.validate_ssh_user(val, var_name)
    if not val or val == "" then
        return true
    end
    if val:match("[^%w%._%-]") then
        logger.error(string.format("FATAL: %s contains invalid characters.", var_name))
        return false
    end
    return true
end

function M.validate_ssh_key_path(val, var_name)
    if not val or val == "" then
        return true
    end
    if val:match("[^%w%._/%-~]") then
        logger.error(string.format("FATAL: %s contains invalid characters.", var_name))
        return false
    end
    return true
end

function M.validate_secure_file(path, var_name)
    if not path or path == "" then
        return true
    end
    if not fs or not fs.stat then
        logger.error(string.format("FATAL: Cannot stat %s.", var_name))
        return false
    end

    local stat = fs.stat(path)
    if not stat or stat.uid ~= 0 or type(stat.modedec) ~= "number" then
        logger.error(string.format("FATAL: %s must be owned by root with mode 600 or 400.", var_name))
        return false
    end

    if stat.modedec ~= 600 and stat.modedec ~= 400 then
        logger.error(string.format("FATAL: %s must be owned by root with mode 600 or 400.", var_name))
        return false
    end

    return true
end

function M.validate_path_list(list, var_name)
    if not list or type(list) ~= "table" then
        return true
    end
    for _, item in ipairs(list) do
        if item:match("[^%w%_%-%./]") then
            logger.error(string.format("FATAL: %s contains invalid characters.", var_name))
            return false
        end
    end
    return true
end

return M
