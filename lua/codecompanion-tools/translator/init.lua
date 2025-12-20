local M = {}
local config = require("codecompanion-tools.translator.config")
local core = require("codecompanion-tools.translator.core")
local utils = require("codecompanion-tools.common.utils")

function M.setup(user_conf)
  config.setup(user_conf)
  M.create_commands()
end

function M.create_commands()
  utils.create_command("CCTranslate", function(cmd)
    local args = vim.split(cmd.args or "", " ", { trimempty = true })
    local cfg = require("codecompanion-tools.translator.config").opts
    local target = args[1]
    if not target or target == "" then
      target = cfg.default_target_lang
    elseif not config.opts.languages[target] then
      utils.notify("Invalid language '" .. target .. "', falling back to default: " .. cfg.default_target_lang, vim.log.levels.WARN, "Translator")
      target = cfg.default_target_lang
    end
    core.translate_visual({ target_lang = target })
  end, {
    range = true,
    nargs = "?",
    desc = "Translate selected text (optional: language)",
    complete = function(ArgLead)
      local lang_keys = {}
      for k, _ in pairs(config.opts.languages) do
        table.insert(lang_keys, k)
      end
      table.sort(lang_keys)
      if not ArgLead or ArgLead == "" then
        return lang_keys
      end
      local out = {}
      for _, v in ipairs(lang_keys) do
        if v:find(ArgLead, 1, true) then
          table.insert(out, v)
        end
      end
      return out
    end,
  })

  utils.create_command("CCTranslatorLog", function(cmd)
    local logger = require("codecompanion-tools.translator.logger")
    local sub = cmd.args
    if sub == "clear" then
      logger:clear()
      return utils.notify("Logs cleared", vim.log.levels.INFO, "Translator")
    end
    logger:open()
  end, {
    nargs = "?",
    desc = "View or clear translator logs",
    complete = function(ArgLead)
      local opts = { "clear" }
      local out = {}
      for _, v in ipairs(opts) do
        if not ArgLead or ArgLead == "" or v:find(ArgLead, 1, true) then
          table.insert(out, v)
        end
      end
      return out
    end,
  })

  utils.create_command("CCTranslatorCacheClear", function()
    core.clear_cache()
    utils.notify("Translation cache cleared", vim.log.levels.INFO, "Translator")
  end, {
    desc = "Clear translator cache",
  })
end

function M.health()
  local health = vim.health
  local cfg = config.opts

  health.start("Translator Module")

  health.ok("Default target language: " .. cfg.default_target_lang)

  if cfg.adapter then
    health.ok("Custom adapter: " .. cfg.adapter)
  else
    health.info("Using CodeCompanion default adapter")
  end

  if cfg.cache.enabled then
    health.ok(string.format("Cache enabled (TTL: %ds)", cfg.cache.ttl))
  else
    health.info("Cache disabled")
  end

  if cfg.debug.enabled then
    health.ok("Debug logging: " .. cfg.debug.log_level)
  else
    health.info("Debug logging disabled")
  end

  local logger = require("codecompanion-tools.translator.logger").get()
  local log_path = logger and logger.path or "unknown"
  local log_dir = vim.fn.fnamemodify(log_path, ":h")
  if vim.fn.isdirectory(log_dir) == 1 then
    health.ok("Log directory exists: " .. log_dir)
  else
    health.warn("Log directory does not exist: " .. log_dir)
  end
end

return M
