-- CodeCompanion Tools Full Configuration Example

require("codecompanion-tools").setup({
  -- Translator module
  translator = {
    adapter = nil, -- nil uses CodeCompanion default adapter
    default_target_lang = "zh", -- Default target language
    debug = {
      enabled = false, -- Recommended to disable in production
      log_level = "INFO", -- DEBUG|INFO|WARN|ERROR
    },
    output = {
      notification_timeout = 3000,
      copy_to_clipboard = false,
    },
    -- Custom prompt (optional)
    prompt = {
      system = [[You are a professional translator. Translate the following content into %s.
Keep code blocks, technical terms, and formatting unchanged.
Return only the translated text without any explanation.]],
    },
    -- Supported languages (extensible)
    languages = {
      zh = "Chinese",
      en = "English",
      ja = "Japanese",
      ko = "Korean",
      fr = "French",
      de = "German",
      es = "Spanish",
      ru = "Russian",
    },
  },

  -- Future module examples (not implemented yet)
  -- formatter = false,  -- Disable formatter module
  -- refactor = {        -- Refactor module configuration
  --   ...
  -- }
})

-- Keymap examples
vim.keymap.set("v", "<leader>te", ":CCTranslate en<CR>", { desc = "Translate to English" })
vim.keymap.set("v", "<leader>tz", ":CCTranslate zh<CR>", { desc = "Translate to Chinese" })
vim.keymap.set("v", "<leader>tj", ":CCTranslate ja<CR>", { desc = "Translate to Japanese" })

-- View logs
vim.keymap.set("n", "<leader>tl", ":CCTranslatorLog<CR>", { desc = "View translator logs" })
vim.keymap.set("n", "<leader>tc", ":CCTranslatorLog clear<CR>", { desc = "Clear translator logs" })
