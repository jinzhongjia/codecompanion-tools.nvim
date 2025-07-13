-- 使用示例：如何在 CodeCompanion 中配置 codecompanion-tools

require("codecompanion").setup({
  -- 其他 CodeCompanion 配置...
  extensions = {
    -- 现在可以直接使用扩展名，不需要 callback
    -- CodeCompanion 会自动查找 lua/codecompanion/_extensions/codecompanion-tools/init.lua
    ["codecompanion-tools"] = {
      opts = {
        -- 规则管理器配置
        rules = {
          enabled = true,
          debug = false,
          rules_filenames = {
            ".rules",
            ".goosehints", 
            ".cursorrules",
            ".windsurfrules",
            ".clinerules",
            ".github/copilot-instructions.md",
            "AGENT.md",
            "AGENTS.md", 
            "CLAUDE.md",
            ".codecompanionrules",
          },
          -- 自定义文件路径提取函数（可选）
          extract_file_paths_from_chat_message = function(message)
            -- 从消息内容中提取文件路径
            -- 返回路径数组
            return {}
          end,
        },
        
        -- 模型切换配置
        model_toggle = {
          enabled = true,
          keymap = "<S-Tab>", -- 切换快捷键
          
          -- 序列模式：跨适配器切换（推荐）
          sequence = {
            { adapter = "copilot", model = "gpt-4.1" },
            { adapter = "copilot", model = "o1-mini" },
            { adapter = "anthropic", model = "claude-3-5-sonnet-20241022" },
            { adapter = "openai", model = "gpt-4o" },
          },
          
          -- 或者使用模型列表模式：同适配器不同模型
          -- （如果设置了 sequence，则忽略 models）
          -- models = {
          --   copilot = {
          --     "gpt-4.1",
          --     "o1-mini",
          --     "claude-3-5-sonnet-20241022",
          --   },
          --   anthropic = {
          --     "claude-3-5-sonnet-20241022",
          --     "claude-3-opus-20240229",
          --   },
          --   openai = {
          --     "gpt-4o",
          --     "gpt-4o-mini",
          --     "gpt-4-turbo",
          --   }
          -- }
        },
      },
    },
  },
  
  -- 其他 CodeCompanion 配置...
})

-- 手动调用模型切换（可选）
-- vim.keymap.set("n", "<leader>tm", function()
--   require("codecompanion").extensions["codecompanion-tools"].toggle_model(vim.api.nvim_get_current_buf())
-- end, { desc = "Toggle model" })