# CodeCompanion Tools 架构说明

## 目录结构

```
lua/codecompanion-tools/
├── init.lua                 # 主入口，负责模块加载和管理
├── common/                   # 共享组件
│   ├── logger.lua           # 通用日志模块
│   └── utils.lua            # 通用工具函数
├── translator/              # 翻译模块
│   ├── init.lua            # 模块入口
│   ├── config.lua          # 配置管理
│   ├── core.lua            # 核心功能
│   └── logger.lua          # 日志代理（使用 common/logger）
├── adapters/                # OAuth 适配器模块
│   ├── init.lua            # 模块入口，注册所有适配器
│   ├── oauth_utils.lua     # OAuth 共享工具函数
│   ├── anthropic_oauth.lua # Anthropic Claude OAuth 适配器
│   ├── codex_oauth.lua     # OpenAI Codex (ChatGPT) OAuth 适配器
│   ├── codex_instructions.lua # Codex 系统指令
│   ├── gemini_oauth.lua    # Google Gemini OAuth 适配器
│   └── antigravity_oauth.lua # Google Antigravity OAuth 适配器
└── module_template.lua      # 新模块模板
```

## 模块概览

### 翻译模块 (translator)
提供翻译功能，支持多种目标语言。

### 适配器模块 (adapters)
提供基于 OAuth 认证的 AI 服务适配器，支持：

| 适配器 | 服务 | OAuth 类型 | 功能特点 |
|--------|------|------------|----------|
| `anthropic_oauth` | Anthropic Claude | OAuth 2.0 + PKCE | 支持最新 Claude 模型，扩展思考 |
| `codex_oauth` | OpenAI Codex/ChatGPT | OAuth 2.0 + PKCE | 支持 GPT-5.x 系列，推理模式 |
| `gemini_oauth` | Google Gemini | OAuth 2.0 + PKCE | 支持 Gemini 3/2.5/2.0/1.5 |
| `antigravity_oauth` | Google Antigravity | OAuth 2.0 + PKCE | 多端点故障转移，支持 Claude/GPT |

## 添加新模块的步骤

### 1. 创建模块目录
```bash
mkdir lua/codecompanion-tools/your_module
```

### 2. 创建模块文件
参考 `module_template.lua` 创建以下文件：
- `init.lua` - 模块入口和命令注册
- `config.lua` - 配置管理
- `core.lua` - 核心功能实现

### 3. 注册模块
在 `lua/codecompanion-tools/init.lua` 的 `available_modules` 表中添加：
```lua
local available_modules = {
  translator = "codecompanion-tools.translator",
  adapters = "codecompanion-tools.adapters",
  your_module = "codecompanion-tools.your_module",  -- 新增
}
```

### 4. 使用共享组件

#### 使用 Logger
```lua
local logger = require("codecompanion-tools.common.logger").create("your_module", {
  enabled = true,
  log_level = "INFO"
})

logger:debug("Debug message")
logger:info("Info message")
logger:error("Error message")
```

#### 使用 Utils
```lua
local utils = require("codecompanion-tools.common.utils")

-- 获取选中文本
local text = utils.get_visual_selection()

-- 合并配置
local config = utils.merge_config(defaults, user_config)

-- 发送通知
utils.notify("操作完成", vim.log.levels.INFO, "Your Module")
```

#### 使用 OAuth Utils (适配器开发)
```lua
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

-- 生成 PKCE
local pkce = oauth_utils.generate_pkce(64)

-- URL 编码
local encoded = oauth_utils.url_encode(str)

-- 启动 OAuth 服务器
oauth_utils.start_oauth_server(port, callback_path, timeout_ms, success_html, callback)

-- 打开浏览器
oauth_utils.open_url(url)
```

## 用户配置示例

```lua
require("codecompanion-tools").setup({
  -- 翻译模块配置
  translator = {
    default_target_lang = "zh",
    debug = { enabled = true, log_level = "DEBUG" }
  },
  
  -- 适配器模块配置
  adapters = {
    -- 启用所有适配器（默认）
    anthropic_oauth = true,
    codex_oauth = true,
    gemini_oauth = true,
    antigravity_oauth = true,
  },
  
  -- 禁用某个模块
  -- some_module = false,
})
```

## 适配器用户命令

### Anthropic OAuth
- `:AnthropicOAuthSetup` - 设置 OAuth 认证
- `:AnthropicOAuthStatus` - 检查认证状态
- `:AnthropicOAuthClear` - 清除存储的凭证

### Codex OAuth
- `:CodexOAuthSetup` - 设置 OAuth 认证
- `:CodexOAuthStatus` - 检查认证状态
- `:CodexOAuthClear` - 清除存储的凭证
- `:CodexUpdateInstructions` - 从 GitHub 更新系统指令

### Gemini OAuth
- `:GeminiOAuthSetup` - 设置 OAuth 认证
- `:GeminiOAuthStatus` - 检查认证状态
- `:GeminiOAuthClear` - 清除存储的凭证

### Antigravity OAuth
- `:AntigravityOAuthSetup` - 设置 OAuth 认证
- `:AntigravityOAuthStatus` - 检查认证状态
- `:AntigravityOAuthClear` - 清除存储的凭证

## 在 CodeCompanion 中使用适配器

设置完成后，可以在 CodeCompanion 配置中使用这些适配器：

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic_oauth",  -- 或 codex_oauth, gemini_oauth, antigravity_oauth
    },
  },
})
```

## 架构优势

1. **模块化设计** - 每个功能独立，易于维护
2. **共享组件** - 避免代码重复，提高一致性
3. **灵活配置** - 支持模块级别的启用/禁用
4. **易于扩展** - 添加新模块只需遵循既定模式
5. **健康检查** - 内置 health check 功能
6. **跨平台支持** - OAuth 工具支持 Windows/macOS/Linux

## 开发建议

1. 保持模块独立性，避免模块间直接依赖
2. 使用共享组件处理通用功能
3. 为每个模块提供独立的配置选项
4. 编写清晰的日志信息便于调试
5. 提供用户友好的命令和补全功能
6. 适配器开发时复用 `oauth_utils` 中的工具函数
