-- codecompanion_tools/context_compression/strategies/priority_truncation.lua
-- 优先级截断策略 - 基于重要性评分智能选择保留内容

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- 时间衰减因子计算
---@param time_distance number 时间距离（消息索引差）
---@param lambda number 衰减系数
---@return number time_score 时间得分
local function calculate_time_decay(time_distance, lambda)
	lambda = lambda or 0.1
	return math.exp(-lambda * time_distance)
end

--- 语义相关性评分（基础实现）
---@param content string 内容
---@param current_topic string 当前主题
---@return number semantic_score 语义得分
local function calculate_semantic_relevance(content, current_topic)
	if not current_topic or not content then
		return 0.5
	end

	-- 基础关键词匹配
	local content_lower = content:lower()
	local topic_lower = current_topic:lower()

	-- 简单的关键词重叠度计算
	local topic_words = {}
	for word in topic_lower:gmatch("%w+") do
		if #word > 3 then -- 忽略短词
			topic_words[word] = true
		end
	end

	local matches = 0
	local total_words = 0
	for word in content_lower:gmatch("%w+") do
		if #word > 3 then
			total_words = total_words + 1
			if topic_words[word] then
				matches = matches + 1
			end
		end
	end

	if total_words == 0 then
		return 0.5
	end

	return matches / total_words
end

--- 用户交互强度评分
---@param message table 消息对象
---@param context table 上下文信息
---@return number interaction_score 交互得分
local function calculate_interaction_intensity(message, context)
	local score = 0.5

	-- 用户消息得分更高
	if message.role == "user" then
		score = score + 0.3
	end

	-- 包含问题的消息得分更高
	if message.content:match("%?") then
		score = score + 0.2
	end

	-- 包含请求的消息得分更高
	if
		message.content:match("please")
		or message.content:match("help")
		or message.content:match("can you")
		or message.content:match("how to")
	then
		score = score + 0.2
	end

	-- 包含否定或纠正的消息得分更高
	if
		message.content:match("no")
		or message.content:match("wrong")
		or message.content:match("error")
		or message.content:match("fix")
	then
		score = score + 0.3
	end

	return math.min(score, 1.0)
end

--- 内容类型权重评分
---@param message table 消息对象
---@return number type_score 类型得分
local function calculate_content_type_weight(message)
	local content = message.content
	local score = 0.5

	-- 系统消息权重最高
	if message.role == "system" then
		return 1.0
	end

	-- 代码块权重较高
	if content:match("```") then
		score = score + 0.3
	end

	-- 错误信息权重高
	if content:match("error") or content:match("Error") or content:match("exception") or content:match("Exception") then
		score = score + 0.4
	end

	-- 链接和引用权重较高
	if content:match("http") or content:match("www") or content:match("%[.*%]%(.*%)") then
		score = score + 0.2
	end

	-- 列表和结构化内容权重较高
	if content:match("%-%s") or content:match("%d+%.%s") or content:match("^%s*%*%s") then
		score = score + 0.2
	end

	return math.min(score, 1.0)
end

--- 引用频率评分
---@param message table 消息对象
---@param all_messages table 所有消息
---@param message_index number 消息索引
---@return number reference_score 引用得分
local function calculate_reference_frequency(message, all_messages, message_index)
	local score = 0.0
	local content = message.content

	-- 检查后续消息是否引用了当前消息的内容
	for i = message_index + 1, #all_messages do
		local later_message = all_messages[i]

		-- 简单的内容引用检测
		local common_words = 0
		local total_words = 0

		for word in content:gmatch("%w+") do
			if #word > 4 then -- 只检查较长的词
				total_words = total_words + 1
				if later_message.content:lower():match(word:lower()) then
					common_words = common_words + 1
				end
			end
		end

		if total_words > 0 then
			local reference_strength = common_words / total_words
			if reference_strength > 0.3 then
				score = score + reference_strength * 0.2
			end
		end
	end

	return math.min(score, 1.0)
end

--- 提取当前对话主题
---@param messages table 消息数组
---@return string current_topic 当前主题
local function extract_current_topic(messages)
	local recent_messages = {}
	local start_idx = math.max(1, #messages - 3)

	for i = start_idx, #messages do
		if messages[i].role == "user" then
			table.insert(recent_messages, messages[i].content)
		end
	end

	-- 简单的主题提取 - 取最近用户消息的关键词
	local topic_words = {}
	for _, content in ipairs(recent_messages) do
		for word in content:gmatch("%w+") do
			if #word > 4 then
				topic_words[word] = (topic_words[word] or 0) + 1
			end
		end
	end

	-- 找到最频繁的词作为主题
	local max_count = 0
	local topic = ""
	for word, count in pairs(topic_words) do
		if count > max_count then
			max_count = count
			topic = word
		end
	end

	return topic
end

--- 计算消息重要性得分
---@param message table 消息对象
---@param message_index number 消息索引
---@param all_messages table 所有消息
---@param current_topic string 当前主题
---@param weights table 权重配置
---@return number importance_score 重要性得分
local function calculate_importance_score(message, message_index, all_messages, current_topic, weights)
	local time_distance = #all_messages - message_index

	-- 计算各个维度的得分
	local time_score = calculate_time_decay(time_distance, weights.time_decay_lambda)
	local semantic_score = calculate_semantic_relevance(message.content, current_topic)
	local interaction_score = calculate_interaction_intensity(message, {})
	local type_score = calculate_content_type_weight(message)
	local reference_score = calculate_reference_frequency(message, all_messages, message_index)

	-- 综合得分
	local total_score = weights.time_weight * time_score
		+ weights.semantic_weight * semantic_score
		+ weights.interaction_weight * interaction_score
		+ weights.type_weight * type_score
		+ weights.reference_weight * reference_score

	return total_score
end

--- 智能截断保持语义完整性
---@param scored_messages table 已评分的消息
---@param target_count number 目标保留数量
---@return table selected_messages 选择的消息
local function intelligent_truncation(scored_messages, target_count)
	-- 按得分排序
	table.sort(scored_messages, function(a, b)
		return a.score > b.score
	end)

	local selected = {}
	local selected_indices = {}

	-- 首先保留系统消息
	for _, scored_msg in ipairs(scored_messages) do
		if scored_msg.message.role == "system" then
			table.insert(selected, scored_msg)
			selected_indices[scored_msg.index] = true
		end
	end

	-- 然后按得分选择其他消息
	for _, scored_msg in ipairs(scored_messages) do
		if #selected >= target_count then
			break
		end

		if not selected_indices[scored_msg.index] then
			table.insert(selected, scored_msg)
			selected_indices[scored_msg.index] = true
		end
	end

	-- 按原始顺序排序
	table.sort(selected, function(a, b)
		return a.index < b.index
	end)

	local result = {}
	for _, scored_msg in ipairs(selected) do
		table.insert(result, scored_msg.message)
	end

	return result
end

--- 优先级截断策略实现
---@param messages table 消息数组
---@param options table? 压缩选项
---@return table compressed_messages 压缩后的消息
---@return table compression_stats 压缩统计信息
function M.compress(messages, options)
	local strategy_config = config.get_config().context_compression.priority_truncation
	local stats = {
		original_count = #messages,
		compressed_count = 0,
		compression_ratio = 0,
		strategy = "priority_truncation",
		success = false,
		error = nil,
		processing_time = 0,
		importance_distribution = {},
	}

	local start_time = vim.loop.hrtime()

	-- 获取权重配置
	local weights = strategy_config.importance_weights
	if not weights then
		stats.error = "Missing importance_weights configuration"
		return messages, stats
	end

	-- 计算目标保留数量
	local target_count = strategy_config.target_message_count
		or math.floor(#messages * (strategy_config.retention_ratio or 0.5))

	if target_count >= #messages then
		stats.error = "Target count greater than or equal to original count"
		return messages, stats
	end

	-- 提取当前主题
	local current_topic = extract_current_topic(messages)

	-- 计算每个消息的重要性得分
	local scored_messages = {}
	for i, message in ipairs(messages) do
		local score = calculate_importance_score(message, i, messages, current_topic, weights)
		table.insert(scored_messages, {
			message = message,
			index = i,
			score = score,
		})

		-- 统计得分分布
		local score_range = math.floor(score * 10) / 10
		stats.importance_distribution[score_range] = (stats.importance_distribution[score_range] or 0) + 1
	end

	-- 智能截断
	local compressed_messages = intelligent_truncation(scored_messages, target_count)

	-- 添加压缩信息标记
	if strategy_config.add_compression_marker then
		local removed_count = #messages - #compressed_messages
		local marker_message = {
			role = "system",
			content = string.format(
				"=== 上下文压缩 ===\n"
					.. "策略: 优先级截断\n"
					.. "原始消息数: %d\n"
					.. "保留消息数: %d\n"
					.. "压缩比: %.1f%%\n"
					.. "当前主题: %s\n"
					.. "=== 压缩结束 ===",
				#messages,
				#compressed_messages,
				removed_count / #messages * 100,
				current_topic ~= "" and current_topic or "未识别"
			),
			metadata = {
				type = "compression_marker",
				strategy = "priority_truncation",
				original_count = #messages,
				compressed_count = #compressed_messages,
				timestamp = os.time(),
			},
		}

		table.insert(compressed_messages, 1, marker_message)
	end

	-- 计算统计信息
	stats.compressed_count = #compressed_messages
	stats.compression_ratio = (stats.original_count - stats.compressed_count) / stats.original_count
	stats.success = true
	stats.processing_time = (vim.loop.hrtime() - start_time) / 1e6
	stats.current_topic = current_topic

	return compressed_messages, stats
end

--- 获取策略信息
---@return table info 策略信息
function M.get_info()
	return {
		name = "priority_truncation",
		description = "基于多维度重要性评分的智能截断策略",
		type = "analytical",
		quality = 0.75,
		cost = 0.4,
		speed = "fast",
		requirements = {
			importance_weights = "required",
		},
		features = {
			"importance_scoring",
			"semantic_analysis",
			"time_decay",
			"interaction_analysis",
			"content_type_detection",
			"reference_tracking",
		},
	}
end

--- 验证策略是否可以处理当前上下文
---@param messages table 消息数组
---@return boolean can_handle
---@return string? error_message
function M.validate(messages)
	local strategy_config = config.get_config().context_compression.priority_truncation

	if not strategy_config then
		return false, "Missing priority_truncation configuration"
	end

	if not strategy_config.importance_weights then
		return false, "Missing importance_weights configuration"
	end

	if #messages < 2 then
		return false, "Too few messages for priority truncation"
	end

	return true
end

-- 设置策略属性
M.name = "priority_truncation"
M.quality = 0.75
M.cost = 0.4

--- 估算压缩效果
---@param messages table 消息数组
---@return table estimation 估算结果
function M.estimate_compression(messages)
	local config_data = config.get_config().context_compression.priority_truncation
	local retention_ratio = config_data.retention_ratio or 0.5
	local target_count = config_data.target_message_count or math.floor(#messages * retention_ratio)

	local estimated_count = math.max(target_count, 3) -- 最少保留3条消息
	local compression_ratio = (#messages - estimated_count) / #messages

	return {
		original_count = #messages,
		estimated_count = estimated_count,
		compression_ratio = compression_ratio,
		processing_time_estimate = 500, -- 0.5秒估算
		quality_estimate = 0.85,
		recommended = compression_ratio > 0.2 and compression_ratio < 0.8,
	}
end

return M
