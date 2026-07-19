stds.openwrt = {
   read_globals = {
      "require", "pcall", "xpcall", "tonumber", "tostring", "print", "type", "pairs", "ipairs", "error", "next", "setmetatable", "getmetatable", "math", "string", "table", "io", "os", "coroutine", "_G", "_VERSION",
      -- LuCI / OpenWrt specifics
      "luci", "nixio", "cjson", "iwinfo", "ubus", "uci", "unpack",
      "entry", "cbi", "_", "translate", "Map", "NamedSection",
      "Value", "DummyValue", "DynamicList", "Flag", "module", "package", "index"
   },
}

std = "openwrt"
max_line_length = 120
ignore = {}
globals = {"index"}

overrides = {
   ["tests/**/*.lua"] = {
      std = "openwrt+busted"
   }
}
