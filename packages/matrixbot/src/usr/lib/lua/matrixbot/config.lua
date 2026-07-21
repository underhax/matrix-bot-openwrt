local uci = require("uci")
local logger = require("matrixbot.utils.logger")
local validator = require("matrixbot.utils.validator")

local M = {}

local function normalize_url(url)
    if not url or url == "" then
        return url
    end
    return (url:gsub("/$", ""))
end

function M.load()
    local cursor = uci.cursor()
    local cfg = {}

    local function get_opt(section, option, default)
        local val = cursor:get("matrixbot", section, option)
        if val == nil then
            return default
        end
        return val
    end

    local function get_list(section, option, default)
        local val = cursor:get("matrixbot", section, option)
        if type(val) == "table" then
            return val
        elseif type(val) == "string" then
            return { val }
        end
        return default or {}
    end

    if not cursor:get("matrixbot", "main") then
        logger.error("UCI configuration 'matrixbot.main' not found. Ensure /etc/config/matrixbot exists.")
        return nil
    end

    cfg.main = {
        url = normalize_url(get_opt("main", "url", "")),
        token = get_opt("main", "token", ""),
        admin_room = get_opt("main", "admin_room", ""),
        bot_user = get_opt("main", "bot_user", ""),
        admin_user = get_opt("main", "admin_user", ""),
        debug = get_opt("main", "debug", "0") == "1",
        start_delay = tonumber(get_opt("main", "start_delay", "30")) or 30,
    }

    local rooms = get_list("main", "rooms")
    if #rooms == 1 and type(rooms[1]) == "string" and rooms[1]:find(" ") then
        local r_list = {}
        for r in rooms[1]:gmatch("%S+") do
            table.insert(r_list, r)
        end
        rooms = r_list
    end
    cfg.main.rooms = rooms

    cfg.e2ee = {
        enabled = get_opt("e2ee", "enabled", "0") == "1",
        ssh_host = get_opt("e2ee", "ssh_host", ""),
        ssh_port = get_opt("e2ee", "ssh_port", "22"),
        ssh_user = get_opt("e2ee", "ssh_user", ""),
        ssh_key = get_opt("e2ee", "ssh_key", ""),
        data_dir = get_opt("e2ee", "data_dir", ""),
    }

    cfg.features = {
        svc_wanted = get_list(
            "features",
            "svc_wanted",
            { "dnsmasq", "firewall", "network", "odhcpd", "cron", "uhttpd", "nginx" }
        ),
        mac_pc = get_opt("features", "mac_pc", ""),
        wol_interfaces = get_list("features", "wol_interfaces", {}),
        wifi_detailed = get_opt("features", "wifi_detailed", "0") == "1",
        wifi_show_key = get_opt("features", "wifi_show_key", "0") == "1",
    }

    local invalid = false

    if not validator.validate_url(cfg.main.url) then
        invalid = true
    end
    if not validator.validate_token(cfg.main.token) then
        invalid = true
    end
    if cfg.main.admin_room == "" then
        logger.error("FATAL: MATRIX_ROOM_ADMIN is empty.")
        invalid = true
    elseif not validator.validate_matrix_room(cfg.main.admin_room, "MATRIX_ROOM_ADMIN") then
        invalid = true
    end
    if cfg.main.bot_user == "" then
        logger.error("FATAL: MATRIX_BOT_USER is empty.")
        invalid = true
    elseif not validator.validate_matrix_user(cfg.main.bot_user, "MATRIX_BOT_USER") then
        invalid = true
    end
    if cfg.main.admin_user == "" then
        logger.error("FATAL: MATRIX_ADMIN_USER is empty.")
        invalid = true
    elseif not validator.validate_matrix_user(cfg.main.admin_user, "MATRIX_ADMIN_USER") then
        invalid = true
    end

    for _, room in ipairs(cfg.main.rooms) do
        if not validator.validate_matrix_room(room, "MATRIX_ROOM_IDS") then
            invalid = true
        end
    end

    if not validator.validate_mac(cfg.features.mac_pc, "MAC_PC") then
        invalid = true
    end
    if not validator.validate_path_list(cfg.features.svc_wanted, "SVC_WANTED") then
        invalid = true
    end
    if not validator.validate_path_list(cfg.features.wol_interfaces, "WOL_INTERFACES") then
        invalid = true
    end

    if cfg.e2ee.enabled then
        if not validator.validate_domain_ip_value(cfg.e2ee.ssh_host, "SSH_HOST") then
            invalid = true
        end
        if not validator.validate_port_value(cfg.e2ee.ssh_port, "SSH_PORT") then
            invalid = true
        end
        if not validator.validate_ssh_user(cfg.e2ee.ssh_user, "SSH_USER") then
            invalid = true
        end
        if not validator.validate_ssh_key_path(cfg.e2ee.ssh_key, "SSH_KEY") then
            invalid = true
        elseif not validator.validate_secure_file(cfg.e2ee.ssh_key, "SSH_KEY") then
            invalid = true
        end
        if
            cfg.e2ee.ssh_host ~= ""
            and not validator.validate_secure_file("/etc/matrix_bot_known_hosts", "/etc/matrix_bot_known_hosts")
        then
            invalid = true
        end
    end

    if invalid then
        logger.error("Configuration validation failed. Exiting.")
        return nil
    end

    return cfg
end

return M
