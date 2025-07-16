-- codecompanion_tools/tool_registry.lua
-- Simplified tool registration utility

local M = {}

-- Register tools with CodeCompanion
---@param tools table
---@param debug boolean
---@return boolean success
function M.register_tools(tools, debug)
	debug = debug or false

	-- Try codecompanion.config first, then fall back to codecompanion module
	local registration_targets = {
		{
			name = "codecompanion.config",
			loader = function()
				return require("codecompanion.config")
			end,
			validator = function(target)
				return target.strategies and target.strategies.chat
			end,
		},
		{
			name = "codecompanion module",
			loader = function()
				return require("codecompanion")
			end,
			validator = function(target)
				return target.config
			end,
			config_path = function(target)
				return target.config
			end,
		},
	}

	for _, target in ipairs(registration_targets) do
		local ok, config_obj = pcall(target.loader)
		if ok and target.validator(config_obj) then
			local config = target.config_path and target.config_path(config_obj) or config_obj

			if debug then
				print("[CodeCompanion-Tools] Registering tools via", target.name)
			end

			-- Ensure tools table exists
			if not config.strategies then
				config.strategies = {}
			end
			if not config.strategies.chat then
				config.strategies.chat = {}
			end
			if not config.strategies.chat.tools then
				config.strategies.chat.tools = {}
			end

			-- Register tools
			for tool_name, tool_config in pairs(tools) do
				config.strategies.chat.tools[tool_name] = tool_config
				if debug then
					print("[CodeCompanion-Tools] Registered tool:", tool_name)
				end
			end

			return true
		end
	end

	if debug then
		print("[CodeCompanion-Tools] Could not register tools - CodeCompanion config not found")
	end

	return false
end

return M
