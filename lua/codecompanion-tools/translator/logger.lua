local M = {}

local log_path = vim.fn.stdpath("state") .. "/codecompanion_translator.log"
M.path = log_path

local level_map = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

local function should_log(cur, want)
  return level_map[cur] <= level_map[want]
end

local function write(level, msg)
  local line = string.format("[%s] %s %s", level, os.date("%H:%M:%S"), msg)
  local fd = assert(io.open(log_path, "a"))
  fd:write(line .. "\n")
  fd:close()
end

function M.log(level, msg, ...)
  local cfg = require("codecompanion-tools.translator.config").opts
  if not cfg.debug.enabled then return end
  level = level or "INFO"
  if not should_log(level, cfg.debug.log_level) then return end
  if select('#', ...) > 0 then
    msg = string.format(msg, ...)
  end
  write(level, msg)
end

function M.debug(...)
  M.log("DEBUG", ...)
end
function M.info(...)
  M.log("INFO", ...)
end
function M.warn(...)
  M.log("WARN", ...)
end
function M.error(...)
  M.log("ERROR", ...)
end

function M.open()
  vim.cmd("tabnew " .. log_path)
end

function M.clear()
  local fd = assert(io.open(log_path, 'w'))
  fd:write("")
  fd:close()
end

return M
