local mock = {}

function mock.type(ifname)
    if ifname == "wlan0" then
        return "nl80211"
    end
    return nil
end

mock.nl80211 = {
    assoclist = function(ifname)
        if ifname == "wlan0" then
            return {
                ["aa:bb:cc:dd:ee:ff"] = {
                    signal = -50,
                    noise = -90,
                },
            }
        end
        return nil
    end,
    channel = function(ifname)
        if ifname == "wlan0" then
            return 36
        end
        return nil
    end,
    ssid = function(ifname)
        if ifname == "wlan0" then
            return "Mock_WiFi"
        end
        return nil
    end,
    info = function(ifname)
        if ifname == "wlan0" then
            return {
                channel = 36,
                ssid = "Mock_WiFi",
            }
        end
        return nil
    end,
}

return mock
