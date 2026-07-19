---@meta

---@class nixio
local nixio = {}

---@class nixio_file
local nixio_file = {}

---@return boolean
function nixio_file:close() end

---@param length number
---@return string|nil data
function nixio_file:read(length) end

---@param data string
---@return number|nil bytes_written
function nixio_file:write(data) end

---@return nixio_file pin, nixio_file pout
function nixio.pipe() end

---@return number pid
function nixio.fork() end

---@param pid number
---@param signal number
function nixio.kill(pid, signal) end

---@param pid number
---@param options string?
---@return number wpid, string status, number code
function nixio.waitpid(pid, options) end

---@param seconds number
---@param nanoseconds number
function nixio.nanosleep(seconds, nanoseconds) end

---@param fd1 any
---@param fd2 any
function nixio.dup(fd1, fd2) end

---@param executable string
---@vararg string
function nixio.execp(executable, ...) end

---@return number pid
function nixio.getpid() end

nixio.stdout = {}
nixio.stdin = {}
nixio.stderr = {}

---@param path string
---@param flags number
---@return any fd
function nixio.open(path, flags) end

nixio.O_RDWR = 2
nixio.O_WRONLY = 1
nixio.O_RDONLY = 0

---@class nixio_fs
nixio.fs = {}

---@param path string
---@return function|nil iterator
function nixio.fs.dir(path) end

---@param path string
---@param mode string?
---@return boolean
function nixio.fs.access(path, mode) end

---@param domain string
---@param type string
---@return any sock
function nixio.socket(domain, type) end

---@param priority string
---@param message string
function nixio.syslog(priority, message) end

return nixio
