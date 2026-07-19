---@meta

---@class iwinfo_assoc_entry
---@field mac string
---@field signal number
---@field noise number
---@field rx_rate number
---@field tx_rate number

---@class iwinfo_backend
---@field assoclist fun(ifname: string): table<string, iwinfo_assoc_entry>

---@class iwinfo
local iwinfo = {}
---@param ifname string
---@return string
function iwinfo.type(ifname) end
---@param ifname string
---@return iwinfo_backend|nil
function iwinfo.nl80211(ifname) end
---@param ifname string
---@return iwinfo_backend|nil
function iwinfo.wl(ifname) end

return iwinfo
