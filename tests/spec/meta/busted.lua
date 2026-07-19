---@meta

---@class luassert_are
---@field equal fun(expected: any, actual: any, message?: string)

---@class luassert
---@field are luassert_are
---@field is_table fun(value: any, message?: string)
---@field is_true fun(value: any, message?: string)
---@field is_false fun(value: any, message?: string)
---@field is_nil fun(value: any, message?: string)
---@field is_not_nil fun(value: any, message?: string)
---@field is_string fun(value: any, message?: string)
---@field matches fun(pattern: string, value: string|nil, message?: string)
---@field not_matches fun(pattern: string, value: string|nil, message?: string)

---@type luassert | fun(v: any, message?: string): any
-- luacheck: push ignore 111 113
assert = assert
-- luacheck: pop
