-- 通用日志模块，供所有工具使用
local M = {}

local function get_log_path(module_name)
  return vim.fn.stdpath("state") .. "/codecompanion_" .. module_name .. ".log"
end

local level_map = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

---@class Logger
---@field module_name string
---@field path string
---@field config table
local Logger = {}
Logger.__index = Logger

function Logger:new(module_name, config)
  local instance = setmetatable({}, self)
  instance.module_name = module_name
  instance.path = get_log_path(module_name)
  instance.config = config or { enabled = true, log_level = "INFO" }
  return instance
end

function Logger:should_log(level)
  if not self.config.enabled then
    return false
  end
  return level_map[level] >= level_map[self.config.log_level]
end

function Logger:write(level, msg)
  local line =
    string.format("[%s] [%s] %s %s", self.module_name:upper(), level, os.date("%H:%M:%S"), msg)
  local fd = io.open(self.path, "a")
  if fd then
    fd:write(line .. "\n")
    fd:close()
  end
end

function Logger:log(level, msg, ...)
  if not self:should_log(level) then
    return
  end
  if select("#", ...) > 0 then
    msg = string.format(msg, ...)
  end
  self:write(level, msg)
end

function Logger:debug(...)
  self:log("DEBUG", ...)
end
function Logger:info(...)
  self:log("INFO", ...)
end
function Logger:warn(...)
  self:log("WARN", ...)
end
function Logger:error(...)
  self:log("ERROR", ...)
end

function Logger:open()
  vim.cmd("tabnew " .. self.path)
end

function Logger:clear()
  local fd = io.open(self.path, "w")
  if fd then
    fd:write("")
    fd:close()
  end
end

-- 工厂函数
function M.create(module_name, config)
  return Logger:new(module_name, config)
end

return M
