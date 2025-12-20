local M = {}

---@class TranslatorDebugConfig
---@field enabled boolean
---@field log_level "DEBUG"|"INFO"|"WARN"|"ERROR"

---@class TranslatorOutputConfig
---@field notification_timeout number
---@field copy_to_clipboard boolean
---@field replace_selection boolean

---@class TranslatorCacheConfig
---@field enabled boolean
---@field ttl number TTL in seconds

---@class TranslatorPromptConfig
---@field system string

---@class TranslatorConfig
---@field adapter? string
---@field model? string
---@field default_target_lang string
---@field debug TranslatorDebugConfig
---@field output TranslatorOutputConfig
---@field cache TranslatorCacheConfig
---@field prompt TranslatorPromptConfig
---@field languages table<string, string>

---@type TranslatorConfig
local defaults = {
  adapter = "antigravity_oauth",
  model = "gemini-3-flash",
  default_target_lang = "en",
  debug = {
    enabled = true,
    log_level = "INFO",
  },
  output = {
    notification_timeout = 4000,
    copy_to_clipboard = false,
    replace_selection = false,
  },
  cache = {
    enabled = true,
    ttl = 300,
  },
  prompt = {
    system = [[You are a professional translator. Translate the following content into %s.
 Keep code blocks, technical terms, and formatting unchanged.
 Return only the translated text without any explanation.]],
  },
  languages = {
    zh = "Chinese",
    en = "English",
    ja = "Japanese",
    ko = "Korean",
    fr = "French",
    de = "German",
    es = "Spanish",
    ru = "Russian",
    it = "Italian",
    pt = "Portuguese",
    vi = "Vietnamese",
    ar = "Arabic",
  },
}

M.opts = vim.deepcopy(defaults)

function M.setup(user)
  user = user or {}
  M.opts = vim.tbl_deep_extend("force", defaults, user)

  local logger = require("codecompanion-tools.translator.logger")
  logger.reset()
end

return M
