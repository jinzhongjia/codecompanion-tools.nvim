-- codecompanion_tools/context_compression/compression_manager.lua
-- Core compression management logic

local config = require("codecompanion_tools.context_compression.config")
local trigger_detector = require("codecompanion_tools.context_compression.trigger_detector")
local strategy_selector = require("codecompanion_tools.context_compression.strategy_selector")
local quality_assessor = require("codecompanion_tools.context_compression.quality_assessor")
local chat_utils = require("codecompanion_tools.chat")

local M = {}

--- Initialize compression manager
function M.init()
	strategy_selector.init()

	if config.is_debug() then
		print("[Compression Manager] Initialized")
	end
end

--- Extract messages from chat object
---@param chat table Chat object
---@return table messages
local function extract_messages_from_chat(chat)
	local messages = {}

	if not chat or not chat.messages then
		return messages
	end

	for _, message in ipairs(chat.messages) do
		if message.content and message.content ~= "" then
			table.insert(messages, {
				role = message.role or "user",
				content = message.content,
				timestamp = message.timestamp or os.time(),
				id = message.id,
			})
		end
	end

	return messages
end

--- Apply compressed messages back to chat
---@param chat table Chat object
---@param compressed_messages table Compressed messages
---@param compression_stats table Compression statistics
local function apply_compressed_messages_to_chat(chat, compressed_messages, compression_stats)
	local debug = config.is_debug()

	if debug then
		print("[Compression Manager] Applying", #compressed_messages, "compressed messages to chat")
	end

	-- Clear existing messages
	chat.messages = {}

	-- Add compressed messages
	for _, message in ipairs(compressed_messages) do
		table.insert(chat.messages, {
			role = message.role,
			content = message.content,
			timestamp = message.timestamp,
			id = message.id or (vim.fn and vim.fn.localtime()) or os.time(),
		})
	end

	-- Re-render chat context (only if in real nvim environment)
	if chat_utils and chat_utils.rerender_context then
		pcall(chat_utils.rerender_context, chat)
	end

	-- Show notification if enabled (only if in real nvim environment)
	if config.get("ui.auto_notify") and vim.notify then
		local message = string.format(
			"Context compressed: %d → %d messages (%.1f%% reduction)",
			compression_stats.original_count,
			compression_stats.compressed_count,
			compression_stats.compression_ratio * 100
		)
		vim.notify(message, vim.log.levels.INFO, { title = "CodeCompanion Context Compression" })
	end

	if debug then
		print("[Compression Manager] Applied compression:", vim.inspect(compression_stats))
	end
end

--- Compress chat context
---@param chat table Chat object
---@param options table? Compression options
---@return boolean success
---@return string? error_message
---@return table? compression_stats
function M.compress_context(chat, options)
	local debug = config.is_debug()
	options = options or {}

	if debug then
		print("[Compression Manager] Starting context compression")
	end

	-- Check if compression is enabled
	if not config.get("enabled") then
		return false, "Context compression is disabled"
	end

	-- Validate chat object
	if not chat or not chat.messages then
		return false, "Invalid chat object"
	end

	-- Extract messages
	local messages = extract_messages_from_chat(chat)

	if #messages == 0 then
		return false, "No messages to compress"
	end

	-- Check if compression is needed
	local should_compress, urgency, trigger_reasons = trigger_detector.should_compress(chat)

	if not should_compress and not options.force then
		return false,
			"Compression not needed",
			{
				original_count = #messages,
				compressed_count = #messages,
				compression_ratio = 0,
				urgency = urgency,
				trigger_reasons = trigger_reasons,
			}
	end

	-- Select compression strategy
	local strategy, strategy_error = strategy_selector.select_strategy(messages, urgency, options.constraints)

	if not strategy then
		return false, "No suitable compression strategy found: " .. (strategy_error or "unknown error")
	end

	if debug then
		print("[Compression Manager] Selected strategy:", strategy.name)
	end

	-- Perform compression
	local compressed_messages, compression_stats
	local success, result1, result2 = pcall(strategy.compress, messages)

	if debug then
		print("[Compression Manager] Compression result:", success, type(result1))
		if success and type(result1) == "table" then
			print("[Compression Manager] Result1 length:", #result1, "Result2 type:", type(result2))
		end
	end

	if not success then
		-- Try fallback strategy
		local fallback_strategy_name = config.get("fallback_strategy")
		local fallback_strategy = strategy_selector.get_strategy(fallback_strategy_name)

		if fallback_strategy and fallback_strategy ~= strategy then
			if debug then
				print("[Compression Manager] Primary strategy failed, trying fallback:", fallback_strategy.name)
			end

			success, result1, result2 = pcall(fallback_strategy.compress, messages)

			if success then
				compressed_messages, compression_stats = result1, result2 or {}
				compression_stats.fallback_used = true
				compression_stats.fallback_strategy = fallback_strategy.name
			end
		end

		if not success then
			return false, "Compression failed: " .. tostring(result1)
		end
	else
		compressed_messages, compression_stats = result1, result2 or {}
	end

	-- Validate compression results
	if not compressed_messages or #compressed_messages == 0 then
		return false, "Compression produced no valid messages"
	end

	-- Perform quality assessment
	local quality_config = config.get("quality_assessment")
	if quality_config and quality_config.enabled then
		local quality_assessment = quality_assessor.assess_quality(messages, compressed_messages, compression_stats)

		if debug then
			print("[Compression Manager] Quality assessment:", vim.inspect(quality_assessment))
		end

		-- Check if quality meets minimum requirements
		if not quality_assessment.passed then
			if debug then
				print("[Compression Manager] Quality assessment failed, trying fallback")
			end

			-- Try fallback strategy if quality is too low
			local fallback_strategy_name = config.get("fallback_strategy")
			local fallback_strategy = strategy_selector.get_strategy(fallback_strategy_name)

			if fallback_strategy and fallback_strategy ~= strategy then
				local fallback_success, fallback_result1, fallback_result2 = pcall(fallback_strategy.compress, messages)

				if fallback_success then
					local fallback_compressed, fallback_stats = fallback_result1, fallback_result2 or {}
					local fallback_quality =
						quality_assessor.assess_quality(messages, fallback_compressed, fallback_stats)

					if fallback_quality.passed then
						compressed_messages = fallback_compressed
						compression_stats = fallback_stats
						compression_stats.fallback_used = true
						compression_stats.fallback_reason = "quality_assessment_failed"
						compression_stats.quality_assessment = fallback_quality
					end
				end
			end
		else
			compression_stats.quality_assessment = quality_assessment
		end
	end

	-- Apply compressed messages to chat
	apply_compressed_messages_to_chat(chat, compressed_messages, compression_stats)

	-- Update compression stats
	compression_stats.timestamp = os.time()
	compression_stats.urgency = urgency
	compression_stats.trigger_reasons = trigger_reasons

	if debug then
		print("[Compression Manager] Compression completed successfully")
	end

	return true, nil, compression_stats
end

--- Get compression statistics for a chat
---@param chat table Chat object
---@return table stats
function M.get_compression_stats(chat)
	return trigger_detector.get_compression_stats(chat)
end

--- Check if compression is recommended
---@param chat table Chat object
---@return boolean recommended
---@return string urgency
---@return table reasons
function M.is_compression_recommended(chat)
	return trigger_detector.should_compress(chat)
end

--- Get strategy recommendations
---@param chat table Chat object
---@return table recommendations
function M.get_strategy_recommendations(chat)
	local messages = extract_messages_from_chat(chat)
	local _, urgency, _ = trigger_detector.should_compress(chat)

	return strategy_selector.get_strategy_recommendations(messages, urgency)
end

--- Monitor chat for automatic compression
---@param chat table Chat object
function M.monitor_chat(chat)
	if not config.get("auto_trigger") then
		return
	end

	trigger_detector.monitor_chat(chat, function(monitored_chat, urgency, reasons)
		local debug = config.is_debug()

		if debug then
			print("[Compression Manager] Auto-compression triggered, urgency:", urgency)
		end

		-- Only auto-compress on high urgency to avoid interrupting user
		if urgency == "red" then
			local success, error_msg, stats = M.compress_context(monitored_chat, { auto_triggered = true })

			if success then
				if debug then
					print("[Compression Manager] Auto-compression successful:", vim.inspect(stats))
				end
			else
				if debug then
					print("[Compression Manager] Auto-compression failed:", error_msg)
				end
			end
		end
	end)
end

return M
