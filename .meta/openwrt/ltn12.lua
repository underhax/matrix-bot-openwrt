---@meta

---@class ltn12_sink
local sink = {}
---@param t table
---@return function
function sink.table(t) end

---@param f file*
---@return function
function sink.file(f) end

---@class ltn12_source
local source = {}
---@param str string
---@return function
function source.string(str) end

---@class ltn12
local ltn12 = {}
ltn12.sink = sink
ltn12.source = source

return ltn12
