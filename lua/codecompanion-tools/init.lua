local M = {}

---@class CodeCompanionToolsConfig
---@field translator table|nil Translator module configuration
---@field modules table<string, boolean|table> Module enable status and configuration

-- Available modules list
local available_modules = {
  translator = "codecompanion-tools.translator",
  -- Future modules can be added, for example:
  -- formatter = "codecompanion-tools.formatter",
  -- refactor = "codecompanion-tools.refactor",
  -- docgen = "codecompanion-tools.docgen",
}

---Setup entry for codecompanion-tools
---@param opts CodeCompanionToolsConfig
function M.setup(opts)
  opts = opts or {}

  -- Check if CodeCompanion is available
  local utils = require("codecompanion-tools.common.utils")
  if not utils.check_codecompanion() then
    return
  end

  -- Load each module
  for module_name, module_path in pairs(available_modules) do
    local module_config = opts[module_name]

    -- Load module if configuration is not false
    if module_config ~= false then
      local ok, module = pcall(require, module_path)
      if ok then
        -- Use default config if configuration is true or nil
        -- Use user config if configuration is table
        local config = (type(module_config) == "table") and module_config or {}
        module.setup(config)

        -- Record loaded modules
        M[module_name] = module
      else
        vim.notify(
          string.format("Failed to load module '%s': %s", module_name, module),
          vim.log.levels.WARN,
          { title = "CodeCompanion Tools" }
        )
      end
    end
  end
end

-- Get list of loaded modules
function M.loaded_modules()
  local modules = {}
  for name, _ in pairs(available_modules) do
    if M[name] then
      table.insert(modules, name)
    end
  end
  return modules
end

-- Health check
function M.health()
  local health = vim.health

  health.start("CodeCompanion Tools")

  -- Check CodeCompanion
  local cc_ok = pcall(require, "codecompanion")
  if cc_ok then
    health.ok("CodeCompanion is installed")
  else
    health.error("CodeCompanion is not installed")
    return
  end

  -- Check loaded modules
  local loaded = M.loaded_modules()
  if #loaded > 0 then
    health.ok(string.format("Loaded modules: %s", table.concat(loaded, ", ")))
  else
    health.warn("No modules loaded")
  end
end

return M
