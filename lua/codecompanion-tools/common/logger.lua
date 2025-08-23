-- Common logger module for all tools
local M = {}

local function get_log_path(module_name)
  -- Use vim.fs.joinpath for cross-platform compatibility
  local state_dir = vim.fn.stdpath("state")
  local log_file = "codecompanion_" .. module_name .. ".log"
  return vim.fs.joinpath(state_dir, log_file)
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
  local configured_level = level_map[self.config.log_level] or level_map.INFO
  return level_map[level] >= configured_level
end

function Logger:write(level, msg)
  local line =
    string.format("[%s] [%s] %s %s", self.module_name:upper(), level, os.date("%H:%M:%S"), msg)

  -- Ensure log directory exists (Windows compatible)
  local log_dir = vim.fn.fnamemodify(self.path, ":h")
  if vim.fn.isdirectory(log_dir) == 0 then
    vim.fn.mkdir(log_dir, "p")
  end

  -- Use vim.uv for async file operations
  vim.uv.fs_open(self.path, "a", 438, function(err, fd) -- 438 = 0666 in octal
    if err then
      vim.schedule(function()
        vim.notify("Failed to open log file: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    local data = line .. "\n"
    vim.uv.fs_write(fd, data, -1, function(write_err)
      if write_err then
        vim.schedule(function()
          vim.notify("Failed to write to log file: " .. write_err, vim.log.levels.ERROR)
        end)
      end
      vim.uv.fs_close(fd)
    end)
  end)
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
  -- Use vim.uv for async file operations
  vim.uv.fs_open(self.path, "w", 438, function(err, fd) -- 438 = 0666 in octal
    if err then
      vim.schedule(function()
        vim.notify("Failed to open log file for clearing: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    -- Write empty string to clear the file
    vim.uv.fs_write(fd, "", 0, function(write_err)
      if write_err then
        vim.schedule(function()
          vim.notify("Failed to clear log file: " .. write_err, vim.log.levels.ERROR)
        end)
      end
      vim.uv.fs_close(fd)
    end)
  end)
end

-- Factory function
function M.create(module_name, config)
  return Logger:new(module_name, config)
end

return M
