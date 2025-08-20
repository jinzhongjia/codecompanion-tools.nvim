# CodeCompanion Translator 

## 项目结构

```
codecompanion-tools.nvim/
├── lua/
│   └── codecompanion-tools/
│       ├── init.lua                 # 主入口文件
│       └── translator/
│           ├── init.lua              # 翻译器主模块
│           ├── config.lua            # 配置管理
│           ├── core.lua              # 核心翻译逻辑
│           └── logger.lua            # 日志系统
├── examples/
│   └── translator_config.lua        # 配置示例
├── README.md                         # 主文档
├── README_translator.md              # 翻译器详细文档
└── .stylua.toml                      # 代码格式化配置
```

## 功能实现

1. **核心翻译功能**
   - 支持选中文本翻译
   - 支持单词/行翻译
   - 异步执行，不阻塞编辑器
   - 结果显示在 Neovim message 中

2. **灵活配置**
   - 支持指定 adapter 和 model
   - 支持多种语言（12种预设语言）
   - 可自定义提示词模板
   - 可配置输出格式

3. **调试支持**
   - 完整的日志系统
   - 支持 DEBUG, INFO, WARN, ERROR 四个级别
   - 日志文件管理命令

4. **用户体验**
   - 简单的命令接口
   - 支持快捷键映射
   - 友好的错误提示
   - 可选的剪贴板复制

5. **集成特性**
   - 与 CodeCompanion 完美集成
   - 利用 CodeCompanion 的 adapter 系统
   - 支持所有 CodeCompanion 支持的 LLM

### 📝 使用示例

```vim
" 基本使用
:'<,'>CodeCompanionTranslate zh              " 翻译为中文
:'<,'>CodeCompanionTranslate en              " 翻译为英文
:'<,'>CodeCompanionTranslate ja anthropic    " 使用 Anthropic 翻译为日文
:'<,'>CodeCompanionTranslate ko openai gpt-4 " 指定模型翻译为韩文

" 调试命令
:CodeCompanionTranslatorLog                  " 查看日志
:CodeCompanionTranslatorLog clear            " 清空日志
```

### 🔧 配置示例

```lua
require("codecompanion-tools").setup({
  translator = {
    default_adapter = "anthropic",
    default_target_lang = "zh",
    debug = {
      enabled = true,
      log_level = "DEBUG",
    },
    output = {
      show_original = true,
      notification_timeout = 5000,
      copy_to_clipboard = true,
    }
  }
})
```

## 技术实现细节

### 1. 异步处理
- 使用 `vim.schedule` 确保 UI 不阻塞
- 翻译请求在后台执行
- 回调函数处理结果

### 2. 适配器集成
- 动态获取 CodeCompanion 的适配器
- 支持适配器扩展和模型覆盖
- 自动处理适配器配置

### 3. 错误处理
- 多层错误捕获
- 友好的用户提示
- 详细的调试日志

### 4. 配置管理
- 深度合并用户配置
- 默认值和用户值分离
- 运行时配置访问

## 测试方法

1. **基本功能测试**
   ```vim
   " 在 Neovim 中
   :source quickstart.lua
   :TranslatorTest
   ```

2. **交互式测试**
   ```vim
   :lua require("tests.translator_test").interactive()
   ```

3. **完整测试套件**
   ```vim
   :lua require("tests.translator_test").run_all()
   ```

## 后续优化建议

1. **性能优化**
   - 添加翻译缓存机制
   - 批量翻译支持
   - 请求去重

2. **功能增强**
   - 浮动窗口显示长文本
   - 翻译历史记录
   - 术语表管理
   - 与 Action Palette 集成

3. **用户体验**
   - 进度条显示
   - 翻译质量评分
   - 多翻译结果对比
