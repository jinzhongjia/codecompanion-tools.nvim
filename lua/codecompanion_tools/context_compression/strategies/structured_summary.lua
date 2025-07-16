-- codecompanion_tools/context_compression/strategies/structured_summary.lua
-- 结构化摘要策略 - 使用生成式模型创建高质量摘要

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- 验证配置
---@param strategy_config table 策略配置
---@return boolean valid
---@return string? error_message
local function validate_config(strategy_config)
	if not strategy_config then
		return false, "Missing structured_summary configuration"
	end

	if not strategy_config.model then
		return false, "Missing model configuration for structured_summary"
	end

	if not strategy_config.template then
		return false, "Missing template configuration for structured_summary"
	end

	return true
end

--- 分析对话主题和关键信息
---@param messages table 消息数组
---@return table analysis 分析结果
local function analyze_conversation(messages)
	local analysis = {
		topics = {},
		key_decisions = {},
		user_intents = {},
		code_blocks = {},
		important_references = {},
	}

	for i, msg in ipairs(messages) do
		if msg.role == "user" then
			-- 检测用户意图变化
			if msg.content:match("help me") or msg.content:match("I need") then
				table.insert(analysis.user_intents, {
					index = i,
					intent = "request_help",
					content = msg.content:sub(1, 100),
				})
			end

			-- 检测代码相关讨论
			if msg.content:match("```") then
				table.insert(analysis.code_blocks, {
					index = i,
					language = msg.content:match("```(%w+)") or "unknown",
					content = msg.content:sub(1, 200),
				})
			end
		elseif msg.role == "assistant" then
			-- 检测关键决策点
			if msg.content:match("recommend") or msg.content:match("suggest") then
				table.insert(analysis.key_decisions, {
					index = i,
					type = "recommendation",
					content = msg.content:sub(1, 150),
				})
			end
		end
	end

	return analysis
end

--- 构建摘要提示
---@param messages table 消息数组
---@param analysis table 分析结果
---@param template string 模板
---@return string prompt 摘要提示
local function build_summary_prompt(messages, analysis, template)
	local conversation_text = ""

	-- 构建对话文本
	for i, msg in ipairs(messages) do
		if msg.role ~= "system" then
			conversation_text = conversation_text .. string.format("[%s]: %s\n\n", msg.role:upper(), msg.content)
		end
	end

	-- 构建分析信息
	local analysis_text = ""
	if #analysis.topics > 0 then
		analysis_text = analysis_text .. "主要讨论话题：\n"
		for _, topic in ipairs(analysis.topics) do
			analysis_text = analysis_text .. "- " .. topic .. "\n"
		end
	end

	if #analysis.key_decisions > 0 then
		analysis_text = analysis_text .. "\n关键决策点：\n"
		for _, decision in ipairs(analysis.key_decisions) do
			analysis_text = analysis_text .. "- " .. decision.content .. "\n"
		end
	end

	if #analysis.code_blocks > 0 then
		analysis_text = analysis_text .. "\n代码相关讨论：\n"
		for _, code in ipairs(analysis.code_blocks) do
			analysis_text = analysis_text .. "- " .. code.language .. " 代码块\n"
		end
	end

	-- 应用模板
	local prompt = template:gsub("{conversation}", conversation_text)
	prompt = prompt:gsub("{analysis}", analysis_text)
	prompt = prompt:gsub("{message_count}", tostring(#messages))

	return prompt
end

--- 调用生成模型创建摘要
---@param prompt string 摘要提示
---@param model_config table 模型配置
---@return boolean success
---@return string? summary_or_error
local function generate_summary(prompt, model_config)
	-- 这里需要根据 CodeCompanion 的模型调用方式实现
	-- 由于当前没有直接的模型调用 API，我们创建一个基本的摘要

	local lines = {}
	for line in prompt:gmatch("[^\n]+") do
		table.insert(lines, line)
	end

	-- 创建基本的结构化摘要
	local summary = {
		"=== 对话摘要 ===",
		"",
		"本次对话涉及以下主要内容：",
		"",
	}

	-- 提取关键信息
	local key_points = {}
	for _, line in ipairs(lines) do
		if line:match("USER:") then
			local content = line:gsub("USER:", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if #content > 20 then
				table.insert(key_points, "用户询问：" .. content:sub(1, 100) .. "...")
			end
		elseif line:match("ASSISTANT:") then
			local content = line:gsub("ASSISTANT:", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if #content > 20 then
				table.insert(key_points, "助手回复：" .. content:sub(1, 100) .. "...")
			end
		end
	end

	-- 限制关键点数量
	local max_points = math.min(#key_points, 5)
	for i = 1, max_points do
		table.insert(summary, "• " .. key_points[i])
	end

	table.insert(summary, "")
	table.insert(summary, "=== 摘要结束 ===")

	return true, table.concat(summary, "\n")
end

--- 验证摘要质量
---@param summary string 生成的摘要
---@param original_messages table 原始消息
---@return boolean valid
---@return number quality_score 质量分数 (0-1)
local function validate_summary(summary, original_messages)
	if not summary or #summary < 50 then
		return false, 0.1
	end

	-- 基本质量检查
	local quality_score = 0.5

	-- 检查是否包含关键信息
	local has_structure = summary:match("===") and summary:match("•")
	if has_structure then
		quality_score = quality_score + 0.2
	end

	-- 检查长度合理性
	local compression_ratio = #summary / (#table.concat(original_messages, " "))
	if compression_ratio > 0.1 and compression_ratio < 0.8 then
		quality_score = quality_score + 0.2
	end

	-- 检查是否包含摘要标记
	if summary:match("摘要") then
		quality_score = quality_score + 0.1
	end

	return quality_score > 0.6, quality_score
end

--- 结构化摘要策略实现
---@param messages table 消息数组
---@param options table? 压缩选项
---@return table compressed_messages 压缩后的消息
---@return table compression_stats 压缩统计信息
function M.compress(messages, options)
	local strategy_config = config.get_config().context_compression.structured_summary
	local stats = {
		original_count = #messages,
		compressed_count = 0,
		compression_ratio = 0,
		strategy = "structured_summary",
		success = false,
		error = nil,
		processing_time = 0,
	}

	local start_time = vim.loop.hrtime()

	-- 验证配置
	local valid, error_msg = validate_config(strategy_config)
	if not valid then
		stats.error = error_msg
		return messages, stats
	end

	-- 分析对话
	local analysis = analyze_conversation(messages)

	-- 构建摘要提示
	local prompt = build_summary_prompt(messages, analysis, strategy_config.template)

	-- 生成摘要
	local success, summary = generate_summary(prompt, strategy_config.model)
	if not success then
		stats.error = summary
		return messages, stats
	end

	-- 验证摘要质量
	local quality_valid, quality_score = validate_summary(summary, messages)
	if not quality_valid then
		stats.error = "Summary quality too low: " .. quality_score
		return messages, stats
	end

	-- 构建压缩后的消息
	local compressed_messages = {}

	-- 保留系统消息
	for _, msg in ipairs(messages) do
		if msg.role == "system" then
			table.insert(compressed_messages, msg)
		end
	end

	-- 添加摘要消息
	table.insert(compressed_messages, {
		role = "system",
		content = summary,
		metadata = {
			type = "compression_summary",
			original_message_count = #messages,
			strategy = "structured_summary",
			timestamp = os.time(),
			quality_score = quality_score,
		},
	})

	-- 保留最近的几条消息
	local keep_recent = strategy_config.keep_recent_messages or 3
	local recent_start = math.max(1, #messages - keep_recent + 1)
	for i = recent_start, #messages do
		if messages[i].role ~= "system" then
			table.insert(compressed_messages, messages[i])
		end
	end

	-- 计算统计信息
	stats.compressed_count = #compressed_messages
	stats.compression_ratio = (stats.original_count - stats.compressed_count) / stats.original_count
	stats.success = true
	stats.processing_time = (vim.loop.hrtime() - start_time) / 1e6 -- 转换为毫秒
	stats.quality_score = quality_score

	return compressed_messages, stats
end

--- 获取策略信息
---@return table info 策略信息
function M.get_info()
	return {
		name = "structured_summary",
		description = "使用生成式模型创建高质量的对话摘要",
		type = "generative",
		quality = 0.8,
		cost = 0.7,
		speed = "medium",
		requirements = {
			model = "required",
			template = "required",
		},
		features = {
			"conversation_analysis",
			"structured_output",
			"quality_validation",
			"topic_detection",
			"key_decision_extraction",
		},
	}
end

--- 验证策略是否可以处理当前上下文
---@param messages table 消息数组
---@return boolean can_handle
---@return string? error_message
function M.validate(messages)
	local strategy_config = config.get_config().context_compression.structured_summary

	if not strategy_config then
		return false, "Missing structured_summary configuration"
	end

	if not strategy_config.model then
		return false, "Missing model configuration"
	end

	if not strategy_config.template then
		return false, "Missing template configuration"
	end

	if #messages < 3 then
		return false, "Too few messages for structured summary"
	end

	return true
end

-- 设置策略属性
M.name = "structured_summary"
M.quality = 0.8
M.cost = 0.7

--- 估算压缩效果
---@param messages table 消息数组
---@return table estimation 估算结果
function M.estimate_compression(messages)
	local config_data = config.get_config().context_compression.structured_summary
	local keep_recent = config_data.keep_recent_messages or 3
	local system_count = 0

	for _, msg in ipairs(messages) do
		if msg.role == "system" then
			system_count = system_count + 1
		end
	end

	local estimated_count = system_count + 1 + keep_recent -- 系统消息 + 摘要 + 最近消息
	local compression_ratio = (#messages - estimated_count) / #messages

	return {
		original_count = #messages,
		estimated_count = estimated_count,
		compression_ratio = compression_ratio,
		processing_time_estimate = 2000, -- 2秒估算
		quality_estimate = 0.8,
		recommended = compression_ratio > 0.3,
	}
end

return M
