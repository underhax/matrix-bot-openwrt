local sys = require("luci.sys")

local M = {}

local SUPPORTED_PLATFORMS = {
    ["mipsle"] = "matrix-cli-linux-mipsle-softfloat.tar.gz",
}

function M.get_arch()
    local arch
    local f = io.open("/etc/os-release", "r")
    if f then
        for line in f:lines() do
            arch = line:match('^OPENWRT_ARCH="?([^"]+)"?')
            if arch then
                break
            end
        end
        f:close()
    end

    if not arch then
        local nixio = require("nixio")
        arch = nixio.uname().machine
    end

    if arch:match("^mipsel") then
        return "mipsle"
    end
    return arch
end

function M.is_supported_arch()
    local arch = M.get_arch()
    if SUPPORTED_PLATFORMS[arch] then
        return true, arch
    end
    return false, arch
end

local function create_system_user(username)
    local lock_path = "/var/lock/matrixbot_sysuser"
    os.execute("lock " .. lock_path)

    local function _do_create()
        local f = io.open("/etc/passwd", "r")
        local prefix = username .. ":"
        local prefix_len = #prefix
        if f then
            for line in f:lines() do
                if line:sub(1, prefix_len) == prefix then
                    f:close()
                    return true
                end
            end
            f:close()
        end

        local used_uids = {}
        f = io.open("/etc/passwd", "r")
        if f then
            for line in f:lines() do
                local uid_str = line:match("^[^:]+:[^:]+:(%d+)")
                local uid = tonumber(uid_str)
                if uid then
                    used_uids[uid] = true
                end
            end
            f:close()
        end

        local uid = 1000
        while used_uids[uid] do
            uid = uid + 1
        end

        local entries = {
            { "/etc/passwd", string.format("%s:x:%d:%d:%s:/var/empty:/bin/false\n", username, uid, uid, username) },
            { "/etc/group", string.format("%s:x:%d:\n", username, uid) },
            { "/etc/shadow", string.format("%s:*:0:0:99999:7:::\n", username) },
        }

        for _, entry in ipairs(entries) do
            local ef = io.open(entry[1], "a")
            if ef then
                ef:write(entry[2])
                ef:close()
            else
                return false
            end
        end
        return true
    end

    local status, result = pcall(_do_create)
    os.execute("lock -u " .. lock_path)

    if not status or not result then
        return false
    end

    return os.execute("id " .. username .. " >/dev/null 2>&1") == 0
end

function M.ensure_run_user(run_user, data_dir)
    local nok, nixio = pcall(require, "nixio")

    if nok and type(nixio.getpwnam) == "function" then
        local pw = nixio.getpwnam(run_user)
        if not pw and run_user == "matrix-cli" then
            create_system_user("matrix-cli")
            pw = nixio.getpwnam("matrix-cli")
        end
        if not pw then
            return false
        end
        if type(data_dir) == "string" and data_dir ~= "" and not nixio.fs.access(data_dir) then
            nixio.fs.mkdir(data_dir, 700)
            nixio.fs.chown(data_dir, pw.uid, pw.gid)
            nixio.fs.chmod(data_dir, 700)
        end
        return true, pw
    end

    local user_exists = os.execute("id " .. run_user .. " >/dev/null 2>&1") == 0
    if not user_exists and run_user == "matrix-cli" then
        create_system_user("matrix-cli")
        user_exists = os.execute("id matrix-cli >/dev/null 2>&1") == 0
    end
    if not user_exists then
        return false
    end
    if type(data_dir) == "string" and data_dir ~= "" then
        os.execute(string.format("mkdir -p %s", data_dir))
        os.execute(string.format("chown %s:%s %s", run_user, run_user, data_dir))
        os.execute(string.format("chmod 700 %s", data_dir))
    end
    return true
end

function M.get_installed_version()
    local fs = require("nixio.fs")
    if not fs.access("/usr/bin/matrix-cli") then
        return nil
    end
    local ver = sys.exec("/usr/bin/matrix-cli version 2>&1"):gsub("%s+", "")
    if ver == "" then
        return "Unknown"
    end
    return ver
end

local function fetch_github_release()
    local cache_file = "/tmp/matrixbot_github_latest.json"
    local fs = require("nixio.fs")
    local cjson = require("cjson")

    local stat = fs.stat(cache_file)
    if stat and stat.mtime and (os.time() - stat.mtime) < 43200 then
        local content = fs.readfile(cache_file)
        if content and content ~= "" then
            local ok_json, data = pcall(cjson.decode, content)
            if ok_json and data then
                return true, data
            end
        end
    end

    local endpoint = "https://api.github.com/repos/underhax/matrix-cli/releases/latest"
    local https = require("ssl.https")
    local ltn12 = require("ltn12")

    local resp_body = {}
    local ok, _, code = pcall(https.request, {
        url = endpoint,
        method = "GET",
        headers = { ["User-Agent"] = "matrixbot/installer", ["Accept"] = "application/json" },
        sink = ltn12.sink.table(resp_body),
        protocol = "any",
    })

    if not ok or code ~= 200 then
        return false, "Failed to fetch GitHub API"
    end

    local json_str = table.concat(resp_body)
    local ok_json, data = pcall(cjson.decode, json_str)
    if not ok_json or not data then
        return false, "Invalid JSON from GitHub"
    end

    fs.writefile(cache_file, json_str)
    return true, data
end

function M.get_latest_version()
    local ok, data_or_err = fetch_github_release()
    if not ok then
        return nil, data_or_err
    end

    if not data_or_err.tag_name then
        return nil, "Missing tag_name in GitHub response"
    end

    return data_or_err.tag_name
end

function M.install()
    local https = require("ssl.https")
    local ltn12 = require("ltn12")

    local ok, data_or_err = fetch_github_release()
    if not ok then
        return false, data_or_err
    end

    local data = data_or_err
    if not data.assets then
        return false, "Missing assets in GitHub response"
    end

    local arch = M.get_arch()
    local target_name = SUPPORTED_PLATFORMS[arch]

    if not target_name then
        return false, "Unsupported architecture for pre-compiled binary: " .. tostring(arch)
    end
    local dl_url
    local expected_digest

    for _, asset in ipairs(data.assets) do
        if asset.name == target_name then
            dl_url = asset.browser_download_url
            expected_digest = asset.digest
            break
        end
    end

    if not dl_url or not expected_digest then
        return false, "Asset or checksum not found in GitHub API for " .. target_name
    end

    local archive_path = "/tmp/matrix-cli.tar.gz"
    os.remove(archive_path)

    local dl_req_url = dl_url
    local redirects = 0
    local dl_success = false
    while redirects < 5 do
        local f = io.open(archive_path, "wb")
        if not f then
            return false, "Failed to open file for writing"
        end

        local req = {
            url = dl_req_url,
            method = "GET",
            headers = { ["User-Agent"] = "matrixbot/installer" },
            sink = ltn12.sink.file(f),
            protocol = "any",
            redirect = false,
        }
        local req_ok, _, req_code, headers = pcall(https.request, req)

        if req_ok and req_code == 200 then
            dl_success = true
            break
        elseif req_ok and (req_code == 301 or req_code == 302) and headers.location then
            dl_req_url = headers.location
            redirects = redirects + 1
        else
            os.remove(archive_path)
            return false, "Download failed with code " .. tostring(req_code)
        end
    end

    if not dl_success then
        os.remove(archive_path)
        return false, "Download failed after redirects"
    end

    local f_hash = io.popen("sha256sum " .. archive_path .. " 2>/dev/null", "r")
    if not f_hash then
        os.remove(archive_path)
        return false, "Failed to execute sha256sum"
    end
    local hash_output = f_hash:read("*a")
    f_hash:close()

    local actual_sha256 = hash_output:match("^(%x+)")
    if not actual_sha256 then
        os.remove(archive_path)
        return false, "Failed to parse sha256sum output"
    end
    local clean_expected = expected_digest:gsub("^sha256:", "")
    if actual_sha256 ~= clean_expected then
        os.remove(archive_path)
        return false, "SHA256 mismatch! Expected: " .. tostring(clean_expected) .. ", got: " .. tostring(actual_sha256)
    end

    local res_tar = os.execute(string.format("tar -xzf %q -C /tmp/", archive_path))
    if res_tar ~= 0 then
        os.remove(archive_path)
        return false, "Failed to extract archive"
    end

    os.execute("mv /tmp/matrix-cli /usr/bin/matrix-cli")

    local uci = require("uci")
    local cursor = uci.cursor()
    local run_user = cursor:get("matrixbot", "e2ee", "run_user") or "matrix-cli"
    local data_dir = cursor:get("matrixbot", "e2ee", "local_data_dir") or "/etc/matrix-cli"

    local user_ok = M.ensure_run_user(run_user, data_dir)
    if user_ok then
        os.execute(string.format("chown %s:%s /usr/bin/matrix-cli", run_user, run_user))
    end
    os.execute("chmod 500 /usr/bin/matrix-cli")
    os.remove(archive_path)

    return true, "Successfully installed " .. (data.tag_name or "latest")
end

function M.update()
    local log_file = "/tmp/matrixbot_updater.log"
    local exit_code = os.execute("/usr/bin/matrix-cli update > " .. log_file .. " 2>&1")
    if exit_code ~= 0 then
        local fs = require("nixio.fs")
        local err = fs.readfile(log_file) or "Unknown error"
        return false, "Update failed: " .. err
    end
    return true
end

return M
