local mock = {}
mock.sink = {
    table = function(t)
        return function(chunk, _err)
            if chunk then
                table.insert(t, chunk)
            end
            return 1
        end
    end,
}
mock.source = {
    string = function(s)
        return function()
            local chunk = s
            s = nil
            return chunk
        end
    end,
}
return mock
