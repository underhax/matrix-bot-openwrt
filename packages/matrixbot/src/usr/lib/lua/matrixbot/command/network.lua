local iwinfo = require("iwinfo")
local uci = require("uci")
local nixio = require("nixio")
require("nixio.fs")

local M = {}

local function get_dhcp_leases()
    local leases = {}
    local f = io.open("/tmp/dhcp.leases", "r")
    if f then
        for line in f:lines() do
            local _, mac, ip, name, _ = line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
            if mac then
                leases[mac:lower()] = { ip = ip, name = name }
            end
        end
        f:close()
    end
    return leases
end

local function get_static_leases()
    local static = {}
    local cursor = uci.cursor()
    cursor:foreach("dhcp", "host", function(s)
        if s.mac and s.name then
            local mac = type(s.mac) == "table" and s.mac[1] or s.mac
            if type(mac) == "string" then
                static[mac:lower()] = s.name
            end
        end
    end)
    return static
end

local function get_ipv6_neighbors()
    local ipv6_global = {}
    local ipv6_local = {}

    local r, w = nixio.pipe()
    if not r then
        return {}
    end

    local pid = nixio.fork()
    if pid == 0 then
        r:close()
        nixio.dup(w, nixio.stdout)
        w:close()
        local devnull = nixio.open("/dev/null", nixio.O_WRONLY)
        nixio.dup(devnull, nixio.stderr)
        devnull:close()
        nixio.execp("ip", "-6", "neigh", "show")
        nixio.kill(nixio.getpid(), 9)
    end
    w:close()

    local out = {}
    while true do
        local chunk = r:read(4096)
        if not chunk or #chunk == 0 then
            break
        end
        table.insert(out, chunk)
    end
    r:close()
    nixio.waitpid(pid)

    local full_out = table.concat(out)
    for line in full_out:gmatch("[^\r\n]+") do
        local addr, mac = line:match("^(%S+)%s+dev%s+%S+%s+lladdr%s+(%S+)")
        if addr and mac and mac ~= "00:00:00:00:00:00" then
            local lmac = mac:lower()
            if not addr:match("^fe80") then
                if not ipv6_global[lmac] then
                    ipv6_global[lmac] = addr
                end
            else
                if not ipv6_local[lmac] then
                    ipv6_local[lmac] = addr
                end
            end
        end
    end

    local result = {}
    for mac, addr in pairs(ipv6_global) do
        result[mac] = addr
    end
    for mac, addr in pairs(ipv6_local) do
        if not result[mac] then
            result[mac] = addr
        end
    end

    return result
end

local function get_bridge_devices()
    local bridges = {}
    local cursor = uci.cursor()
    cursor:foreach("network", "device", function(s)
        if s.type == "bridge" and s.name then
            bridges[s.name] = true
        end
    end)
    cursor:foreach("network", "interface", function(s)
        if s.type == "bridge" and s.device then
            bridges[s.device] = true
        end
    end)
    return bridges
end

local function get_managed_subnets()
    local subnets = {}
    local ubus = require("ubus")
    local conn = ubus.connect()
    if conn then
        local st, dump = pcall(conn.call, conn, "network.interface", "dump", {})
        if st and dump and dump.interface then
            for _, ifc in ipairs(dump.interface) do
                if ifc["ipv4-address"] and ifc.l3_device then
                    for _, addr in ipairs(ifc["ipv4-address"]) do
                        table.insert(subnets, {
                            ip = addr.address,
                            mask = addr.mask,
                            dev = ifc.l3_device,
                        })
                    end
                end
            end
        end
    end
    return subnets
end

local function ip2num(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return 0
    end
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function in_managed(ip, dev, subnets)
    local ipn = ip2num(ip)
    for _, sub in ipairs(subnets) do
        if sub.dev == dev then
            local d = 2 ^ (32 - sub.mask)
            if math.floor(ipn / d) == math.floor(ip2num(sub.ip) / d) then
                return true
            end
        end
    end
    return false
end

local function get_arp_entries()
    local arp = {}
    local bridges = get_bridge_devices()
    local subnets = get_managed_subnets()

    local f = io.open("/proc/net/arp", "r")
    if f then
        local _ = f:read("*l")
        for line in f:lines() do
            local ip, _, flags, mac, _, dev = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
            if mac and mac ~= "00:00:00:00:00:00" and flags ~= "0x0" and bridges[dev] then
                if in_managed(ip, dev, subnets) then
                    arp[mac:lower()] = { ip = ip, dev = dev }
                end
            end
        end
        f:close()
    end
    return arp
end

local function get_dhcpv6_leases()
    local dhcpv6 = {}
    local ubus = require("ubus")
    local conn = ubus.connect()
    if conn then
        local st, leases = pcall(conn.call, conn, "dhcp", "ipv6leases", {})
        if st and leases and leases.device then
            for _, devs in pairs(leases.device) do
                for _, lease in ipairs(devs) do
                    if lease.hostname and lease.address then
                        dhcpv6[lease.hostname:lower()] = lease.address
                    end
                end
            end
        end
    end
    return dhcpv6
end

local function get_wifi_macs()
    local macs = {}
    local ifaces = {}

    local netdir = nixio.fs.dir("/sys/class/net")
    if not netdir then
        return {}, {}
    end

    for ifname in netdir do
        local iw_type = iwinfo.type(ifname)
        if iw_type and iwinfo[iw_type] and iwinfo[iw_type].assoclist then
            local assoc = iwinfo[iw_type].assoclist(ifname)
            local chan = iwinfo[iw_type].channel(ifname) or 0
            local ssid_val = iwinfo[iw_type].ssid(ifname)
            local ssid = (ssid_val and ssid_val ~= "" and ssid_val ~= "unknown") and ssid_val or "Hidden"
            ifaces[ifname] = {
                ssid = ssid,
                channel = chan,
                count = 0,
            }
            if assoc then
                for mac, assoc_info in pairs(assoc) do
                    macs[mac:lower()] = {
                        ifname = ifname,
                        signal = assoc_info.signal,
                        noise = assoc_info.noise,
                    }
                    ifaces[ifname].count = ifaces[ifname].count + 1
                end
            end
        end
    end
    return macs, ifaces
end

local function format_client(mac, ip, ipv6, name, extra_info, icon)
    name = name or "Unknown"
    if name == "*" then
        name = "Unknown"
    end

    name = name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")

    local lines = {
        string.format("%s <b>%s</b>", icon, name),
        string.format(
            "IPv4: <code>%s</code>%s",
            ip or "Unknown",
            (extra_info and extra_info ~= "") and (" | " .. extra_info) or ""
        ),
    }
    if ipv6 and ipv6 ~= "" then
        table.insert(lines, string.format("IPv6: <small><code>%s</code></small>", ipv6))
    end
    table.insert(lines, string.format("Mac: <small>%s</small>", mac))

    return table.concat(lines, "<br>")
end

function M.execute(cmd, _args, _cfg)
    local leases = get_dhcp_leases()
    local static_leases = get_static_leases()
    local ipv6_neighbors = get_ipv6_neighbors()
    local dhcpv6 = get_dhcpv6_leases()
    local arp = get_arp_entries()
    local wifi_macs, wifi_ifaces = get_wifi_macs()

    local lines = {}

    local function resolve_client(mac)
        local name = ""
        if leases[mac] and leases[mac].name and leases[mac].name ~= "*" then
            name = leases[mac].name
        end
        if name == "" and static_leases[mac] then
            name = static_leases[mac]
        end

        local ipv6 = ""
        local lname = name:lower()
        if lname ~= "" and lname ~= "unknown" and dhcpv6[lname] then
            ipv6 = dhcpv6[lname]
        end
        if ipv6 == "" then
            ipv6 = ipv6_neighbors[mac] or ""
        end

        return name, ipv6
    end

    if cmd == "wifi_clients" or cmd == "clients" then
        table.insert(lines, "🤖 <b>WiFi (LAN) Clients:</b>")

        local total = 0
        local grouped = {}
        for mac, info in pairs(wifi_macs) do
            if not grouped[info.ifname] then
                grouped[info.ifname] = {}
            end
            table.insert(grouped[info.ifname], { mac = mac, info = info })
            total = total + 1
        end

        if total == 0 then
            table.insert(lines, "No wireless interfaces found or no clients.")
        else
            local sorted_ifaces = {}
            for ifname, _ in pairs(wifi_ifaces) do
                table.insert(sorted_ifaces, ifname)
            end
            table.sort(sorted_ifaces)

            for _, ifname in ipairs(sorted_ifaces) do
                local ifdata = wifi_ifaces[ifname]
                local icon = (ifdata.channel > 14) and "🚀 5G" or "📡 2.4G"
                table.insert(
                    lines,
                    string.format("<br><br><b>%s %s</b> [%s] (%d)<br>", icon, ifdata.ssid, ifname, ifdata.count)
                )

                if ifdata.count == 0 then
                    table.insert(lines, "<br><i>No clients.</i>")
                else
                    if grouped[ifname] then
                        for _, c in ipairs(grouped[ifname]) do
                            local ip = leases[c.mac] and leases[c.mac].ip or (arp[c.mac] and arp[c.mac].ip or "Unknown")
                            local name, ipv6 = resolve_client(c.mac)
                            local extra = string.format("%s dBm", tostring(c.info.signal or 0))
                            table.insert(lines, format_client(c.mac, ip, ipv6, name, extra, "<br>📱"))
                        end
                    end
                end
            end
        end
    end

    if cmd == "wired_clients" or cmd == "clients" then
        if cmd == "clients" then
            table.insert(lines, "<br><br>")
        end
        table.insert(lines, "🤖 <b>Wired (LAN) Clients:</b><br>")
        local count = 0
        for mac, info in pairs(arp) do
            if not wifi_macs[mac] then
                count = count + 1
                local name, ipv6 = resolve_client(mac)
                table.insert(lines, format_client(mac, info.ip, ipv6, name, "", "<br>🌐"))
            end
        end
        if count == 0 then
            table.insert(lines, "<br><br><i>No active wired clients found.</i><br>")
        end
    end

    return table.concat(lines, "\n")
end

return M
