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

	-- Setup DAG tools and register them automatically
	if opts.dag and opts.dag.enabled ~= false then
		M.dag_tools = require("codecompanion_tools.dag.checklist_tool")
		
		-- Auto-register tools with CodeCompanion
		local ok, codecompanion = pcall(require, "codecompanion")
		if ok and codecompanion.config then
			-- Ensure strategies.chat.tools exists
			if not codecompanion.config.strategies then
				codecompanion.config.strategies = {}
			end
			if not codecompanion.config.strategies.chat then
				codecompanion.config.strategies.chat = {}
			end
			if not codecompanion.config.strategies.chat.tools then
				codecompanion.config.strategies.chat.tools = {}
			end
			
			-- Register our tools
			for tool_name, tool_config in pairs(M.dag_tools) do
				codecompanion.config.strategies.chat.tools[tool_name] = tool_config
			end
		end
	end
end

--- Export functions
M.exports = {
	toggle_model = function(bufnr)
		return require("codecompanion_tools.model_toggle").exports.toggle_model(bufnr)
	end,
}

--- Return tools configuration for CodeCompanion
---@return table
function M.get_tools()
	return M.dag_tools or {}
end

return M
