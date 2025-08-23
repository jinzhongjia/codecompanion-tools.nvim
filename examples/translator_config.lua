require("codecompanion-tools").setup({
  translator = {
    adapter = "anthropic", -- Override default adapter (optional)
    default_target_lang = "zh",
    debug = {
      enabled = true,
      log_level = "DEBUG",
    },
    output = {
      notification_timeout = 5000,
      copy_to_clipboard = true,
    },
  },
})
