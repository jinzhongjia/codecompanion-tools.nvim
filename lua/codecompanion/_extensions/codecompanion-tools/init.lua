---@class CodeCompanion.Extension
local M = {}

--- Setup codecompanion-tools extension
---@param opts table Configuration options
function M.setup(opts)
	opts = opts or {}

	-- Setup rule manager
	if opts.rules and opts.rules.enabled ~= false then
		require("codecompanion_tools.rule").setup(opts.rules or {})
	end

	-- Setup model toggle
	if opts.model_toggle and opts.model_toggle.enabled ~= false then
		require("codecompanion_tools.model_toggle").setup(opts.model_toggle or {})
	end
end

--- Export functions
M.exports = {
	toggle_model = function(bufnr)
		return require("codecompanion_tools.model_toggle").exports.toggle_model(bufnr)
	end,
}

return M
