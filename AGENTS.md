# CodeCompanion Tools Architecture

## LLM NOTE

This document outlines the architecture and usage of the CodeCompanion Tools for Neovim, a modular plugin that enhances AI-assisted programming with OAuth adapters and translation capabilities.
It provides detailed information on the directory structure, module functionalities, configuration options, and development guidelines.
It is intended for developers looking to understand or extend the functionality of the plugin.

When modify code or adding new features, please refer to this architecture document to ensure consistency and maintainability across the codebase.

## Directory Structure

```
lua/codecompanion-tools/
├── init.lua                 # Main entry point, handles module loading and management
├── common/                   # Shared components
│   ├── logger.lua           # Universal logging module
│   └── utils.lua            # Common utility functions
├── translator/              # Translator module
│   ├── init.lua            # Module entry point
│   ├── config.lua          # Configuration management
│   ├── core.lua            # Core functionality
│   └── logger.lua          # Logger proxy (uses common/logger)
├── adapters/                # OAuth adapters module
│   ├── init.lua            # Module entry point, registers all adapters
│   ├── oauth_utils.lua     # OAuth shared utility functions
│   ├── anthropic_oauth.lua # Anthropic Claude OAuth adapter
│   ├── codex_oauth.lua     # OpenAI Codex (ChatGPT) OAuth adapter
│   ├── codex_instructions.lua # Codex system instructions
│   └── antigravity_oauth.lua # Google Antigravity OAuth adapter
└── module_template.lua      # Template for new modules
```

## Module Overview

### Translator Module (translator)
Provides AI-powered translation functionality with multi-language support.

### Adapters Module (adapters)
Provides OAuth-authenticated adapters for AI services:

| Adapter | Service | OAuth Type | Features |
|---------|---------|------------|----------|
| `anthropic_oauth` | Anthropic Claude | OAuth 2.0 + PKCE | Latest Claude models, extended thinking |
| `codex_oauth` | OpenAI Codex/ChatGPT | OAuth 2.0 + PKCE | GPT-5.x series, reasoning mode |
| `antigravity_oauth` | Google Antigravity | OAuth 2.0 + PKCE | Multi-endpoint failover, Claude/GPT support |

## Adding a New Module

### 1. Create Module Directory
```bash
mkdir lua/codecompanion-tools/your_module
```

### 2. Create Module Files
Reference `module_template.lua` to create the following files:
- `init.lua` - Module entry point and command registration
- `config.lua` - Configuration management
- `core.lua` - Core functionality implementation

### 3. Register Module
Add to the `available_modules` table in `lua/codecompanion-tools/init.lua`:
```lua
local available_modules = {
  translator = "codecompanion-tools.translator",
  adapters = "codecompanion-tools.adapters",
  your_module = "codecompanion-tools.your_module",  -- Add new module
}
```

### 4. Using Shared Components

#### Using Logger
```lua
local logger = require("codecompanion-tools.common.logger").create("your_module", {
  enabled = true,
  log_level = "INFO"
})

logger:debug("Debug message")
logger:info("Info message")
logger:error("Error message")
```

#### Using Utils
```lua
local utils = require("codecompanion-tools.common.utils")

-- Get selected text
local text = utils.get_visual_selection()

-- Merge configuration
local config = utils.merge_config(defaults, user_config)

-- Send notification
utils.notify("Operation completed", vim.log.levels.INFO, "Your Module")
```

#### Using OAuth Utils (for adapter development)
```lua
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

-- Generate PKCE
local pkce = oauth_utils.generate_pkce(64)

-- URL encoding
local encoded = oauth_utils.url_encode(str)

-- Start OAuth server
oauth_utils.start_oauth_server(port, callback_path, timeout_ms, success_html, callback)

-- Open browser
oauth_utils.open_url(url)
```

## User Configuration Example

```lua
require("codecompanion-tools").setup({
  -- Translator module configuration
  translator = {
    default_target_lang = "zh",
    debug = { enabled = true, log_level = "DEBUG" }
  },

  -- Adapters module configuration
  adapters = {
    -- Enable all adapters (default)
    anthropic_oauth = true,
    codex_oauth = true,
    antigravity_oauth = true,
  },

  -- Disable a module
  -- some_module = false,
})
```

## Adapter User Commands

All adapter operations use the unified `:CCTools` command:

```vim
:CCTools adapter <name> <action>
```

### Available Adapters
- `anthropic` - Anthropic Claude
- `codex` - OpenAI Codex/ChatGPT
- `antigravity` - Google Antigravity

### Available Actions
| Action | Description |
|--------|-------------|
| `auth` | Setup OAuth authentication |
| `status` | Check authentication status |
| `clear` | Clear stored tokens |
| `instructions` | Update system instructions (codex only) |

### Examples
```vim
" Setup Anthropic OAuth
:CCTools adapter anthropic auth

" Check Codex status
:CCTools adapter codex status

" Update Codex instructions
:CCTools adapter codex instructions
```

## Using Adapters with CodeCompanion

After setup, use these adapters in your CodeCompanion configuration:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic_oauth",  -- or codex_oauth, antigravity_oauth
    },
  },
})
```

## Architecture Benefits

1. **Modular Design** - Each feature is independent and easy to maintain
2. **Shared Components** - Avoid code duplication and improve consistency
3. **Flexible Configuration** - Supports module-level enable/disable
4. **Easy to Extend** - Adding new modules follows established patterns
5. **Health Check** - Built-in health check functionality
6. **Cross-Platform Support** - OAuth tools support Windows/macOS/Linux

## Development Guidelines

1. Keep modules independent, avoid direct inter-module dependencies
2. Use shared components for common functionality
3. Provide independent configuration options for each module
4. Write clear log messages for debugging
5. Provide user-friendly commands with completion support
6. Reuse `oauth_utils` utility functions when developing adapters
