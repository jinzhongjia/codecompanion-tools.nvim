local M = {}
local config = require("codecompanion-tools.translator.config")
local core = require("codecompanion-tools.translator.core")
local logger = require("codecompanion-tools.translator.logger")

function M.setup(user_conf)
  config.setup(user_conf)
  M._create_commands()
end

function M._create_commands()
  vim.api.nvim_create_user_command("CodeCompanionTranslate", function(cmd)
    local args = vim.split(cmd.args or "", " ", { trimempty = true })
    local cfg = require("codecompanion-tools.translator.config").opts
    local target = args[1]
    if not target or target == "" then
      target = cfg.default_target_lang
      vim.notify("No target language provided, using default: " .. target, vim.log.levels.INFO, { title = "Translator" })
    end
    core.translate_visual({ target_lang = target })
  end, {
    range = true,
    nargs = "*",
    complete = function(ArgLead, CmdLine, _)
      -- 仅补全第一个参数（语言代码）
      local parts = vim.split(CmdLine, "%s+", { trimempty = true })
      local arg_count = #parts - 1 -- 去除命令本身
      if arg_count <= 1 then
        local lang_keys = {}
        local ok_cfg, ccfg = pcall(function() return require("codecompanion-tools.translator.config").opts end)
        if ok_cfg and ccfg.languages then
          for k, _ in pairs(ccfg.languages) do table.insert(lang_keys, k) end
          table.sort(lang_keys)
        end
        if not ArgLead or ArgLead == "" then return lang_keys end
        local out = {}
        for _, v in ipairs(lang_keys) do if v:find(ArgLead, 1, true) then table.insert(out, v) end end
        return out
      end
      return {}
    end,
  })

  vim.api.nvim_create_user_command("CodeCompanionTranslatorLog", function(cmd)
    local sub = cmd.args
    if sub == "clear" then
      logger.clear()
      return vim.notify("Translator log cleared", vim.log.levels.INFO, { title = "Translator" })
    end
    logger.open()
  end, { nargs = "?", complete = function(ArgLead)
    local opts = { "clear" }
    local out = {}
    for _, v in ipairs(opts) do
      if not ArgLead or ArgLead == "" or v:find(ArgLead, 1, true) then table.insert(out, v) end
    end
    return out
  end })
end

return M
