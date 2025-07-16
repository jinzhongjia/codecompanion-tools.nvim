-- codecompanion_tools/context_compression/strategies/simple_truncation.lua
-- Simple truncation strategy for context compression (MVP)

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- Strategy information
M.name = "simple_truncation"
M.description = "Simple truncation strategy that keeps recent messages"
M.cost = 0.2
M.quality = 0.5

--- Check if message should be preserved
---@param message table Message object
---@return boolean should_preserve
local function should_preserve_message(message)
	if not message or not message.content then
		return false
	end

	-- Always keep system messages
	if message.role == "system" then
		return true
	end

	-- Keep context markers and references
	if config.get("simple_truncation.preserve_context_markers") then
		local content = message.content
		if content:match("^>") or content:match("^%[") or content:match("^%#") then
			return true
		end
	end

	return false
end

--- Sort messages by timestamp (newest first)
---@param messages table Array of message objects
---@return table sorted_messages
local function sort_messages_by_time(messages)
	local sorted = vim.deepcopy(messages)

	table.sort(sorted, function(a, b)
		-- If timestamps are available, use them
		if a.timestamp and b.timestamp then
			return a.timestamp > b.timestamp
		end

		-- Otherwise, assume array order represents chronological order
		-- Find their original indices
		local a_index, b_index = 0, 0
		for i, msg in ipairs(messages) do
			if msg == a then
				a_index = i
			end
			if msg == b then
				b_index = i
			end
		end

		return a_index > b_index
	end)

	return sorted
end

--- Compress messages using simple truncation
---@param messages table Array of message objects
---@return table compressed_messages
---@return table compression_stats
function M.compress(messages)
	local debug = config.is_debug()

	if debug then
		print("[Simple Truncation] Starting compression with", #messages, "messages")
	end

	local keep_recent = config.get("simple_truncation.keep_recent_messages") or 5
	local keep_system = config.get("simple_truncation.keep_system_messages") or true

	local compressed_messages = {}
	local preserved_count = 0
	local removed_count = 0

	-- First pass: collect system messages and important markers
	local system_messages = {}
	local important_messages = {}
	local regular_messages = {}

	for _, message in ipairs(messages) do
		if message.role == "system" and keep_system then
			table.insert(system_messages, message)
		elseif should_preserve_message(message) then
			table.insert(important_messages, message)
		else
			table.insert(regular_messages, message)
		end
	end

	-- Sort regular messages by time (newest first)
	local sorted_regular = sort_messages_by_time(regular_messages)

	-- Keep system messages
	for _, msg in ipairs(system_messages) do
		table.insert(compressed_messages, msg)
		preserved_count = preserved_count + 1
	end

	-- Keep important messages
	for _, msg in ipairs(important_messages) do
		table.insert(compressed_messages, msg)
		preserved_count = preserved_count + 1
	end

	-- Keep recent regular messages
	local recent_count = 0
	for _, msg in ipairs(sorted_regular) do
		if recent_count < keep_recent then
			table.insert(compressed_messages, msg)
			preserved_count = preserved_count + 1
			recent_count = recent_count + 1
		else
			removed_count = removed_count + 1
		end
	end

	-- Add compression summary if messages were removed
	if removed_count > 0 then
		local summary_message = {
			role = "system",
			content = string.format(
				"## 上下文压缩摘要\n\n"
					.. "为了优化性能，已压缩部分历史对话内容。\n\n"
					.. "- 保留消息数: %d\n"
					.. "- 移除消息数: %d\n"
					.. "- 保留了系统消息、重要标记和最近 %d 条消息\n\n"
					.. "---\n",
				preserved_count,
				removed_count,
				keep_recent
			),
			timestamp = os.time(),
			compression_marker = true,
		}

		table.insert(compressed_messages, 1, summary_message)
	end

	-- Restore chronological order
	table.sort(compressed_messages, function(a, b)
		if a.compression_marker then
			return true
		end
		if b.compression_marker then
			return false
		end

		if a.timestamp and b.timestamp then
			return a.timestamp < b.timestamp
		end

		-- Fallback to original order approximation
		return false
	end)

	local compression_stats = {
		strategy = M.name,
		original_count = #messages,
		compressed_count = #compressed_messages,
		removed_count = removed_count,
		preserved_count = preserved_count,
		compression_ratio = removed_count / #messages,
		system_messages_kept = #system_messages,
		important_messages_kept = #important_messages,
		recent_messages_kept = recent_count,
	}

	if debug then
		print("[Simple Truncation] Compression completed:", vim.inspect(compression_stats))
	end

	return compressed_messages, compression_stats
end

--- Validate if compression is possible
---@param messages table Array of message objects
---@return boolean can_compress
---@return string? error_message
function M.validate(messages)
	if not messages or type(messages) ~= "table" then
		return false, "Invalid messages array"
	end

	if #messages == 0 then
		return false, "No messages to compress"
	end

	local keep_recent = config.get("simple_truncation.keep_recent_messages") or 5

	if #messages <= keep_recent then
		return false, "Message count is below threshold for compression"
	end

	return true
end

--- Get strategy configuration
---@return table strategy_config
function M.get_config()
	return {
		name = M.name,
		description = M.description,
		cost = M.cost,
		quality = M.quality,
		settings = config.get("simple_truncation") or {},
	}
end

-- Set strategy attributes
M.quality = 0.6
M.cost = 0.2

--- Update strategy configuration
---@param new_config table New configuration values
function M.update_config(new_config)
	if type(new_config) ~= "table" then
		return false, "Configuration must be a table"
	end

	for key, value in pairs(new_config) do
		config.set("simple_truncation." .. key, value)
	end

	return true
end

return M
