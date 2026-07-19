---@meta

---@class ubus_conn
local conn = {}
---@param object string
---@param method string
---@param msg table?
---@return table|nil, number?
function conn:call(object, method, msg) end
---@param req table
---@param msg table
function conn:reply(req, msg) end
---@param objects table
function conn:add(objects) end

---@class ubus
local ubus = {}
---@return ubus_conn|nil
function ubus.connect() end

ubus.STATUS_OK = 0
ubus.STATUS_INVALID_COMMAND = 1
ubus.STATUS_INVALID_ARGUMENT = 2
ubus.STATUS_METHOD_NOT_FOUND = 3
ubus.STATUS_NOT_FOUND = 4
ubus.STATUS_NO_DATA = 5
ubus.STATUS_PERMISSION_DENIED = 6
ubus.STATUS_TIMEOUT = 7
ubus.STATUS_NOT_SUPPORTED = 8
ubus.STATUS_UNKNOWN_ERROR = 9
ubus.STATUS_CONNECTION_FAILED = 10

ubus.STRING = 3
ubus.INT32 = 4
ubus.BOOLEAN = 5
ubus.ARRAY = 6
ubus.TABLE = 7

return ubus
