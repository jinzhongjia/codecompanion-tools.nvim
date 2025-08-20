require("codecompanion-tools").setup({
  translator = {
     adapter = "anthropic", -- 覆盖默认适配器 (可选)
    default_target_lang = "zh",
     debug = { 
       enabled = true, 
       log_level = "DEBUG" 
     },
     output = { 
       notification_timeout = 5000, 
       copy_to_clipboard = true 
     },
  }
})
