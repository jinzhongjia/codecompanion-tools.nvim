local M = {}

local defaults = {
  default_adapter = nil, -- 使用 CodeCompanion 默认适配器
  default_target_lang = "en",
  debug = {
    enabled = true,
    log_level = "INFO", -- DEBUG|INFO|WARN|ERROR
  },
  fallback = {
    -- 当当前 CodeCompanion 版本没有提供 codecompanion.api 模块时，是否使用 Chat 回退方案
    -- 为 true 时会打开一个临时聊天窗口并填入翻译提示，而不是直接输出到 messages
    use_chat = false,
  },
  output = {
    show_original = true,
    notification_timeout = 4000,
    copy_to_clipboard = false,
  },
  prompt = [[You are a professional software localization translator.
Translate the following content into %s.
Keep code blocks unchanged.
Return only the translated text.
Do not add any explanation.
Do not output any emojis or decorative symbols that are not present in the source.
Preserve the original meaning and technical terms.]],
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
