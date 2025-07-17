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

	-- Setup adapters
	local adapter_configs = {
		dag = { module = "codecompanion_tools.adapters.dag_adapter", default_enabled = true },
		compression = { module = "codecompanion_tools.adapters.compression_adapter", default_enabled = true },
	}

	local all_tools = {}
	for name, config in pairs(adapter_configs) do
		if opts[name] ~= false then
			if debug then
				print("[CodeCompanion-Tools] Setting up", name, "adapter...")
			end
			local adapter = require(config.module)
			adapters[name] = adapter
			local adapter_opts = vim.tbl_deep_extend("force", opts[name] or {}, { debug = debug })
			adapter:setup(adapter_opts)

			-- Collect tools
			local tools = adapter:get_tools()
			for tool_name, tool_config in pairs(tools) do
				all_tools[tool_name] = tool_config
			end
			if debug and next(tools) then
				print("[CodeCompanion-Tools] Registered tools from", name, "adapter:", vim.inspect(vim.tbl_keys(tools)))
			end
		end
	end

	-- Register all tools
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
