local mock = {}

function mock.decode(str)
    if not str or str:match("missing closing brace") or str == '{"success": true' then
        error("Expected closing brace")
    end

    if str:match("Rate limit exceeded") then
        return { error = "Rate limit exceeded", retry_after_ms = 1000 }
    end

    if str:match("event123") then
        return { event_id = "$event123" }
    end

    return { success = true }
end

function mock.encode(_t)
    return '{"dummy":"json"}'
end

return mock
