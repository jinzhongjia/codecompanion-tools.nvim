# CodeCompanion Tools for Neovim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[中文文档](./README_zh.md)

A collection of productivity tools for [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim), enhancing your AI-powered coding experience in Neovim.

## ✨ Features

### 🔐 OAuth Adapters Module

Pre-configured OAuth adapters for popular AI providers, enabling seamless authentication without manual API key management.

- **Anthropic OAuth**: Claude API with extended thinking support
- **Codex OAuth**: OpenAI Codex/ChatGPT with GPT-5.x models
- **Gemini OAuth**: Google Gemini Code Assist
- **Antigravity OAuth**: Google Antigravity with multi-endpoint failover
- **Cross-Platform**: Works on macOS, Linux, and Windows
- **Secure**: Uses PKCE flow for OAuth authentication
- **Token Management**: Automatic token refresh and secure storage

### 🌐 Translator Module

- **AI-Powered Translation**: Leverages CodeCompanion's AI adapters for accurate translations
- **Multi-Language Support**: Supports 12+ languages including Chinese, English, Japanese, Korean, French, German, Spanish, Russian, Italian, Portuguese, Vietnamese, and Arabic
- **Visual Mode Selection**: Translate selected text directly from visual mode
- **Smart Code Handling**: Preserves code blocks and technical terms during translation
- **Flexible Output Options**:
  - Display notifications with translation results
  - Copy translations to clipboard automatically
  - Configurable notification timeout
- **Debug Logging**: Built-in logging system for troubleshooting
- **Adapter Flexibility**: Use any CodeCompanion adapter or specify a custom one

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "codecompanion-tools.nvim",
  dependencies = {
    "olimorris/codecompanion.nvim",
  },
  opts = {},
}
```

## ⚙️ Configuration

### OAuth Adapters Configuration

Enable OAuth adapters to authenticate with AI providers using browser-based OAuth flow:

```lua
require("codecompanion-tools").setup({
  adapters = {
    -- Enable/disable specific adapters (all enabled by default)
    anthropic_oauth = true,    -- Anthropic Claude
    codex_oauth = true,        -- OpenAI Codex/ChatGPT
    gemini_oauth = true,       -- Google Gemini
    antigravity_oauth = true,  -- Google Antigravity
  },
})
```

After setup, use the OAuth adapters in CodeCompanion:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic_oauth",  -- or "codex_oauth", "gemini_oauth", "antigravity_oauth"
    },
  },
})
```

#### OAuth Commands

All adapter operations are managed through a unified command:

```vim
:CCTools adapter <name> <action>
```

**Available adapters:** `anthropic`, `codex`, `gemini`, `antigravity`

**Available actions:**
| Action | Description |
|--------|-------------|
| `auth` | Setup OAuth authentication |
| `status` | Check authentication status |
| `clear` | Clear stored tokens |
| `instructions` | Update system instructions (codex only) |

**Examples:**

```vim
" Setup Anthropic OAuth
:CCTools adapter anthropic auth

" Check Codex status
:CCTools adapter codex status

" Clear Gemini tokens
:CCTools adapter gemini clear

" Update Codex instructions
:CCTools adapter codex instructions
```

#### OAuth Flow

1. Run `:CCTools adapter <name> auth` (e.g., `:CCTools adapter anthropic auth`)
2. A browser window opens for authentication
3. After authorization, tokens are automatically saved
4. Use the adapter in CodeCompanion

Tokens are stored securely at `~/.local/share/nvim/` and are automatically refreshed when expired.

### Translator Configuration

### Default Configuration

```lua
require("codecompanion-tools").setup({
  translator = {
    -- Use specific adapter (optional, defaults to CodeCompanion's default)
    adapter = nil,          -- alias: default_adapter
    model = nil,            -- default model (alias: default_model)

    -- Default target language for translations
    default_target_lang = "en",

    -- Debug settings
    debug = {
      enabled = true,
      log_level = "INFO", -- DEBUG|INFO|WARN|ERROR
    },

    -- Fallback options for older CodeCompanion versions
    fallback = {
      use_chat = false, -- Open chat window instead of direct output
    },

    -- Output settings
    output = {
      show_original = true,           -- Show original text in output
      notification_timeout = 4000,    -- Notification display time (ms)
      copy_to_clipboard = false,      -- Auto-copy translation to clipboard
    },

    -- Custom prompt template (%s will be replaced with target language)
    prompt = [[You are a professional software localization translator.
Translate the following content into %s.
Keep code blocks unchanged.
Return only the translated text.
Do not add any explanation.
Do not output any emojis or decorative symbols that are not present in the source.
Preserve the original meaning and technical terms.]],

    -- Language mappings (code -> full name)
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

### Minimal Configuration

```lua
require("codecompanion-tools").setup({
  translator = {
    default_target_lang = "zh",  -- Set your preferred target language
  }
})
```

### Advanced Configuration Example

```lua
require("codecompanion-tools").setup({
  translator = {
    adapter = "anthropic",  -- Use specific AI provider
    model = "claude-3-5-sonnet",    -- Default model for translation requests
    default_target_lang = "zh",
    debug = {
      enabled = true,
      log_level = "DEBUG"  -- Verbose logging for debugging
    },
    output = {
      show_original = true,
      notification_timeout = 5000,
      copy_to_clipboard = true  -- Auto-copy translations
    },
  }
})
```

## 🚀 Usage

### Commands

#### `:CCTranslate [target_lang]`

Translate selected text to the specified language.

**Usage:**

1. Select text in visual mode
2. Run `:CodeCompanionTranslate zh` to translate to Chinese
3. Or run `:CodeCompanionTranslate` to use default target language and configured default model

**Examples:**

```vim
" Translate to Chinese
:'<,'>CCTranslate zh

" Translate to Japanese
:'<,'>CCTranslate ja

" Use default target language
:'<,'>CCTranslate

```

#### `:CCTranslatorLog [action]`

Manage translator debug logs.

**Actions:**

- No argument: Open log file in new tab
- `clear`: Clear the log file

**Examples:**

```vim
" View logs
:CCTranslatorLog

" Clear logs
:CCTranslatorLog clear
```

### Key Mappings (Optional)

Add these to your Neovim configuration for quick access:

```lua
-- Translate to default language
vim.keymap.set('v', '<leader>tt', ':CCTranslate<CR>', { desc = 'Translate selection' })

-- Translate to specific languages
vim.keymap.set('v', '<leader>tz', ':CCTranslate zh<CR>', { desc = 'Translate to Chinese' })
vim.keymap.set('v', '<leader>te', ':CCTranslate en<CR>', { desc = 'Translate to English' })
vim.keymap.set('v', '<leader>tj', ':CCTranslate ja<CR>', { desc = 'Translate to Japanese' })

-- View translator logs
vim.keymap.set('n', '<leader>tl', ':CCTranslatorLog<CR>', { desc = 'View translator logs' })
```

## 🔧 API Reference

### Setup Function

```lua
require("codecompanion-tools").setup(opts)
```

**Parameters:**

- `opts` (table): Configuration options
  - `adapters` (table|false): OAuth adapters configuration. Set to `false` to disable all adapters.
  - `translator` (table|false): Translator module configuration. Set to `false` to disable.

### Translator Module API

```lua
local translator = require("codecompanion-tools.translator")

-- Setup translator with custom config
translator.setup({
  default_target_lang = "zh",
  -- other options...
})
```

### Core Translation Function

```lua
local core = require("codecompanion-tools.translator.core")

-- Translate visual selection programmatically
core.translate_visual({
  target_lang = "zh",  -- Target language
  adapter = "anthropic",  -- Optional: specific adapter
  model = "claude-3-opus",  -- Optional: specific model
})
```

## 📝 Supported Languages

| Code | Language | Code | Language   |
| ---- | -------- | ---- | ---------- |
| zh   | Chinese  | es   | Spanish    |
| en   | English  | ru   | Russian    |
| ja   | Japanese | it   | Italian    |
| ko   | Korean   | pt   | Portuguese |
| fr   | French   | vi   | Vietnamese |
| de   | German   | ar   | Arabic     |

You can also use any custom language by providing its full name.

## 🐛 Troubleshooting

### Enable Debug Logging

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

### View Logs

```vim
:CCTranslatorLog
```

### Common Issues

1. **Translation not working**: Ensure CodeCompanion.nvim is properly configured with a valid AI adapter
2. **Adapter not found**: Check that the specified adapter name matches your CodeCompanion configuration
3. **Empty response**: Verify your API keys and network connection
4. **Log file location**: Logs are stored at `vim.fn.stdpath("state") .. "/codecompanion_translator.log"`

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) for providing the AI integration framework
- All contributors and users of this plugin

## 🚧 Roadmap

- [ ] Add more tool modules (code formatter, documentation generator, etc.)
- [ ] Support for translation history
- [ ] Batch file translation
- [ ] Custom language detection
- [ ] Additional OAuth adapters for more AI providers
- [ ] Translation quality feedback system

---

Made with ❤️ for the Neovim community

