require("codecompanion-tools").setup({
  translator = {
    default_adapter = "anthropic", -- 覆盖默认适配器 (可选)
    default_target_lang = "zh",
    debug = { enabled = true, log_level = "DEBUG" },
    output = { show_original = true, notification_timeout = 5000, copy_to_clipboard = true },
  }
})
