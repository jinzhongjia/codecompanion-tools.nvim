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

		-- Try to register tools using the correct method according to documentation
		local success = false

		-- Method 1: Use codecompanion.config directly (recommended approach)
		local config_ok, config = pcall(require, "codecompanion.config")
		if config_ok and config.strategies and config.strategies.chat then
			if debug then
				print("[CodeCompanion-Tools] Found codecompanion.config, registering tools...")
			end

			if not config.strategies.chat.tools then
				config.strategies.chat.tools = {}
			end

			for tool_name, tool_config in pairs(M.dag_tools) do
				config.strategies.chat.tools[tool_name] = tool_config
				if debug then
					print("[CodeCompanion-Tools] Registered tool via config: " .. tool_name)
				end
			end
			success = true
		end

		-- Method 2: Fallback to codecompanion module
		if not success then
			local cc_ok, codecompanion = pcall(require, "codecompanion")
			if cc_ok and codecompanion.config then
				if debug then
					print("[CodeCompanion-Tools] Using codecompanion module config...")
				end

				if not codecompanion.config.strategies then
					codecompanion.config.strategies = {}
				end
				if not codecompanion.config.strategies.chat then
					codecompanion.config.strategies.chat = {}
				end
				if not codecompanion.config.strategies.chat.tools then
					codecompanion.config.strategies.chat.tools = {}
				end

				for tool_name, tool_config in pairs(M.dag_tools) do
					codecompanion.config.strategies.chat.tools[tool_name] = tool_config
					if debug then
						print("[CodeCompanion-Tools] Registered tool via codecompanion: " .. tool_name)
					end
				end
				success = true
			end
		end

		-- Method 3: Store for later retrieval
		if not success and debug then
			print("[CodeCompanion-Tools] Could not register tools directly, storing for later retrieval")
		end

		if debug then
			print("[CodeCompanion-Tools] Tool registration success:", success)
		end
	else
		if debug then
			print("[CodeCompanion-Tools] DAG is disabled")
		end
	end

	-- Create debug command
	vim.api.nvim_create_user_command("CodeCompanionToolsDebug", function()
		print("=== CodeCompanion Tools Debug ===")
		print("Extension loaded:", M ~= nil)
		print("Global debug mode:", M.debug or false)
		print("DAG tools:", M.dag_tools and vim.inspect(vim.tbl_keys(M.dag_tools)) or "nil")

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
	-- Only show debug info if DAG debug is enabled
	-- We don't have access to opts here, so we'll make this always silent
	return M.dag_tools or {}
end

return M
