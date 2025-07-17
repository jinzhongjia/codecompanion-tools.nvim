---@class CodeCompanion.Extension
-- CodeCompanion Tools Extension
--
-- This is the main extension module that integrates codecompanion-tools with CodeCompanion.
-- It provides a centralized setup interface for all tool components and handles the
-- registration of tools with CodeCompanion.
--
-- Components managed by this extension:
-- - Rule manager: Automated workflow rules
-- - Model toggle: Quick model switching utilities
-- - DAG tools: Checklist tools with dependency management (via adapter)
-- - Context compression: Chat context compression system (via adapter)
--
-- The extension follows CodeCompanion's extension architecture and provides
-- both setup configuration and runtime tool access.
local M = {}

-- 适配器注册表
local adapters = {}

--- Setup codecompanion-tools extension
-- This function initializes all components of the codecompanion-tools extension
-- based on the provided configuration options.
--
---@param opts table Configuration options with component-specific settings
function M.setup(opts)
	opts = opts or {}

	-- Global debug setting
	local debug = opts.debug or false
	M.debug = debug

	if debug then
		print("[CodeCompanion-Tools] Extension setup started with debug mode enabled")
		print("[CodeCompanion-Tools] Options:", vim.inspect(opts))
	end

	-- Setup rule manager
	if opts.rules and opts.rules.enabled ~= false then
		if debug then
			print("[CodeCompanion-Tools] Setting up rule manager...")
		end
		-- Pass global debug to rule manager
		local rule_opts = vim.tbl_deep_extend("force", opts.rules or {}, { debug = debug })
		require("codecompanion_tools.rule").setup(rule_opts)
	end

	-- Setup model toggle
	if opts.model_toggle and opts.model_toggle.enabled ~= false then
		if debug then
			print("[CodeCompanion-Tools] Setting up model toggle...")
		end
		-- Pass global debug to model toggle
		local model_opts = vim.tbl_deep_extend("force", opts.model_toggle or {}, { debug = debug })
		require("codecompanion_tools.model_toggle").setup(model_opts)
	end

	-- Setup DAG adapter
	if opts.dag ~= false then
		if debug then
			print("[CodeCompanion-Tools] Setting up DAG adapter...")
		end
		local dag_adapter = require("codecompanion_tools.adapters.dag_adapter")
		adapters.dag = dag_adapter
		local dag_opts = vim.tbl_deep_extend("force", opts.dag or {}, { debug = debug })
		dag_adapter:setup(dag_opts)
	else
		if debug then
			print("[CodeCompanion-Tools] DAG adapter is disabled")
		end
	end

	-- Setup context compression adapter
	if opts.compression ~= false then
		if debug then
			print("[CodeCompanion-Tools] Setting up context compression adapter...")
		end
		local compression_adapter = require("codecompanion_tools.adapters.compression_adapter")
		adapters.compression = compression_adapter
		local compression_opts = vim.tbl_deep_extend("force", opts.compression or {}, { debug = debug })
		compression_adapter:setup(compression_opts)
	else
		if debug then
			print("[CodeCompanion-Tools] Context compression adapter is disabled")
		end
	end

	-- 注册所有适配器的工具到 CodeCompanion
	local all_tools = {}
	for name, adapter in pairs(adapters) do
		local tools = adapter:get_tools()
		for tool_name, tool_config in pairs(tools) do
			all_tools[tool_name] = tool_config
		end
		if debug then
			print("[CodeCompanion-Tools] Registered tools from adapter:", name, vim.inspect(vim.tbl_keys(tools)))
		end
	end

	-- Register tools with CodeCompanion
	if next(all_tools) then
		local tool_registry = require("codecompanion_tools.tool_registry")
		local success = tool_registry.register_tools(all_tools, debug)
		if debug then
			print("[CodeCompanion-Tools] Tool registration success:", success)
		end
	end
end

--- Export functions for external use
-- These functions provide programmatic access to tool functionality
M.exports = {
	-- Toggle model function - switches between different LLM models
	toggle_model = function(bufnr)
		return require("codecompanion_tools.model_toggle").exports.toggle_model(bufnr)
	end,
}

--- Return tools configuration for CodeCompanion
-- This function provides the tool definitions that CodeCompanion will register
---@return table Tool definitions for CodeCompanion integration
function M.get_tools()
	-- Return all tools from adapters
	local all_tools = {}
	for name, adapter in pairs(adapters) do
		local tools = adapter:get_tools()
		for tool_name, tool_config in pairs(tools) do
			all_tools[tool_name] = tool_config
		end
	end
	return all_tools
end

--- Get adapter by name
-- This function provides access to specific adapters
---@param name string Adapter name
---@return table|nil Adapter instance
function M.get_adapter(name)
	return adapters[name]
end

return M
