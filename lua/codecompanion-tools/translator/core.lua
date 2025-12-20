local M = {}
local utils = require("codecompanion-tools.common.utils")

---@type table<string, {result: string, timestamp: number}>
local cache = {}

local function get_cache_key(text, target_lang)
  return target_lang .. ":" .. text
end

local function get_cached(text, target_lang)
  local cfg = require("codecompanion-tools.translator.config").opts
  if not cfg.cache.enabled then
    return nil
  end

  local key = get_cache_key(text, target_lang)
  local entry = cache[key]
  if not entry then
    return nil
  end

  local now = os.time()
  if now - entry.timestamp > cfg.cache.ttl then
    cache[key] = nil
    return nil
  end

  return entry.result
end

local function set_cached(text, target_lang, result)
  local cfg = require("codecompanion-tools.translator.config").opts
  if not cfg.cache.enabled then
    return
  end

  local key = get_cache_key(text, target_lang)
  cache[key] = { result = result, timestamp = os.time() }
end

function M.clear_cache()
  cache = {}
end

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

  -- COMPAT: v18 renamed strategies -> interactions, remove fallback when dropping v17 support
  local chat_config = cc_config.interactions and cc_config.interactions.chat or cc_config.strategies.chat
  adapter_name = adapter_name or chat_config.adapter
  local adapter = adapters.resolve(adapter_name)
  if not adapter then
    return cb("Failed to resolve adapter: " .. tostring(adapter_name))
  end

  adapter.opts.stream = false
  -- Create overrides for schema if user specified a model
  local overrides = {}
  if model_name and model_name ~= "" then
    overrides.model = model_name
  end
  adapter = adapter:map_schema_to_params(schema.get_default(adapter, overrides))

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

local function output_result(translated, bufnr, start_line, end_line)
  local cfg = get_config()

  if cfg.output.replace_selection and bufnr and start_line and end_line then
    if not vim.api.nvim_buf_is_valid(bufnr) then
      utils.notify("Buffer no longer valid, printing result instead", vim.log.levels.WARN, "Translator")
      print(translated)
    else
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if end_line > line_count then
        utils.notify("Lines changed, printing result instead", vim.log.levels.WARN, "Translator")
        print(translated)
      else
        local lines = vim.split(translated, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, lines)
        utils.notify("Text replaced", vim.log.levels.INFO, "Translator")
      end
    end
  else
    print(translated)
  end

  if cfg.output.copy_to_clipboard then
    vim.fn.setreg("+", translated)
    utils.notify("Copied to clipboard", vim.log.levels.INFO, "Translator")
  end
end

---@class TranslateVisualOpts
---@field target_lang? string
---@field adapter? string
---@field model? string

---@param opts? TranslateVisualOpts
function M.translate_visual(opts)
  opts = opts or {}
  local cfg = get_config()
  local logger = get_logger()

  local bufnr = vim.api.nvim_get_current_buf()
  local text, start_line, end_line = utils.get_strict_visual_selection()
  if text then
    logger:debug("Got selection text: lines %d-%d", start_line, end_line)
  else
    text, start_line, end_line = utils.get_visual_selection()
    logger:debug("No strict selection, falling back to general: lines %d-%d", start_line, end_line)
  end

  if not text or vim.trim(text) == "" then
    return utils.notify("No text selected for translation", vim.log.levels.WARN, "Translator")
  end

  local target = opts.target_lang or cfg.default_target_lang

  local cached_result = get_cached(text, target)
  if cached_result then
    logger:debug("Cache hit for target: %s", target)
    return output_result(cached_result, bufnr, start_line, end_line)
  end

  local messages = build_messages(text, target)
  local adapter = opts.adapter or cfg.adapter
  local model = opts.model or cfg.model

  send_request(messages, adapter, model, function(err, translated)
    if err then
      return utils.notify("Translation failed: " .. err, vim.log.levels.ERROR, "Translator")
    end
    set_cached(text, target, translated)
    output_result(translated, bufnr, start_line, end_line)
  end)
end

return M
