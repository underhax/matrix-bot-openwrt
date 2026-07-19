---@meta

---@class uci_cursor
local uci_cursor = {}

---@param config string
---@param section_type string
---@param callback fun(s: table): boolean|nil
function uci_cursor:foreach(config, section_type, callback) end

---@param config string
---@param section string
---@param option? string
---@return string|table|nil value
function uci_cursor:get(config, section, option) end


---@class uci
local uci = {}

---@return uci_cursor
function uci.cursor() end

return uci
