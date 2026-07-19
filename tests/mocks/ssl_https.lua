local mock = {}

mock.next_response = nil
mock.next_code = 200
mock.next_error = nil

function mock.request(req)
    if mock.next_error then
        error(mock.next_error)
    end

    if req.sink and mock.next_response then
        req.sink(mock.next_response)
    end

    return true, mock.next_code, {}, mock.next_response or '{"success": true}', "HTTP/1.1 " .. mock.next_code
end

return mock
