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
-- - DAG tools: Checklist tools with dependency management
-- - Context compression: Chat context compression system
--
-- The extension follows CodeCompanion's extension architecture and provides
-- both setup configuration and runtime tool access.
local M = {}

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

	-- Setup DAG tools
	if opts.dag and opts.dag.enabled ~= false then
		if debug then
			print("[CodeCompanion-Tools] DAG is enabled, loading checklist tool...")
		end

		M.dag_tools = require("codecompanion_tools.dag.checklist_tool")

		if debug then
			print("[CodeCompanion-Tools] Loaded DAG tools:", vim.inspect(vim.tbl_keys(M.dag_tools)))
		end

		-- Register tools with CodeCompanion
		local tool_registry = require("codecompanion_tools.tool_registry")
		local success = tool_registry.register_tools(M.dag_tools, debug)

		if debug then
			print("[CodeCompanion-Tools] Tool registration success:", success)
		end
	else
		if debug then
			print("[CodeCompanion-Tools] DAG is disabled")
		end
	end

	-- Setup context compression
	if opts.context_compression and opts.context_compression.enabled ~= false then
		if debug then
			print("[CodeCompanion-Tools] Setting up context compression...")
		end

		-- Pass global debug to context compression
		local compression_opts = vim.tbl_deep_extend("force", opts.context_compression or {}, { debug = debug })
		local compression_module = require("codecompanion_tools.context_compression")
		compression_module.setup(compression_opts)
		compression_module.init()

		-- 注意：压缩工具已移除，但保留核心功能
		M.compression_tools = {}

		if debug then
			print("[CodeCompanion-Tools] Context compression core functionality loaded (tools removed)")
		end
	else
		if debug then
			print("[CodeCompanion-Tools] Context compression is disabled")
		end
	end

	-- Create debug command for troubleshooting
	-- This command provides detailed information about the extension state
	vim.api.nvim_create_user_command("CodeCompanionToolsDebug", function()
		print("=== CodeCompanion Tools Debug ===")
		print("Extension loaded:", M ~= nil)
		print("Global debug mode:", M.debug or false)
		print("DAG tools:", M.dag_tools and vim.inspect(vim.tbl_keys(M.dag_tools)) or "nil")
		print("Compression tools:", "removed (core functionality available via commands)")

		local ok, codecompanion = pcall(require, "codecompanion")
		if ok and codecompanion.config then
			print("CodeCompanion config exists:", codecompanion.config ~= nil)
			print("Strategies config:", codecompanion.config.strategies ~= nil)
			print("Chat config:", codecompanion.config.strategies and codecompanion.config.strategies.chat ~= nil)
			print(
				"Tools config:",
				codecompanion.config.strategies
					and codecompanion.config.strategies.chat
					and codecompanion.config.strategies.chat.tools ~= nil
			)

			if
				codecompanion.config.strategies
				and codecompanion.config.strategies.chat
				and codecompanion.config.strategies.chat.tools
			then
				print("Registered tools:", vim.inspect(vim.tbl_keys(codecompanion.config.strategies.chat.tools)))
			end
		else
			print("Failed to load CodeCompanion")
		end
	end, {})
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
	-- Return only DAG tools (compression tools were removed from CodeCompanion integration)
	-- Other tools are available via commands but not as CodeCompanion chat tools
	return M.dag_tools or {}
end

return M
