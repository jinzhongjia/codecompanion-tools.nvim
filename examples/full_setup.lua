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

  -- OAuth Adapters module
  adapters = {
    -- All adapters are enabled by default
    -- Set to false to disable specific adapters
    anthropic_oauth = true,    -- Anthropic Claude OAuth adapter
    codex_oauth = true,        -- OpenAI Codex (ChatGPT) OAuth adapter
    gemini_oauth = true,       -- Google Gemini OAuth adapter
    antigravity_oauth = true,  -- Google Antigravity OAuth adapter
  },

  -- Future module examples (not implemented yet)
  -- formatter = false,  -- Disable formatter module
  -- refactor = {        -- Refactor module configuration
  --   ...
  -- }
})

-- ============================================================================
-- Translator Keymap Examples
-- ============================================================================
vim.keymap.set("v", "<leader>te", ":CCTranslate en<CR>", { desc = "Translate to English" })
vim.keymap.set("v", "<leader>tz", ":CCTranslate zh<CR>", { desc = "Translate to Chinese" })
vim.keymap.set("v", "<leader>tj", ":CCTranslate ja<CR>", { desc = "Translate to Japanese" })

-- View logs
vim.keymap.set("n", "<leader>tl", ":CCTranslatorLog<CR>", { desc = "View translator logs" })
vim.keymap.set("n", "<leader>tc", ":CCTranslatorLog clear<CR>", { desc = "Clear translator logs" })

-- ============================================================================
-- OAuth Adapter Usage Examples
-- ============================================================================
-- After setup, you can use the OAuth adapters in CodeCompanion:
--
-- require("codecompanion").setup({
--   strategies = {
--     chat = {
--       adapter = "anthropic_oauth",  -- or codex_oauth, gemini_oauth, antigravity_oauth
--     },
--   },
-- })
--
-- Available OAuth Commands via :CCTools
--   :CCTools adapter anthropic auth    - Setup Anthropic OAuth authentication
--   :CCTools adapter anthropic status  - Check Anthropic OAuth status
--   :CCTools adapter anthropic clear   - Clear Anthropic OAuth credentials
--
--   :CCTools adapter codex auth        - Setup Codex (ChatGPT) OAuth authentication
--   :CCTools adapter codex status      - Check Codex OAuth status
--   :CCTools adapter codex clear       - Clear Codex OAuth credentials
--   :CCTools adapter codex instructions - Update Codex system instructions from GitHub
--
--   :CCTools adapter gemini auth       - Setup Gemini OAuth authentication
--   :CCTools adapter gemini status     - Check Gemini OAuth status
--   :CCTools adapter gemini clear      - Clear Gemini OAuth credentials
--
--   :CCTools adapter antigravity auth  - Setup Antigravity OAuth authentication
--   :CCTools adapter antigravity status - Check Antigravity OAuth status
--   :CCTools adapter antigravity clear - Clear Antigravity OAuth credentials
