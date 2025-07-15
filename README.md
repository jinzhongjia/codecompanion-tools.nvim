# codecompanion-tools.nvim

A collection of useful tools and extensions for [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim).

## Features

### Rule Manager

Automatically detects and manages rule files for your project context in CodeCompanion chat buffers.

- **Automatic Rule Detection**: Automatically finds and includes relevant rule files (`.rules`, `.cursorrules`, `AGENT.md`, etc.) in your chat context
- **Smart Context Management**: Only includes rules from directories containing files referenced in your chat
- **Multiple Rule File Support**: Supports various common rule file formats used by different AI tools
- **Cache Management**: Efficiently caches and updates rule references to minimize token usage
- **Intelligent Path Extraction**: Extracts file paths from chat references, slash commands, and tool outputs

### Model Toggle

Quickly switch between LLM models in any CodeCompanion chat buffer.

- **Two Switching Modes**: 
  - **Sequence Mode**: Cycle through a predefined sequence of adapter+model combinations
  - **Models Mode**: Cycle through models within the same adapter
- **Per-Buffer Memory**: Each chat buffer remembers its original model independently
- **Customizable Keymaps**: Default keymap is `<S-Tab>` but fully customizable
- **Instant Notifications**: Shows which model you've switched to

### DAG Checklist System

Create and manage complex task checklists with dependency management and parallel execution.

- **Dependency Management**: Define task dependencies to ensure proper execution order
- **Parallel Execution**: Automatically execute independent read-only tasks in parallel for efficiency
- **Task Status Tracking**: Track task progress with states (pending, in_progress, completed, blocked)
- **Access Mode Control**: Specify task access modes (read, write, readwrite) for safe parallel execution
- **Persistent Storage**: Automatically save and restore checklists across sessions
- **Progress Monitoring**: Visual progress tracking with completion statistics

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "your-username/codecompanion-tools.nvim"
  },
  config = function()
    require("codecompanion").setup({
      extensions = {
        ["codecompanion-tools"] = {
          -- CodeCompanion automatically loads lua/codecompanion/_extensions/codecompanion-tools/init.lua
          opts = {
            -- Rule manager options
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
              -- Custom function to extract file paths from chat messages
              extract_file_paths_from_chat_message = nil,
            },

            -- Model toggle options
            model_toggle = {
              enabled = true,
              keymap = "<S-Tab>", -- Keymap to toggle models

              -- Option 1: Sequence mode (cross-adapter switching)
              sequence = {
                { adapter = "copilot", model = "gpt-4" },
                { adapter = "copilot", model = "o1-mini" },
                { adapter = "anthropic", model = "claude-3-5-sonnet-20241022" },
                { adapter = "openai", model = "gpt-4o" },
              },

              -- Option 2: Models mode (same-adapter switching)
              -- If sequence is set, models config is ignored
              -- models = {
              --   copilot = { "gpt-4", "o1-mini", "gpt-4o" },
              --   anthropic = { "claude-3-5-sonnet-20241022", "claude-3-opus-20240229" },
              --   openai = { "gpt-4o", "gpt-4o-mini" },
              -- },
            },

            -- DAG checklist system options
            dag = {
              enabled = true,
            },
          },
        },
      },
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "olimorris/codecompanion.nvim",
  requires = {
    "your-username/codecompanion-tools.nvim"
  },
  config = function()
    -- Same configuration as above
  end
}
```

## Directory Structure

The plugin uses the following directory structure to work with CodeCompanion's extension system:

```
lua/
├── codecompanion/
│   └── _extensions/
│       └── codecompanion-tools/
│           └── init.lua          <-- Main extension entry point
└── codecompanion_tools/
    ├── init.lua                  <-- Backward compatibility entry
    ├── model_toggle.lua          <-- Model switching functionality
    ├── rule.lua                  <-- Rule management functionality
    └── dag/                      <-- DAG checklist system
        ├── dag_tools.lua         <-- DAG tool definitions
        ├── dag_manager.lua       <-- DAG business logic
        ├── dag_formatter.lua     <-- DAG output formatting
        ├── dag_types.lua         <-- DAG type definitions
        ├── dag_executor.lua      <-- Parallel execution engine
        ├── storage.lua           <-- Persistent storage
        └── shared_types.lua      <-- Shared type definitions
```

## Configuration

### Rule Manager

The rule manager automatically detects and includes rule files in your chat context. You can customize which files it looks for:

```lua
rules = {
  enabled = true,
  debug = false, -- Enable debug logging
  rules_filenames = {
    ".rules",
    ".cursorrules",
    "AGENT.md",
    -- Add your custom rule files here
  },
  -- Custom function to extract file paths from chat messages
  extract_file_paths_from_chat_message = function(message)
    -- Return array of file paths found in message content
    -- Example: extract paths from custom tool output patterns
    local paths = {}
    for path in message.content:gmatch("Created: `([^`]+)`") do
      table.insert(paths, path)
    end
    return paths
  end,
}
```

#### How Rule Detection Works

1. **Trigger Conditions**: 
   - Chat buffer creation
   - Mode change (insert to normal)
   - After message submission
   - After tool execution
   - Manual trigger via `:CodeCompanionRulesProcess`

2. **Path Collection**:
   - From chat references (`/file`, `/buffer` commands)
   - From tool output patterns in messages
   - From custom extraction function

3. **Rule File Search**:
   - Searches parent directories upward from each referenced file
   - Looks for rule files in order of preference
   - Prioritizes deeper directories (more specific rules)

4. **Automatic Reference Management**:
   - Adds rule files as pinned references
   - Removes obsolete references
   - Updates context automatically

### Model Toggle

Configure model switching behavior:

```lua
model_toggle = {
  enabled = true,
  keymap = "<S-Tab>", -- Change the toggle keymap

  -- Sequence mode: cycle through predefined adapter+model combinations
  sequence = {
    { adapter = "copilot", model = "gpt-4" },
    { adapter = "anthropic", model = "claude-3-5-sonnet-20241022" },
    { adapter = "openai", model = "gpt-4o" },
  },

  -- Models mode: cycle through models within the same adapter
  -- (ignored if sequence is set)
  models = {
    copilot = { "gpt-4", "o1-mini" },
    anthropic = { "claude-3-5-sonnet-20241022", "claude-3-opus-20240229" },
    openai = { "gpt-4o", "gpt-4o-mini" },
  },
}
```

### DAG Checklist System

Configure the DAG checklist system for task management:

```lua
dag = {
  enabled = true, -- Enable/disable DAG functionality
}
```

The DAG system provides tools for creating and managing complex task checklists with dependency management. It automatically handles:

- **Dependency Resolution**: Ensures tasks are executed in the correct order
- **Parallel Execution**: Automatically runs independent read-only tasks in parallel
- **Persistent Storage**: Saves checklists to `~/.local/share/nvim/codecompanion-tools/dag_checklists.json`
- **Progress Tracking**: Monitors task completion and provides visual feedback

#### Task Access Modes

The DAG system uses access modes to determine which tasks can run in parallel:

- **`read`**: Safe for parallel execution (file analysis, search operations)
- **`write`**: Requires sequential execution (file modifications, destructive operations)
- **`readwrite`**: Requires sequential execution (operations that both read and modify)

#### Model Toggle Modes

**Sequence Mode** (recommended for cross-adapter switching):
- Cycles through a predefined sequence of adapter+model combinations
- **Important**: Only shows models for your current adapter
- To switch adapters, use CodeCompanion's built-in `ga` keymap first

**Models Mode** (for same-adapter switching):
- Cycles through models within the same adapter
- Supports single model (string) or multiple models (array) per adapter

#### Usage Flow Example

For sequence mode with current adapter `copilot`:

1. Start with default model (e.g., `copilot:gpt-4o-2024-08-06`)
2. Press `<S-Tab>` → switches to `copilot:gpt-4` (first in sequence for copilot)
3. Press `<S-Tab>` → switches back to original `copilot:gpt-4o-2024-08-06`
4. Manually change adapter to `anthropic` (using `ga`)
5. Press `<S-Tab>` → switches to `anthropic:claude-3-5-sonnet-20241022`
6. Press `<S-Tab>` → switches back to anthropic's default model

## Usage

### Rule Manager

The rule manager works automatically in the background. Manual commands are available:

- `:CodeCompanionRulesProcess` - Manually re-evaluate rule references
- `:CodeCompanionRulesDebug` - Toggle debug logging
- `:CodeCompanionRulesEnable` - Enable the rule manager
- `:CodeCompanionRulesDisable` - Disable the rule manager

#### Automatic Operation

1. **File Reference Detection**: When you reference files in chat via:
   - Slash commands (`/file`, `/buffer`)
   - Tool outputs
   - Custom extraction patterns

2. **Rule File Discovery**: Automatically searches parent directories for rule files

3. **Context Management**: Adds relevant rule files as pinned references

### Model Toggle

Use the configured keymap (default `<S-Tab>`) in any CodeCompanion chat buffer to cycle between models.

#### Programmatic Usage

```lua
-- Toggle model in current buffer
require("codecompanion").extensions["codecompanion-tools"].toggle_model(vim.api.nvim_get_current_buf())
```

### DAG Checklist System

The DAG system provides a unified `checklist` tool for task management:

#### Available Tool

The DAG system provides a unified **`checklist`** tool with action-based interface:

#### Usage Examples

**Create a checklist:**
```lua
checklist({
  action = "create",
  goal = "Implement user authentication system",
  tasks = {
    { text = "Analyze current codebase", mode = "read", dependencies = {} },
    { text = "Review security requirements", mode = "read", dependencies = {} },
    { text = "Design database schema", mode = "readwrite", dependencies = {1} },
    { text = "Write unit tests", mode = "write", dependencies = {3} },
    { text = "Implement auth logic", mode = "write", dependencies = {2, 3, 4} }
  },
  subject = "Auth system implementation",
  body = "Complete authentication system with proper dependency management"
})
```

**List all checklists:**
```lua
checklist({ action = "list" })
```

**Check status of a specific checklist:**
```lua
checklist({ action = "status", checklist_id = "2" })
```

**Complete a task:**
```lua
checklist({
  action = "complete",
  task_id = "1",
  subject = "Completed codebase analysis",
  body = "Analyzed authentication patterns and identified key areas for improvement"
})
```

#### Automatic Behavior

- **Parallel Execution**: Tasks marked with `mode = "read"` and no dependencies execute automatically in parallel
- **Dependency Management**: Tasks with dependencies are automatically blocked until prerequisites complete
- **Progress Tracking**: The system automatically advances to the next available task when one completes
- **Persistent Storage**: All checklists are saved and restored across Neovim sessions

## Supported Rule Files

The extension supports common rule file formats used by various AI tools:

- `.rules` - General rule files
- `.cursorrules` - Cursor AI rules
- `.goosehints` - Goose AI hints
- `.windsurfrules` - Windsurf rules
- `.clinerules` - Cline rules
- `.github/copilot-instructions.md` - GitHub Copilot instructions
- `AGENT.md`, `AGENTS.md` - Agent instructions
- `CLAUDE.md` - Claude-specific rules
- `.codecompanionrules` - CodeCompanion-specific rules

## Troubleshooting

### Extension Not Loading

If you see the error:
```
Error loading extension codecompanion-tools: module 'codecompanion._extensions.codecompanion-tools' not found
```

Ensure your directory structure matches the required layout above. The extension must be in:
```
lua/codecompanion/_extensions/codecompanion-tools/init.lua
```

### Rule Files Not Being Added

1. Enable debug mode: `rules = { debug = true }`
2. Check the output for path collection and rule discovery
3. Verify rule files exist in parent directories of referenced files
4. Ensure files are within your project root (`getcwd()`)

### Model Toggle Not Working

1. Verify you're in a CodeCompanion chat buffer (`filetype = "codecompanion"`)
2. Check that models are configured for your current adapter
3. Ensure the keymap isn't conflicting with other bindings

## Backward Compatibility

The original `require("codecompanion_tools").setup()` call is still supported and will automatically delegate to the proper extension.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

