-- codecompanion_tools/context_compression/trigger_detector.lua
-- Trigger condition detection for context compression

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- Calculate approximate token count for text
---@param text string
---@return number
local function calculate_token_count(text)
	if not text or text == "" then
		return 0
	end

	-- Improved token counting approximation
	local token_count = 0

	-- Count words (more accurate than character/4)
	local word_count = 0
	for word in text:gmatch("%S+") do
		word_count = word_count + 1
	end

	-- Count special tokens
	local special_tokens = 0
	-- Code blocks
	for _ in text:gmatch("```[^`]*```") do
		special_tokens = special_tokens + 10 -- Code blocks are token-heavy
	end

	-- URLs
	for _ in text:gmatch("https?://[%w%.%-%/%?%=%%&]+") do
		special_tokens = special_tokens + 5
	end

	-- Numbers and identifiers
	for _ in text:gmatch("%d+") do
		special_tokens = special_tokens + 1
	end

	-- Punctuation marks
	for _ in text:gmatch("[%p]") do
		special_tokens = special_tokens + 1
	end

	-- Improved formula: base word count + special tokens + character penalty
	token_count = word_count + special_tokens + math.ceil(string.len(text) / 6)

	return token_count
end

--- Get current memory usage (simplified)
---@return number Memory usage in MB
local function get_memory_usage()
	-- Simple memory usage approximation
	local meminfo = vim.fn.luaeval("collectgarbage('count')")
	return meminfo / 1024 -- Convert KB to MB
end

--- Extract messages from chat object
---@param chat table
---@return table messages
local function extract_messages(chat)
	local messages = {}

	if not chat or not chat.messages then
		return messages
	end

	for _, message in ipairs(chat.messages) do
		if message.content then
			table.insert(messages, message)
		end
	end

	return messages
end

--- Calculate total content length from messages
---@param messages table
---@return number total_length
local function calculate_total_content_length(messages)
	local total_length = 0

	for _, message in ipairs(messages) do
		if message.content then
			total_length = total_length + string.len(message.content)
		end
	end

	return total_length
end

--- Check if compression should be triggered
---@param chat table Chat object
---@return boolean should_compress
---@return string compression_urgency "green" | "yellow" | "red"
---@return table trigger_reasons
function M.should_compress(chat)
	local debug = config.is_debug()

	if not chat then
		if debug then
			print("[Context Compression] No chat object provided")
		end
		return false, "green", {}
	end

	local messages = extract_messages(chat)
	local message_count = #messages
	local total_content_length = calculate_total_content_length(messages)
	local token_count = calculate_token_count(table.concat(
		vim.tbl_map(function(msg)
			return msg.content or ""
		end, messages),
		"\n"
	))
	local memory_usage = get_memory_usage()

	local token_threshold = config.get("token_threshold")
	local memory_threshold = config.get("memory_threshold")
	local message_count_threshold = config.get("message_count_threshold")

	if debug then
		print(
			string.format(
				"[Context Compression] Stats: messages=%d, tokens=%d, memory=%.2fMB, content_length=%d",
				message_count,
				token_count,
				memory_usage,
				total_content_length
			)
		)
		print(
			string.format(
				"[Context Compression] Thresholds: messages=%d, tokens=%d, memory=%dMB",
				message_count_threshold,
				token_threshold,
				memory_threshold
			)
		)
	end

	local trigger_reasons = {}
	local urgency_score = 0

	-- Check token count
	if token_count > token_threshold then
		table.insert(trigger_reasons, "token_count_exceeded")
		urgency_score = urgency_score + (token_count / token_threshold)
	elseif token_count > token_threshold * 0.8 then
		table.insert(trigger_reasons, "token_count_warning")
		urgency_score = urgency_score + 0.5
	end

	-- Check memory usage
	if memory_usage > memory_threshold then
		table.insert(trigger_reasons, "memory_usage_exceeded")
		urgency_score = urgency_score + (memory_usage / memory_threshold)
	elseif memory_usage > memory_threshold * 0.8 then
		table.insert(trigger_reasons, "memory_usage_warning")
		urgency_score = urgency_score + 0.3
	end

	-- Check message count
	if message_count > message_count_threshold then
		table.insert(trigger_reasons, "message_count_exceeded")
		urgency_score = urgency_score + (message_count / message_count_threshold)
	elseif message_count > message_count_threshold * 0.8 then
		table.insert(trigger_reasons, "message_count_warning")
		urgency_score = urgency_score + 0.2
	end

	-- Determine urgency level
	local urgency
	if urgency_score >= 1.5 then
		urgency = "red" -- Critical: immediate compression required
	elseif urgency_score >= 0.8 then
		urgency = "yellow" -- Warning: compression recommended
	else
		urgency = "green" -- Normal: no compression needed
	end

	local should_compress = urgency ~= "green"

	if debug then
		print(
			string.format(
				"[Context Compression] Decision: compress=%s, urgency=%s, score=%.2f, reasons=%s",
				tostring(should_compress),
				urgency,
				urgency_score,
				vim.inspect(trigger_reasons)
			)
		)
	end

	return should_compress, urgency, trigger_reasons
end

--- Get detailed compression statistics
---@param chat table Chat object
---@return table stats
function M.get_compression_stats(chat)
	if not chat then
		return {
			message_count = 0,
			token_count = 0,
			memory_usage = 0,
			total_content_length = 0,
			compression_needed = false,
			urgency = "green",
			trigger_reasons = {},
		}
	end

	local messages = extract_messages(chat)
	local message_count = #messages
	local total_content_length = calculate_total_content_length(messages)
	local token_count = calculate_token_count(table.concat(
		vim.tbl_map(function(msg)
			return msg.content or ""
		end, messages),
		"\n"
	))
	local memory_usage = get_memory_usage()

	local should_compress, urgency, trigger_reasons = M.should_compress(chat)

	return {
		message_count = message_count,
		token_count = token_count,
		memory_usage = memory_usage,
		total_content_length = total_content_length,
		compression_needed = should_compress,
		urgency = urgency,
		trigger_reasons = trigger_reasons,
		thresholds = {
			token_threshold = config.get("token_threshold"),
			memory_threshold = config.get("memory_threshold"),
			message_count_threshold = config.get("message_count_threshold"),
		},
	}
end

--- Check if auto-trigger is enabled
---@return boolean
function M.is_auto_trigger_enabled()
	return config.get("auto_trigger") and config.get("enabled")
end

--- Monitor chat for compression triggers
---@param chat table Chat object
---@param callback function Callback function to execute when compression is needed
function M.monitor_chat(chat, callback)
	if not M.is_auto_trigger_enabled() then
		return
	end

	local function check_trigger()
		local should_compress, urgency, reasons = M.should_compress(chat)

		if should_compress and callback then
			callback(chat, urgency, reasons)
		end
	end

	-- Initial check
	check_trigger()

	-- Set up timer for periodic checking (every 30 seconds)
	local timer = vim.loop.new_timer()
	if timer then
		timer:start(
			30000,
			30000,
			vim.schedule_wrap(function()
				if chat and vim.api.nvim_buf_is_valid(chat.bufnr or -1) then
					check_trigger()
				else
					-- Stop timer if chat buffer is no longer valid
					timer:stop()
					timer:close()
				end
			end)
		)
	end
end

return M
