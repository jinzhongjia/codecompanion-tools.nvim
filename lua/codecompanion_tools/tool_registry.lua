-- codecompanion_tools/tool_registry.lua
-- Tool Registration Utility for CodeCompanion
--
-- This module provides a centralized way to register custom tools with CodeCompanion.
-- It handles the complexity of finding and integrating with CodeCompanion's configuration
-- system, providing a simple interface for tool registration.
--
-- The registry supports multiple registration strategies to handle different CodeCompanion
-- configuration approaches and ensures backward compatibility.

local M = {}

-- Register tools with CodeCompanion
-- This function attempts to register tools with CodeCompanion by trying different
-- configuration access methods. It will try the most common approaches until
-- one succeeds.
--
---@param tools table A table of tool configurations where keys are tool names
---@param debug boolean Optional debug flag to enable verbose logging
---@return boolean success True if tools were successfully registered, false otherwise
function M.register_tools(tools, debug)
	debug = debug or false

	-- Define registration targets in order of preference
	-- Each target defines how to load and validate the CodeCompanion configuration
	local registration_targets = {
		-- Primary target: Direct config access
		-- This is the most common way to access CodeCompanion configuration
		{
			name = "codecompanion.config",
			loader = function()
				return require("codecompanion.config")
			end,
			validator = function(target)
				return target.strategies and target.strategies.chat
			end,
		},
		-- Fallback target: Main module with config property
		-- Some CodeCompanion setups expose config through the main module
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

	-- Attempt registration with each target until one succeeds
	for _, target in ipairs(registration_targets) do
		local ok, config_obj = pcall(target.loader)
		if ok and target.validator(config_obj) then
			-- Get the actual config object (may be nested)
			local config = target.config_path and target.config_path(config_obj) or config_obj

			if debug then
				print("[CodeCompanion-Tools] Registering tools via", target.name)
			end

			-- Initialize the configuration structure if it doesn't exist
			-- This ensures we can safely register tools regardless of the current config state
			if not config.strategies then
				config.strategies = {}
			end
			if not config.strategies.chat then
				config.strategies.chat = {}
			end
			if not config.strategies.chat.tools then
				config.strategies.chat.tools = {}
			end

			-- Register each tool in the configuration
			-- Tools are registered by name and their configuration is stored
			for tool_name, tool_config in pairs(tools) do
				config.strategies.chat.tools[tool_name] = tool_config
				if debug then
					print("[CodeCompanion-Tools] Registered tool:", tool_name)
				end
			end

			return true
		end
	end

	-- If we get here, none of the registration targets worked
	if debug then
		print("[CodeCompanion-Tools] Could not register tools - CodeCompanion config not found")
	end

	return false
end

return M
