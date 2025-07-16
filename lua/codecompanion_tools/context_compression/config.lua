-- codecompanion_tools/context_compression/config.lua
-- Configuration management for context compression

local M = {}

--- Default configuration
M.defaults = {
	enabled = true,
	auto_trigger = true,
	debug = false,

	-- Trigger thresholds
	token_threshold = 8000,
	memory_threshold = 500, -- MB
	message_count_threshold = 20,

	-- Strategy configuration
	primary_strategy = "simple_truncation", -- Start with MVP
	fallback_strategy = "simple_truncation",

	-- Strategy-specific settings
	simple_truncation = {
		keep_recent_messages = 5,
		keep_system_messages = true,
		preserve_context_markers = true,
	},

	structured_summary = {
		enabled = false, -- Disabled in MVP
		model = "gpt-4o-mini",
		max_tokens = 1000,
		temperature = 0.1,
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

	priority_truncation = {
		enabled = false, -- Disabled in MVP
		importance_weights = {
			time_decay = 0.3,
			semantic_relevance = 0.4,
			user_interaction = 0.2,
			content_type = 0.1,
		},
		min_importance_score = 0.3,
	},

	-- Quality assessment
	quality_assessment = {
		enabled = true,
		min_content_retention = 0.5,
		check_context_continuity = true,
		validate_key_information = true,
	},

	-- User interface
	ui = {
		auto_notify = true,
		show_compression_stats = true,
	},
}

--- Current configuration
M.config = vim.deepcopy(M.defaults)

--- Setup configuration
---@param opts table User configuration options
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

	if M.config.debug then
		print("[Context Compression] Configuration loaded:", vim.inspect(M.config))
	end
end

--- Get configuration value
---@param key string Configuration key (supports dot notation)
---@return any
function M.get(key)
	local keys = vim.split(key, ".", { plain = true })
	local value = M.config

	for _, k in ipairs(keys) do
		if type(value) == "table" and value[k] ~= nil then
			value = value[k]
		else
			return nil
		end
	end

	return value
end

--- Set configuration value
---@param key string Configuration key (supports dot notation)
---@param value any Configuration value
function M.set(key, value)
	local keys = vim.split(key, ".", { plain = true })
	local config = M.config

	for i = 1, #keys - 1 do
		local k = keys[i]
		if type(config[k]) ~= "table" then
			config[k] = {}
		end
		config = config[k]
	end

	config[keys[#keys]] = value

	if M.config.debug then
		print("[Context Compression] Configuration updated:", key, "=", vim.inspect(value))
	end
end

--- Validate configuration
---@return boolean valid
---@return string? error_message
function M.validate()
	local config = M.config

	-- Check required fields
	if type(config.token_threshold) ~= "number" or config.token_threshold <= 0 then
		return false, "token_threshold must be a positive number"
	end

	if type(config.memory_threshold) ~= "number" or config.memory_threshold <= 0 then
		return false, "memory_threshold must be a positive number"
	end

	-- Check strategy settings
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
---@return boolean
function M.is_debug()
	return M.config.debug or false
end

--- Enable debug mode
function M.enable_debug()
	M.config.debug = true
	print("[Context Compression] Debug mode enabled")
end

--- Disable debug mode
function M.disable_debug()
	M.config.debug = false
	print("[Context Compression] Debug mode disabled")
end

--- Get full configuration
---@return table
function M.get_config()
	return vim.deepcopy(M.config)
end

return M
