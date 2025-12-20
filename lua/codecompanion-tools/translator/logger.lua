-- Logger instance for Translator module
-- Uses lazy initialization to ensure config is loaded before creating logger

local M = {}

---@type Logger|nil
local _logger = nil

---Get or create the logger instance with current config
---@return Logger
function M.get()
  if not _logger then
    local logger_factory = require("codecompanion-tools.common.logger")
    local cfg = require("codecompanion-tools.translator.config").opts
    _logger = logger_factory.create("translator", cfg.debug)
  end
  return _logger
end

---Reset the logger instance (called when config changes)
function M.reset()
  _logger = nil
end

function M:debug(...)
  return M.get():debug(...)
end

function M:info(...)
  return M.get():info(...)
end

function M:warn(...)
  return M.get():warn(...)
end

function M:error(...)
  return M.get():error(...)
end

function M:open()
  return M.get():open()
end

function M:clear()
  return M.get():clear()
end

return M
