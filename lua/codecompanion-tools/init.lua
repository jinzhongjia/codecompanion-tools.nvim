local M = {}

---@class CodeCompanionToolsConfig
---@field translator table|nil

---Setup entry for codecompanion-tools
---@param opts CodeCompanionToolsConfig
function M.setup(opts)
  opts = opts or {}
  if opts.translator ~= false then
    require("codecompanion-tools.translator").setup(opts.translator or {})
  end
end

return M
