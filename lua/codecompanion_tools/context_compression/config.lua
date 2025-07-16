-- codecompanion_tools/context_compression/config.lua
-- Configuration Management for Context Compression System
--
-- This module manages all configuration settings for the context compression system.
-- It provides a centralized configuration interface with validation, defaults, and
-- runtime updates.
--
-- The configuration system supports:
-- - Multiple compression strategies (simple truncation, structured summary, priority-based)
-- - Quality assessment parameters
-- - User interface preferences
-- - Debug and development options
-- - Flexible configuration through dot notation (e.g., 'ui.auto_notify')

local M = {}

--- Default configuration settings
-- These are the baseline settings that will be used if no user configuration is provided
-- All values can be overridden through the setup() function
M.defaults = {
	enabled = true, -- Enable/disable the entire compression system
	auto_trigger = true, -- Automatically trigger compression based on thresholds
	debug = false, -- Enable debug output and logging

	-- Trigger thresholds for automatic compression
	-- These values determine when compression should be triggered
	token_threshold = 8000, -- Compress when token count exceeds this
	memory_threshold = 500, -- Compress when memory usage exceeds this (MB)
	message_count_threshold = 20, -- Compress when message count exceeds this

	-- Strategy configuration
	-- Primary strategy is tried first, fallback is used if primary fails
	primary_strategy = "simple_truncation", -- Primary compression strategy
	fallback_strategy = "simple_truncation", -- Fallback strategy if primary fails

	-- Strategy-specific settings
	-- Simple truncation: Just keep the most recent messages
	simple_truncation = {
		keep_recent_messages = 5, -- Number of recent messages to preserve
		keep_system_messages = true, -- Always preserve system messages
		preserve_context_markers = true, -- Keep context markers for continuity
	},

	-- Structured summary: Use AI to create intelligent summaries
	structured_summary = {
		enabled = false, -- Disabled in MVP (requires AI model)
		model = "gpt-4o-mini", -- AI model to use for summarization
		max_tokens = 1000, -- Maximum tokens for summary generation
		temperature = 0.1, -- Low temperature for consistent results
		template = [[
请将以下对话内容进行结构化总结，保持关键信息和上下文连贯性：

{content}

要求：
1. 保留重要的技术细节和决策点
2. 维护对话的逻辑流程
3. 突出用户的核心需求和意图
4. 保持简洁但完整的信息
]],
	},

	-- Priority truncation: Keep messages based on calculated importance scores
	priority_truncation = {
		enabled = false, -- Disabled in MVP (complex algorithm)
		importance_weights = {
			time_decay = 0.3, -- Weight for recency of messages
			semantic_relevance = 0.4, -- Weight for semantic relevance
			user_interaction = 0.2, -- Weight for user interaction intensity
			content_type = 0.1, -- Weight for content type (code, text, etc.)
		},
		min_importance_score = 0.3, -- Minimum score to keep a message
	},

	-- Quality assessment settings
	-- These settings control how compression quality is evaluated
	quality_assessment = {
		enabled = true, -- Enable quality assessment
		min_content_retention = 0.5, -- Minimum content retention ratio
		check_context_continuity = true, -- Check for context flow preservation
		validate_key_information = true, -- Validate key information retention
	},

	-- User interface settings
	-- Control how compression events are communicated to the user
	ui = {
		auto_notify = true, -- Show notifications when compression occurs
		show_compression_stats = true, -- Display compression statistics
	},
}

--- Current active configuration
-- This is the configuration that will be used at runtime
-- Initially set to defaults, can be modified through setup()
M.config = vim.deepcopy(M.defaults)

--- Setup configuration with user-provided options
-- This function merges user options with defaults and validates the result
---@param opts table User configuration options (optional)
function M.setup(opts)
	-- Deep merge user options with defaults
	M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

	-- Show debug information if enabled
	if M.config.debug then
		print("[Context Compression] Configuration loaded:", vim.inspect(M.config))
	end
end

--- Get configuration value using dot notation
-- Supports nested keys like 'ui.auto_notify' or 'simple_truncation.keep_recent_messages'
---@param key string Configuration key (supports dot notation)
---@return any The configuration value, or nil if not found
function M.get(key)
	-- Split the key by dots to handle nested access
	local keys = vim.split(key, ".", { plain = true })
	local value = M.config

	-- Navigate through the nested structure
	for _, k in ipairs(keys) do
		if type(value) == "table" and value[k] ~= nil then
			value = value[k]
		else
			return nil -- Key not found
		end
	end

	return value
end

--- Set configuration value using dot notation
-- Supports nested keys and will create intermediate tables as needed
---@param key string Configuration key (supports dot notation)
---@param value any Configuration value to set
function M.set(key, value)
	-- Split the key and navigate to the target location
	local keys = vim.split(key, ".", { plain = true })
	local config = M.config

	-- Create intermediate tables if they don't exist
	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(config[k]) ~= "table" then
			config[k] = {}
		end
		config = config[k]
	end

	-- Set the final value
	config[keys[#keys]] = value

	-- Log the change if debugging is enabled
	if M.config.debug then
		print("[Context Compression] Configuration updated:", key, "=", vim.inspect(value))
	end
end

--- Validate the current configuration
-- Checks for required fields and validates strategy settings
---@return boolean valid True if configuration is valid
---@return string? error_message Error message if validation fails
function M.validate()
	local config = M.config

	-- Validate required numeric fields
	if type(config.token_threshold) ~= "number" or config.token_threshold <= 0 then
		return false, "token_threshold must be a positive number"
	end

	if type(config.memory_threshold) ~= "number" or config.memory_threshold <= 0 then
		return false, "memory_threshold must be a positive number"
	end

	-- Validate strategy settings
	local primary_strategy = config.primary_strategy
	if not config[primary_strategy] then
		return false, "Primary strategy '" .. primary_strategy .. "' not configured"
	end

	local fallback_strategy = config.fallback_strategy
	if not config[fallback_strategy] then
		return false, "Fallback strategy '" .. fallback_strategy .. "' not configured"
	end

	return true
end

--- Get debug status
-- Returns whether debug mode is currently enabled
---@return boolean True if debug mode is enabled
function M.is_debug()
	return M.config.debug or false
end

--- Enable debug mode
-- Turns on debug logging and verbose output
function M.enable_debug()
	M.config.debug = true
	print("[Context Compression] Debug mode enabled")
end

--- Disable debug mode
-- Turns off debug logging and verbose output
function M.disable_debug()
	M.config.debug = false
	print("[Context Compression] Debug mode disabled")
end

--- Get full configuration
-- Returns a deep copy of the current configuration
---@return table Complete configuration table
function M.get_config()
	-- Return a deep copy to prevent external modification
	return vim.deepcopy(M.config)
end

return M
