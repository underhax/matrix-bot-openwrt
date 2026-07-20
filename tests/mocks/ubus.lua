local mock = {}

function mock.connect()
    return {
        call = function(_self, namespace, method, _args)
            if namespace == "system" and method == "info" then
                return {
                    memory = {
                        total = 128 * 1024 * 1024,
                        free = 64 * 1024 * 1024,
                        shared = 0,
                        buffered = 10 * 1024 * 1024,
                    },
                    uptime = 86400,
                    load = { 1000, 2000, 3000 },
                }
            elseif namespace == "network.wireless" and method == "status" then
                return {
                    radio0 = {
                        interfaces = {
                            { ifname = "wlan0" },
                        },
                    },
                }
            elseif namespace == "network.interface" and method == "dump" then
                return {
                    interface = {
                        {
                            interface = "lan",
                            l3_device = "br-lan",
                            ["ipv4-address"] = {
                                { address = "192.168.1.1", mask = 24 }
                            }
                        }
                    }
                }
            elseif namespace == "dhcp" and method == "ipv6leases" then
                return {
                    device = {
                        ["br-lan"] = {
                            {
                                hostname = "Desktop",
                                address = "2001:db8::101",
                                duid = "00010001"
                            }
                        }
                    }
                }
            end
            return nil
        end,
    }
end

return mock
