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
└── module_template.lua      # 新模块模板
```

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

## 用户配置示例

```lua
require("codecompanion-tools").setup({
  -- 翻译模块配置
  translator = {
    default_target_lang = "zh",
    debug = { enabled = true, log_level = "DEBUG" }
  },
  
  -- 新模块配置
  your_module = {
    -- 模块特定配置
  },
  
  -- 禁用某个模块
  -- some_module = false,
})
```

## 架构优势

1. **模块化设计** - 每个功能独立，易于维护
2. **共享组件** - 避免代码重复，提高一致性
3. **灵活配置** - 支持模块级别的启用/禁用
4. **易于扩展** - 添加新模块只需遵循既定模式
5. **健康检查** - 内置 health check 功能

## 开发建议

1. 保持模块独立性，避免模块间直接依赖
2. 使用共享组件处理通用功能
3. 为每个模块提供独立的配置选项
4. 编写清晰的日志信息便于调试
5. 提供用户友好的命令和补全功能