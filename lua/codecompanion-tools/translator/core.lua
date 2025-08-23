local M = {}
local utils = require("codecompanion-tools.common.utils")

-- Lazy load configuration and logger
local function get_config()
  return require("codecompanion-tools.translator.config").opts
end

local function get_logger()
  return require("codecompanion-tools.translator.logger")
end

local function build_messages(text, target_lang)
  local cfg = get_config()
  local lang_full = cfg.languages[target_lang] or target_lang
  local system = string.format(cfg.prompt.system, lang_full)
  return {
    { role = "system", content = system },
    { role = "user", content = text },
  }
end

local function send_request(messages, adapter_name, model_name, cb)
  local http = require("codecompanion.http")
  local cc_config = require("codecompanion.config")
  local adapters = require("codecompanion.adapters")
  local schema = require("codecompanion.schema")
  local logger = get_logger()

  adapter_name = adapter_name or cc_config.strategies.chat.adapter
  local adapter = adapters.resolve(adapter_name)
  if not adapter then
    return cb("Failed to resolve adapter: " .. tostring(adapter_name))
  end

  adapter.opts.stream = false
  -- Override schema default if user specified a model
  if model_name and model_name ~= "" then
    if adapter.schema and adapter.schema.model then
      adapter.schema.model.default = model_name
    end
  end
  adapter = adapter:map_schema_to_params(schema.get_default(adapter))

  logger:debug("Using adapter: %s", adapter.name)

  local client = http.new({ adapter = adapter })
  local payload = { messages = adapter:map_roles(messages) }

  client:request(payload, {
    callback = function(err, data, ad)
      if err then
        logger:error("Request failed: %s", err.stderr or err.message or vim.inspect(err))
        return cb(err.stderr or err.message or "Unknown error")
      end
      if not data then
        return cb("Empty response")
      end
      local result = ad.handlers.chat_output(ad, data)
      if not result or not result.status then
        return cb("Failed to parse response")
      end
      if result.status == "error" then
        return cb(result.output or "LLM returned error")
      end
      local content = result.output and result.output.content or ""
      if type(content) == "table" then
        content = table.concat(
          vim.tbl_map(function(c)
            return c.text or c.content or ""
          end, content),
          "\n"
        )
      end
      return cb(nil, vim.trim(content))
    end,
  }, { silent = true })
end

local function output_result(translated)
  local cfg = get_config()
  -- Only print translation result
  print(translated)
  if cfg.output.copy_to_clipboard then
    vim.fn.setreg("+", translated)
    utils.notify("Copied to clipboard", vim.log.levels.INFO, "Translator")
  end
end

function M.translate_visual(opts)
  opts = opts or {}
  local cfg = get_config()
  local logger = get_logger()

  -- Strictly get visual selection; use original function if no selection (maintain backward compatibility)
  local text, start_line, end_line = utils.get_strict_visual_selection()
  if text then
    logger:debug("Got selection text: lines %d-%d", start_line, end_line)
  else
    text, start_line, end_line = utils.get_visual_selection()
    logger:debug("No strict selection, falling back to general: lines %d-%d", start_line, end_line)
  end

  local target = opts.target_lang or cfg.default_target_lang
  local messages = build_messages(text, target)
  local adapter = opts.adapter or cfg.adapter
  local model = opts.model or cfg.model

  send_request(messages, adapter, model, function(err, translated)
    if err then
      return utils.notify("Translation failed: " .. err, vim.log.levels.ERROR, "Translator")
    end
    output_result(translated)
  end)
end

return M
