stds.openwrt = {
   read_globals = {
      "require", "pcall", "xpcall", "tonumber", "tostring", "print", "type", "pairs", "ipairs", "error", "next", "setmetatable", "getmetatable", "math", "string", "table", "io", "os", "coroutine", "_G", "_VERSION",
      -- LuCI / OpenWrt specifics
      "luci", "nixio", "cjson", "iwinfo", "ubus", "uci", "unpack",
      "entry", "cbi", "call", "_", "translate", "Map", "NamedSection",
      "Value", "DummyValue", "DynamicList", "Flag", "ListValue", "module", "package"
   },
}

std = "openwrt"
max_line_length = 120
ignore = {}

overrides = {
   ["tests/**/*.lua"] = {
      std = "openwrt+busted"
   }
}
