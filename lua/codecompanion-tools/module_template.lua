-- This is a module template, new modules can reference this structure
-- Copy this file to a new module directory and modify

local M = {}

-- Module configuration
local config = {
  -- Default configuration
}

-- Module core functionality
local function core_function()
  -- Implement core functionality
end

-- Setup function
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Create command
  vim.api.nvim_create_user_command("CodeCompanionYourModule", function(cmd)
    -- Command handling logic
  end, {
    nargs = "*",
    desc = "Your module description",
  })
end

return M
