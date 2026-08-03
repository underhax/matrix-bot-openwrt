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
        mode = get_opt("e2ee", "mode", "ssh"),
        ssh_host = get_opt("e2ee", "ssh_host", ""),
        ssh_port = get_opt("e2ee", "ssh_port", "22"),
        ssh_user = get_opt("e2ee", "ssh_user", ""),
        ssh_key = get_opt("e2ee", "ssh_key", ""),
        data_dir = get_opt("e2ee", "data_dir", ""),
        local_data_dir = get_opt("e2ee", "local_data_dir", ""),
        run_user = get_opt("e2ee", "run_user", "matrix-cli"),
        run_group = get_opt("e2ee", "run_group", "matrix-cli"),
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

    if not validator.validate_matrix_homeserver_url(cfg.main.url) then
        invalid = true
    end
    if not validator.validate_token(cfg.main.token) then
        invalid = true
    end
    if cfg.main.admin_room == "" then
        logger.error("FATAL: admin_room is empty.")
        invalid = true
    elseif not validator.validate_matrix_room(cfg.main.admin_room, "admin_room") then
        invalid = true
    end
    if cfg.main.bot_user == "" then
        logger.error("FATAL: bot_user is empty.")
        invalid = true
    elseif not validator.validate_matrix_user(cfg.main.bot_user, "bot_user") then
        invalid = true
    end
    if cfg.main.admin_user == "" then
        logger.error("FATAL: admin_user is empty.")
        invalid = true
    elseif not validator.validate_matrix_user(cfg.main.admin_user, "admin_user") then
        invalid = true
    end

    for _, room in ipairs(cfg.main.rooms) do
        if not validator.validate_matrix_room(room, "rooms") then
            invalid = true
        end
    end

    if not validator.validate_mac(cfg.features.mac_pc, "mac_pc") then
        invalid = true
    end
    if not validator.validate_service_list(cfg.features.svc_wanted, "svc_wanted") then
        invalid = true
    end
    if not validator.validate_netdev_list(cfg.features.wol_interfaces, "wol_interfaces") then
        invalid = true
    end

    if cfg.e2ee.enabled then
        if cfg.e2ee.mode == "ssh" then
            if not validator.validate_domain_ip_value(cfg.e2ee.ssh_host, "ssh_host") then
                invalid = true
            end
            if not validator.validate_port_value(cfg.e2ee.ssh_port, "ssh_port") then
                invalid = true
            end
            if not validator.validate_ssh_user(cfg.e2ee.ssh_user, "ssh_user") then
                invalid = true
            end
            if not validator.validate_ssh_key_path(cfg.e2ee.ssh_key, "ssh_key") then
                invalid = true
            elseif not validator.validate_secure_file(cfg.e2ee.ssh_key, "ssh_key") then
                invalid = true
            end
            if not validator.validate_path(cfg.e2ee.data_dir, "data_dir") then
                invalid = true
            end
            if
                cfg.e2ee.ssh_host ~= ""
                and not validator.validate_secure_file("/etc/matrix_bot_known_hosts", "/etc/matrix_bot_known_hosts")
            then
                invalid = true
            end
        elseif cfg.e2ee.mode == "local" then
            if cfg.e2ee.local_data_dir == "" then
                logger.error("FATAL: Configuration option 'local_data_dir' cannot be empty.")
                invalid = true
            elseif not validator.validate_path(cfg.e2ee.local_data_dir, "local_data_dir") then
                invalid = true
            end

            local matrix_cli = require("matrixbot.utils.matrix_cli")
            local user_ok, run_user_pw = matrix_cli.ensure_run_user(cfg.e2ee.run_user, cfg.e2ee.local_data_dir)
            if not user_ok then
                logger.error("FATAL: run_user " .. tostring(cfg.e2ee.run_user) .. " not found in system.")
                invalid = true
            end

            if
                run_user_pw
                and not invalid
                and not validator.validate_secure_dir(
                    tostring(cfg.e2ee.local_data_dir),
                    run_user_pw.uid,
                    "local_data_dir"
                )
            then
                invalid = true
            end
        else
            logger.error("FATAL: e2ee mode must be 'ssh' or 'local'.")
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
