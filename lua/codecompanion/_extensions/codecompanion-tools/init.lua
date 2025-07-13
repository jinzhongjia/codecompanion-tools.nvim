---@class CodeCompanion.Extension
local M = {}

--- Setup function for codecompanion-tools extension
---@param opts table Configuration options
function M.setup(opts)
	opts = opts or {}

	-- Setup rule manager if enabled
	if opts.rules and opts.rules.enabled ~= false then
		local ok, rules = pcall(require, "codecompanion_tools.rule")
		if ok then
			rules.setup(opts.rules or {})
		else
			vim.notify("Failed to load codecompanion_tools.rule", vim.log.levels.WARN)
		end
	end

	-- Setup model toggle if enabled
	if opts.model_toggle and opts.model_toggle.enabled ~= false then
		local ok, model_toggle = pcall(require, "codecompanion_tools.model_toggle")
		if ok then
			model_toggle.setup(opts.model_toggle or {})
		else
			vim.notify("Failed to load codecompanion_tools.model_toggle", vim.log.levels.WARN)
		end
	end
end

--- Export functions for external access
M.exports = {
	toggle_model = function(bufnr)
		local model_toggle = require("codecompanion_tools.model_toggle")
		return model_toggle.exports.toggle_model(bufnr)
	end,
}

return M
