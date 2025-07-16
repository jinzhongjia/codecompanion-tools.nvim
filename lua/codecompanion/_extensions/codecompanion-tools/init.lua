---@class CodeCompanion.Extension
local M = {}

--- Setup codecompanion-tools extension
---@param opts table Configuration options
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

	-- Create debug command
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

--- Export functions
M.exports = {
	toggle_model = function(bufnr)
		return require("codecompanion_tools.model_toggle").exports.toggle_model(bufnr)
	end,
}

--- Return tools configuration for CodeCompanion
---@return table
function M.get_tools()
	-- Only return DAG tools (compression tools removed)
	return M.dag_tools or {}
end

return M
