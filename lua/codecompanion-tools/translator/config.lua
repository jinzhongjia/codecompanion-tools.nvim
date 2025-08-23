local M = {}

local defaults = {
  adapter = nil, -- 使用 CodeCompanion 默认适配器 (也可用 default_adapter 传入)
  model = nil, -- 默认模型 (也可用 default_model 传入)
  default_target_lang = "en",
  debug = {
    enabled = true,
    log_level = "INFO", -- DEBUG|INFO|WARN|ERROR
  },
  output = {
    notification_timeout = 4000,
    copy_to_clipboard = false,
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
end

return M
