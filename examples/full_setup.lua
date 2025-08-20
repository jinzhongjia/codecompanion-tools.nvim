-- CodeCompanion Tools 完整配置示例

require("codecompanion-tools").setup({
  -- 翻译模块
  translator = {
    adapter = nil,              -- nil 使用 CodeCompanion 默认适配器
    default_target_lang = "zh", -- 默认目标语言
    debug = {
      enabled = false,          -- 生产环境建议关闭
      log_level = "INFO"        -- DEBUG|INFO|WARN|ERROR
    },
    output = {
      notification_timeout = 3000,
      copy_to_clipboard = false
    },
    -- 自定义提示词（可选）
    prompt = {
      system = [[You are a professional translator. Translate the following content into %s.
Keep code blocks, technical terms, and formatting unchanged.
Return only the translated text without any explanation.]]
    },
    -- 支持的语言（可扩展）
    languages = {
      zh = "Chinese",
      en = "English",
      ja = "Japanese",
      ko = "Korean",
      fr = "French",
      de = "German",
      es = "Spanish",
      ru = "Russian",
    }
  },
  
  -- 未来的模块示例（当前未实现）
  -- formatter = false,  -- 禁用格式化模块
  -- refactor = {        -- 重构模块配置
  --   ...
  -- }
})

-- 键位映射示例
vim.keymap.set("v", "<leader>te", ":CCTranslate en<CR>", { desc = "翻译为英文" })
vim.keymap.set("v", "<leader>tz", ":CCTranslate zh<CR>", { desc = "翻译为中文" })
vim.keymap.set("v", "<leader>tj", ":CCTranslate ja<CR>", { desc = "翻译为日文" })

-- 查看日志
vim.keymap.set("n", "<leader>tl", ":CCTranslatorLog<CR>", { desc = "查看翻译日志" })
vim.keymap.set("n", "<leader>tc", ":CCTranslatorLog clear<CR>", { desc = "清空翻译日志" })