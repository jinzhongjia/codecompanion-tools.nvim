-- codecompanion_tools/context_compression/init.lua
-- Context compression module entry point

local config = require("codecompanion_tools.context_compression.config")
local compression_manager = require("codecompanion_tools.context_compression.compression_manager")

local M = {}

--- Setup context compression
---@param opts table Configuration options
function M.setup(opts)
	config.setup(opts)
	compression_manager.init()

	if config.is_debug() then
		print("[Context Compression] Setup completed")
	end
end

--- Compress context for a specific chat
---@param chat table Chat object
---@param options table? Compression options
---@return boolean success
---@return string? error_message
---@return table? compression_stats
function M.compress_context(chat, options)
	return compression_manager.compress_context(chat, options)
end

--- Get compression statistics
---@param chat table Chat object
---@return table stats
function M.get_compression_stats(chat)
	return compression_manager.get_compression_stats(chat)
end

--- Check if compression is recommended
---@param chat table Chat object
---@return boolean recommended
---@return string urgency
---@return table reasons
function M.is_compression_recommended(chat)
	return compression_manager.is_compression_recommended(chat)
end

--- Get strategy recommendations
---@param chat table Chat object
---@return table recommendations
function M.get_strategy_recommendations(chat)
	return compression_manager.get_strategy_recommendations(chat)
end

--- Monitor chat for automatic compression
---@param chat table Chat object
function M.monitor_chat(chat)
	return compression_manager.monitor_chat(chat)
end

--- Get compression tools for CodeCompanion
---@return table tools
function M.get_compression_tools()
	-- 工具已移除，返回空表
	return {}
end

--- Create user commands (removed)
local function create_user_commands()
	-- 所有用户命令已移除，只保留自动压缩功能
end

--- Setup keymaps for compression (removed)
local function setup_keymaps()
	-- 快捷键功能已移除
	-- 使用 :CodeCompanionCompress 命令代替
end

--- Initialize context compression
function M.init()
	create_user_commands()
	setup_keymaps()

	if config.is_debug() then
		print("[Context Compression] Initialization completed")
	end
end

--- Get configuration
---@return table
function M.get_config()
	return config.get_config()
end

--- Update configuration
---@param new_config table
function M.update_config(new_config)
	config.setup(new_config)
end

return M
