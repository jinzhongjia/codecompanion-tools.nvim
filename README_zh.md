# CodeCompanion Tools for Neovim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[English Documentation](./README.md)

为 [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) 提供的生产力工具集，增强您在 Neovim 中的 AI 辅助编程体验。

## ✨ 功能特性

### 🌐 翻译器模块
- **AI 驱动翻译**：利用 CodeCompanion 的 AI 适配器实现精准翻译
- **多语言支持**：支持 12+ 种语言，包括中文、英文、日文、韩文、法文、德文、西班牙文、俄文、意大利文、葡萄牙文、越南文和阿拉伯文
- **可视模式选择**：直接从可视模式翻译选中的文本
- **智能代码处理**：翻译时保留代码块和技术术语
- **灵活的输出选项**：
  - 显示翻译结果通知
  - 自动复制翻译到剪贴板
  - 可配置的通知显示时长
- **调试日志**：内置日志系统便于故障排查
- **适配器灵活性**：可使用任何 CodeCompanion 适配器或指定自定义适配器

## 📦 安装

### 使用 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "codecompanion-tools.nvim",
  dependencies = {
    "olimorris/codecompanion.nvim",
  },
  opts = {},
}
```

## ⚙️ 配置

### 默认配置

```lua
require("codecompanion-tools").setup({
  translator = {
    -- 使用特定适配器（可选，默认使用 CodeCompanion 的默认适配器）
    default_adapter = nil,
    
    -- 翻译的默认目标语言
    default_target_lang = "en",
    
    -- 调试设置
    debug = {
      enabled = true,
      log_level = "INFO", -- DEBUG|INFO|WARN|ERROR
    },
    
    -- 旧版 CodeCompanion 的回退选项
    fallback = {
      use_chat = false, -- 打开聊天窗口而不是直接输出
    },
    
    -- 输出设置
    output = {
      show_original = true,           -- 在输出中显示原文
      notification_timeout = 4000,    -- 通知显示时间（毫秒）
      copy_to_clipboard = false,      -- 自动复制翻译到剪贴板
    },
    
    -- 自定义提示词模板（%s 将被替换为目标语言）
    prompt = [[You are a professional software localization translator.
Translate the following content into %s.
Keep code blocks unchanged.
Return only the translated text.
Do not add any explanation.
Do not output any emojis or decorative symbols that are not present in the source.
Preserve the original meaning and technical terms.]],
    
    -- 语言映射（代码 -> 完整名称）
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
})
```

### 最简配置

```lua
require("codecompanion-tools").setup({
  translator = {
    default_target_lang = "zh",  -- 设置您偏好的目标语言
  }
})
```

### 高级配置示例

```lua
require("codecompanion-tools").setup({
  translator = {
    default_adapter = "anthropic",  -- 使用特定的 AI 提供商
    default_target_lang = "zh",
    debug = { 
      enabled = true, 
      log_level = "DEBUG"  -- 详细日志用于调试
    },
    output = { 
      show_original = true, 
      notification_timeout = 5000,
      copy_to_clipboard = true  -- 自动复制翻译
    },
  }
})
```

## 🚀 使用方法

### 命令

#### `:CodeCompanionTranslate [target_lang]`
将选中的文本翻译为指定语言。

**使用方法：**
1. 在可视模式下选择文本
2. 运行 `:CodeCompanionTranslate zh` 翻译为中文
3. 或运行 `:CodeCompanionTranslate` 使用默认目标语言

**示例：**
```vim
" 翻译为中文
:'<,'>CodeCompanionTranslate zh

" 翻译为日文
:'<,'>CodeCompanionTranslate ja

" 使用默认目标语言
:'<,'>CodeCompanionTranslate
```

#### `:CodeCompanionTranslatorLog [action]`
管理翻译器调试日志。

**操作：**
- 无参数：在新标签页中打开日志文件
- `clear`：清空日志文件

**示例：**
```vim
" 查看日志
:CodeCompanionTranslatorLog

" 清空日志
:CodeCompanionTranslatorLog clear
```

### 快捷键映射（可选）

将以下内容添加到您的 Neovim 配置中以快速访问：

```lua
-- 翻译为默认语言
vim.keymap.set('v', '<leader>tt', ':CodeCompanionTranslate<CR>', { desc = '翻译选中内容' })

-- 翻译为特定语言
vim.keymap.set('v', '<leader>tz', ':CodeCompanionTranslate zh<CR>', { desc = '翻译为中文' })
vim.keymap.set('v', '<leader>te', ':CodeCompanionTranslate en<CR>', { desc = '翻译为英文' })
vim.keymap.set('v', '<leader>tj', ':CodeCompanionTranslate ja<CR>', { desc = '翻译为日文' })

-- 查看翻译器日志
vim.keymap.set('n', '<leader>tl', ':CodeCompanionTranslatorLog<CR>', { desc = '查看翻译器日志' })
```

## 🔧 API 参考

### 设置函数

```lua
require("codecompanion-tools").setup(opts)
```

**参数：**
- `opts` (table): 配置选项
  - `translator` (table|false): 翻译器模块配置。设置为 `false` 可禁用。

### 翻译器模块 API

```lua
local translator = require("codecompanion-tools.translator")

-- 使用自定义配置设置翻译器
translator.setup({
  default_target_lang = "zh",
  -- 其他选项...
})
```

### 核心翻译函数

```lua
local core = require("codecompanion-tools.translator.core")

-- 程序化翻译可视选择
core.translate_visual({
  target_lang = "zh",  -- 目标语言
  adapter = "anthropic",  -- 可选：特定适配器
  model = "claude-3-opus",  -- 可选：特定模型
})
```

## 📝 支持的语言

| 代码 | 语言       | 代码 | 语言       |
|------|-----------|------|-----------|
| zh   | 中文      | es   | 西班牙文   |
| en   | 英文      | ru   | 俄文       |
| ja   | 日文      | it   | 意大利文   |
| ko   | 韩文      | pt   | 葡萄牙文   |
| fr   | 法文      | vi   | 越南文     |
| de   | 德文      | ar   | 阿拉伯文   |

您也可以通过提供完整名称来使用任何自定义语言。

## 🐛 故障排查

### 启用调试日志

```lua
require("codecompanion-tools").setup({
  translator = {
    debug = {
      enabled = true,
      log_level = "DEBUG",
    },
  }
})
```

### 查看日志
```vim
:CodeCompanionTranslatorLog
```

### 常见问题

1. **翻译不工作**：确保 CodeCompanion.nvim 已正确配置有效的 AI 适配器
2. **找不到适配器**：检查指定的适配器名称是否与您的 CodeCompanion 配置匹配
3. **响应为空**：验证您的 API 密钥和网络连接
4. **日志文件位置**：日志存储在 `vim.fn.stdpath("state") .. "/codecompanion_translator.log"`

## 🤝 贡献

欢迎贡献！请随时提交 Pull Request。

1. Fork 仓库
2. 创建您的功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) 提供了 AI 集成框架
- 所有贡献者和使用者

## 🚧 路线图

- [ ] 添加更多工具模块（代码格式化器、文档生成器等）
- [ ] 支持翻译历史记录
- [ ] 批量文件翻译
- [ ] 自定义语言检测
- [ ] 集成更多 AI 提供商
- [ ] 翻译质量反馈系统

---

为 Neovim 社区用 ❤️ 制作
