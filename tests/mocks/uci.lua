local mock = {}

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, entry in pairs(value) do
        result[key] = clone(entry)
    end
    return result
end

local default_data = {
    matrixbot = {
        main = {
            url = "https://matrix.example",
            token = "syt_fake_token",
            admin_room = "!admin:matrix.example",
            rooms = { "!room1:matrix.example" },
            bot_user = "@bot:matrix.example",
            admin_user = "@admin:matrix.example",
            debug = "0",
        },
        e2ee = {
            enabled = "0",
        },
        features = {
            wifi_detailed = "1",
        },
    },
    wireless = {
        radio0 = {
            [".type"] = "wifi-device",
        },
        radio1 = {
            [".type"] = "wifi-device",
        },
    },
}

function mock.reset()
    mock.data = clone(default_data)
end

mock.reset()

function mock.cursor()
    return {
        get = function(self, config, section, option)
            local config_data = mock.data[config]
            if not config_data then
                return nil
            end

            local section_data = config_data[section]
            if option == nil then
                if section_data ~= nil then
                    return true
                end
                return nil
            end

            if section_data ~= nil then
                return section_data[option]
            end
            return nil
        end,
        get_all = function(self, config, section)
            local config_data = mock.data[config]
            if not config_data then
                return nil
            end

            local section_data = config_data[section]
            if section_data == nil then
                return nil
            end

            return clone(section_data)
        end,
        foreach = function(self, config, section_type, func)
            if config == "network" and section_type == "device" then
                func({ type = "bridge", name = "br-lan" })
            elseif config == "dhcp" and section_type == "host" then
                func({ name = "Desktop", mac = "11:22:33:44:55:66" })
            end
        end,
    }
end

return mock
