matrix_cli() {
    local MATRIX_CLI_DATA_DIR
    MATRIX_CLI_DATA_DIR=$(uci -q get matrixbot.e2ee.local_data_dir)
    if [ -z "$MATRIX_CLI_DATA_DIR" ]; then
        echo "FATAL: matrixbot.e2ee.local_data_dir is not set in UCI configuration." >&2
        return 1
    fi
    local MATRIX_CLI_USER
    MATRIX_CLI_USER=$(uci -q get matrixbot.e2ee.run_user)
    [ -z "$MATRIX_CLI_USER" ] && MATRIX_CLI_USER="matrix-cli"

    lua - "$MATRIX_CLI_USER" "$MATRIX_CLI_DATA_DIR" "$@" << 'EOF'
        local uid, gid
        local f = io.open("/etc/passwd", "r")
        if f then
            for line in f:lines() do
                local u, _, i, g = line:match("^([^:]+):([^:]*):(%d+):(%d+):")
                if u == arg[1] then
                    uid = tonumber(i)
                    gid = tonumber(g)
                    break
                end
            end
            f:close()
        end
        if not uid or not gid then
            print("FATAL: User " .. tostring(arg[1]) .. " not found in /etc/passwd!")
            os.exit(1)
        end
        local nixio = require("nixio")
        if type(nixio.setgid) ~= "function" or type(nixio.setuid) ~= "function" then
            print("FATAL: nixio.setuid/setgid are not available on this OpenWrt build.")
            os.exit(1)
        end
        if not nixio.setgid(gid) or not nixio.setuid(uid) then
            print("FATAL: Failed to drop privileges!")
            os.exit(1)
        end
        local exec_args = {"/usr/bin/matrix-cli"}
        local first_arg = arg[3]
        if first_arg ~= "version" and first_arg ~= "update" then
            table.insert(exec_args, "--data-dir")
            table.insert(exec_args, arg[2])
        end
        for i = 3, #arg do 
            table.insert(exec_args, arg[i]) 
        end
        
        nixio.execp(unpack(exec_args))
EOF
}

alias matrix-cli='matrix_cli'
