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

local default_fs_stats = {
    ["/root/.ssh/router-matrix"] = { uid = 0, modedec = 600 },
    ["/etc/matrix_bot_known_hosts"] = { uid = 0, modedec = 600 },
}

function mock.reset()
    mock.fs_stats = clone(default_fs_stats)
    mock.next_fork_results = nil
    mock.exec_calls = {}
    mock.syslog_calls = {}
    mock.nanosleep_calls = {}
end

mock.reset()

mock.syslog = function(priority, message)
    table.insert(mock.syslog_calls, { priority = priority, message = message })
end

mock.syslog_prio = {
    err = 3,
    warning = 4,
    info = 6,
    debug = 7,
}

mock.nanosleep = function(sec, nsec)
    table.insert(mock.nanosleep_calls, { sec = sec, nsec = nsec })
end

mock.process = {}
mock.socket = function(_domain, _type)
    return {
        setopt = function()
            return true
        end,
        sendto = function()
            return true
        end,
        close = function()
            return true
        end,
    }
end

mock.pipe = function()
    local r = {
        close = function() end,
        read = function()
            return nil
        end,
    }
    local w = {
        close = function() end,
        write = function()
            return 0
        end,
    }
    return r, w
end
mock.fork = function()
    if mock.next_fork_results and #mock.next_fork_results > 0 then
        local result = table.remove(mock.next_fork_results, 1)
        return result
    end
    return 123
end
mock.waitpid = function()
    return 123, "exited", 0
end
mock.dup = function()
    return true
end
mock.execp = function(...)
    table.insert(mock.exec_calls, { ... })
    return true
end
mock.kill = function()
    return true
end
mock.open = function()
    return { close = function() end }
end
mock.getpid = function()
    return 456
end
mock.O_WRONLY = 1
mock.O_RDWR = 2

mock.fs = {
    dir = function(path)
        if path == "/sys/class/net" then
            local devs = { "wlan0", "eth0" }
            local i = 0
            return function()
                i = i + 1
                return devs[i]
            end
        end
        return function()
            return nil
        end
    end,
    access = function(_path, _mode)
        return false
    end,
    stat = function(path)
        local stat = mock.fs_stats[path]
        if not stat then
            return nil
        end
        return clone(stat)
    end,
}

return mock
