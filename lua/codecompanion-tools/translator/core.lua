local M = {}
local cfg = require("codecompanion-tools.translator.config").opts
local logger = require("codecompanion-tools.translator.logger")

local function get_adapter(adapter_name)
  local cc = require("codecompanion")
  if adapter_name then
    return adapter_name
  end
  return cfg.default_adapter
end

local function build_messages(text, target_lang)
  local lang_full = cfg.languages[target_lang] or target_lang
  local system = string.format(cfg.prompt, lang_full)
  return {
    { role = "system", content = system },
    { role = "user", content = text },
  }
end

local function send_request(messages, opts, cb)
  local adapter_name = get_adapter(opts.adapter)
  local http = require("codecompanion.http")
  local cc_config = require("codecompanion.config")
  local adapters = require("codecompanion.adapters")
  local schema = require("codecompanion.schema")

  adapter_name = adapter_name or cc_config.strategies.chat.adapter
  local adapter = adapters.resolve(adapter_name)
  if not adapter then
    return cb("Cannot resolve adapter: " .. tostring(adapter_name))
  end

  adapter.opts.stream = false
  adapter = adapter:map_schema_to_params(schema.get_default(adapter, { model = opts.model }))

  logger.debug("Resolved adapter=%s model=%s", adapter.name, adapter.model and adapter.model.name or "(default)")

  local client = http.new({ adapter = adapter })
  local payload = { messages = adapter:map_roles(messages) }

  client:request(payload, {
    callback = function(err, data, ad)
      if err then
        logger.error("Request failed: %s", err.stderr or err.message or vim.inspect(err))
        return cb(err.stderr or err.message or "Unknown error")
      end
      if not data then
        return cb("Empty response")
      end
      local result = ad.handlers.chat_output(ad, data)
      if not result or not result.status then
        return cb("Unable to parse response")
      end
      if result.status == "error" then
        return cb(result.output or "LLM returned error")
      end
      local content = result.output and result.output.content or ""
      if type(content) == "table" then
        content = table.concat(vim.tbl_map(function(c) return c.text or c.content or '' end, content), '\n')
      end
      return cb(nil, vim.trim(content))
    end,
  }, { silent = true })
end

local function output_result(original, translated)
  -- 仅输出译文，不再显示原文
  local msg = translated
  vim.schedule(function()
    vim.notify("Translation finished", vim.log.levels.INFO, { title = "Translator", timeout = cfg.output.notification_timeout })
    print(msg)
  end)
  if cfg.output.copy_to_clipboard then
    vim.fn.setreg('+', translated)
  end
end

function M.translate_visual(opts)
  opts = opts or {}
  local mode = vim.fn.mode()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line
  if mode == 'v' or mode == 'V' then
    start_line = vim.fn.getpos("'<")[2]
    end_line = vim.fn.getpos("'>")[2]
  else
    -- use provided range from command invocation
    start_line = vim.fn.line("'<")
    end_line = vim.fn.line("'>")
    if start_line == 0 or end_line == 0 then
      -- fallback: current line
      start_line = vim.fn.line('.')
      end_line = start_line
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local text = table.concat(lines, '\n')
  logger.debug("Captured text lines=%d", #lines)
  local target = opts.target_lang or cfg.default_target_lang
  local messages = build_messages(text, target)
  send_request(messages, opts, function(err, translated)
    if err then
      return vim.notify("Translation failed: " .. err, vim.log.levels.ERROR, { title = "Translator" })
    end
    output_result(text, translated)
  end)
end

return M
