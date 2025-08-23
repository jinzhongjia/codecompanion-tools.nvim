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
    if not target or target == "" or not config.opts.languages[target] then
      target = cfg.default_target_lang
      -- No longer prompt default language, keep output clean
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
end

return M
