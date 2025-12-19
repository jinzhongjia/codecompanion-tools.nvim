-- OAuth Adapters module for CodeCompanion
-- Provides OAuth-authenticated adapters for various AI providers

local M = {}

---@class AdaptersConfig
---@field anthropic_oauth? table|boolean Configuration for Anthropic OAuth adapter
---@field codex_oauth? table|boolean Configuration for Codex (ChatGPT) OAuth adapter
---@field gemini_oauth? table|boolean Configuration for Gemini OAuth adapter
---@field antigravity_oauth? table|boolean Configuration for Antigravity OAuth adapter

-- Available adapters with short names for commands
local available_adapters = {
  anthropic_oauth = {
    path = "codecompanion-tools.adapters.anthropic_oauth",
    short_name = "anthropic",
    display_name = "Anthropic",
  },
  codex_oauth = {
    path = "codecompanion-tools.adapters.codex_oauth",
    short_name = "codex",
    display_name = "Codex",
  },
  gemini_oauth = {
    path = "codecompanion-tools.adapters.gemini_oauth",
    short_name = "gemini",
    display_name = "Gemini",
  },
  antigravity_oauth = {
    path = "codecompanion-tools.adapters.antigravity_oauth",
    short_name = "antigravity",
    display_name = "Antigravity",
  },
}

-- Reverse lookup: short_name -> adapter_name
local short_name_lookup = {}
for adapter_name, info in pairs(available_adapters) do
  short_name_lookup[info.short_name] = adapter_name
end

-- Loaded adapter modules cache
local loaded_modules = {}

-- Loaded adapters cache
local loaded_adapters = {}

---Get adapter module by short name or full name
---@param name string Short name (e.g., "anthropic") or full name (e.g., "anthropic_oauth")
---@return table|nil module, string|nil adapter_name
local function get_adapter_module(name)
  -- Try short name first
  local adapter_name = short_name_lookup[name]
  if not adapter_name then
    -- Try full name
    if available_adapters[name] then
      adapter_name = name
    end
  end

  if not adapter_name then
    return nil, nil
  end

  -- Return cached module if available
  if loaded_modules[adapter_name] then
    return loaded_modules[adapter_name], adapter_name
  end

  -- Load the module
  local adapter_info = available_adapters[adapter_name]
  local ok, module = pcall(require, adapter_info.path)
  if ok then
    loaded_modules[adapter_name] = module
    return module, adapter_name
  end

  return nil, nil
end

---Execute adapter action
---@param adapter_name string
---@param action string
local function execute_adapter_action(adapter_name, action)
  local module, full_name = get_adapter_module(adapter_name)
  if not module then
    vim.notify(
      string.format("Unknown adapter: %s\nAvailable: anthropic, codex, gemini, antigravity", adapter_name),
      vim.log.levels.ERROR,
      { title = "CodeCompanion Tools" }
    )
    return
  end

  local adapter_info = available_adapters[full_name]
  local display_name = adapter_info.display_name

  if action == "auth" or action == "setup" then
    if module.setup_oauth then
      module.setup_oauth()
    else
      vim.notify(display_name .. " does not support OAuth setup", vim.log.levels.WARN)
    end
  elseif action == "status" then
    if module.show_status then
      module.show_status()
    else
      vim.notify(display_name .. " does not support status check", vim.log.levels.WARN)
    end
  elseif action == "clear" then
    if module.clear_tokens then
      module.clear_tokens()
    else
      vim.notify(display_name .. " does not support clearing tokens", vim.log.levels.WARN)
    end
  elseif action == "instructions" then
    -- Codex-specific action
    if module.update_instructions then
      module.update_instructions()
    else
      vim.notify(display_name .. " does not support updating instructions", vim.log.levels.WARN)
    end
  else
    vim.notify(
      string.format("Unknown action: %s\nAvailable: auth, status, clear%s", action, full_name == "codex_oauth" and ", instructions" or ""),
      vim.log.levels.ERROR,
      { title = "CodeCompanion Tools" }
    )
  end
end

---Setup unified command
local function setup_unified_command()
  vim.api.nvim_create_user_command("CCTools", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })

    if #args == 0 then
      -- Show help
      vim.notify(
        "Usage: CCTools adapter <name> <action>\n\n"
          .. "Adapters: anthropic, codex, gemini, antigravity\n"
          .. "Actions: auth, status, clear\n"
          .. "         instructions (codex only)\n\n"
          .. "Examples:\n"
          .. "  :CCTools adapter anthropic auth\n"
          .. "  :CCTools adapter codex status\n"
          .. "  :CCTools adapter gemini clear",
        vim.log.levels.INFO,
        { title = "CodeCompanion Tools" }
      )
      return
    end

    local subcommand = args[1]

    if subcommand == "adapter" then
      if #args < 3 then
        vim.notify(
          "Usage: CCTools adapter <name> <action>\n\n"
            .. "Adapters: anthropic, codex, gemini, antigravity\n"
            .. "Actions: auth, status, clear",
          vim.log.levels.WARN,
          { title = "CodeCompanion Tools" }
        )
        return
      end

      local adapter_name = args[2]
      local action = args[3]
      execute_adapter_action(adapter_name, action)
    else
      vim.notify(
        "Unknown subcommand: " .. subcommand .. "\nAvailable: adapter",
        vim.log.levels.ERROR,
        { title = "CodeCompanion Tools" }
      )
    end
  end, {
    nargs = "*",
    desc = "CodeCompanion Tools commands",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local args = vim.split(cmd_line, "%s+", { trimempty = true })
      local n_args = #args

      -- Remove "CCTools" from count if present
      if args[1] == "CCTools" then
        n_args = n_args - 1
        table.remove(args, 1)
      end

      -- Completing first argument (subcommand)
      if n_args == 0 or (n_args == 1 and not cmd_line:match("%s$")) then
        return vim.tbl_filter(function(item)
          return item:find(arg_lead, 1, true) == 1
        end, { "adapter" })
      end

      local subcommand = args[1]

      if subcommand == "adapter" then
        -- Completing adapter name
        if n_args == 1 or (n_args == 2 and not cmd_line:match("%s$")) then
          local adapters = { "anthropic", "codex", "gemini", "antigravity" }
          return vim.tbl_filter(function(item)
            return item:find(arg_lead, 1, true) == 1
          end, adapters)
        end

        -- Completing action
        if n_args == 2 or (n_args == 3 and not cmd_line:match("%s$")) then
          local adapter_name = args[2]
          local actions = { "auth", "status", "clear" }
          -- Add instructions for codex
          if adapter_name == "codex" then
            table.insert(actions, "instructions")
          end
          return vim.tbl_filter(function(item)
            return item:find(arg_lead, 1, true) == 1
          end, actions)
        end
      end

      return {}
    end,
  })
end

---Setup the adapters module
---@param opts AdaptersConfig
function M.setup(opts)
  opts = opts or {}

  -- Clear previously loaded adapters
  loaded_adapters = {}
  loaded_modules = {}

  -- Register adapters with CodeCompanion
  local cc_ok = pcall(require, "codecompanion")
  if not cc_ok then
    vim.notify("CodeCompanion not found, adapters module cannot be loaded", vim.log.levels.WARN, { title = "CodeCompanion Tools" })
    return
  end

  -- Get CodeCompanion config to register adapters
  local cc_config = require("codecompanion.config")

  for adapter_name, adapter_info in pairs(available_adapters) do
    local adapter_config = opts[adapter_name]

    -- Load adapter if configuration is not false
    if adapter_config ~= false then
      local ok, adapter_module = pcall(require, adapter_info.path)
      if ok then
        -- Cache the module
        loaded_modules[adapter_name] = adapter_module

        -- Create and register the adapter
        local adapter = adapter_module.create_adapter()
        if adapter then
          -- Register the adapter in CodeCompanion's adapter list
          cc_config.adapters.http[adapter.name] = function()
            return adapter
          end

          loaded_adapters[adapter_name] = adapter
        end
      else
        vim.notify(
          string.format("Failed to load adapter '%s': %s", adapter_name, adapter_module),
          vim.log.levels.WARN,
          { title = "CodeCompanion Tools" }
        )
      end
    end
  end

  -- Setup unified command
  setup_unified_command()
end

---Get a loaded adapter by name
---@param name string Adapter name
---@return table|nil
function M.get_adapter(name)
  return loaded_adapters[name]
end

---Get all loaded adapters
---@return table<string, table>
function M.get_all_adapters()
  return loaded_adapters
end

---Get list of loaded adapter names
---@return string[]
function M.loaded_adapter_names()
  local names = {}
  for name, _ in pairs(loaded_adapters) do
    table.insert(names, name)
  end
  return names
end

return M
