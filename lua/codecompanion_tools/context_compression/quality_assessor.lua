-- codecompanion_tools/context_compression/quality_assessor.lua
-- 质量评估框架 - 评估压缩后的上下文质量

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- 检查内容保留程度
---@param original_messages table 原始消息
---@param compressed_messages table 压缩后的消息
---@return number retention_score 保留程度得分 (0-1)
local function assess_content_retention(original_messages, compressed_messages)
	-- 计算关键词覆盖率
	local original_keywords = {}
	local compressed_keywords = {}

	-- 提取原始消息的关键词
	for _, msg in ipairs(original_messages) do
		if msg.role ~= "system" then
			for word in msg.content:gmatch("%w+") do
				if #word > 4 then -- 只考虑较长的词
					original_keywords[word:lower()] = (original_keywords[word:lower()] or 0) + 1
				end
			end
		end
	end

	-- 提取压缩消息的关键词
	for _, msg in ipairs(compressed_messages) do
		if msg.role ~= "system" or (msg.metadata and msg.metadata.type ~= "compression_marker") then
			for word in msg.content:gmatch("%w+") do
				if #word > 4 then
					compressed_keywords[word:lower()] = (compressed_keywords[word:lower()] or 0) + 1
				end
			end
		end
	end

	-- 计算覆盖率
	local covered_keywords = 0
	local total_keywords = 0

	for keyword, count in pairs(original_keywords) do
		total_keywords = total_keywords + 1
		if compressed_keywords[keyword] then
			covered_keywords = covered_keywords + 1
		end
	end

	if total_keywords == 0 then
		return 1.0
	end

	return covered_keywords / total_keywords
end

--- 检查上下文连贯性
---@param compressed_messages table 压缩后的消息
---@return number coherence_score 连贯性得分 (0-1)
local function assess_context_continuity(compressed_messages)
	if #compressed_messages <= 1 then
		return 1.0
	end

	local coherence_score = 0.0
	local transition_count = 0

	-- 检查相邻消息之间的连贯性
	for i = 2, #compressed_messages do
		local prev_msg = compressed_messages[i - 1]
		local curr_msg = compressed_messages[i]

		-- 跳过系统消息
		if not (prev_msg.role == "system" or curr_msg.role == "system") then
			transition_count = transition_count + 1

			-- 检查对话流畅性
			local prev_content = prev_msg.content:lower()
			local curr_content = curr_msg.content:lower()

			local coherence_indicators = {
				-- 问答连贯性
				(prev_content:match("%?") and curr_msg.role == "assistant") and 0.3 or 0,
				-- 代码相关连贯性
				(prev_content:match("```") and curr_content:match("```")) and 0.2 or 0,
				-- 主题连贯性
				assess_topic_coherence(prev_content, curr_content) * 0.3,
				-- 角色交替正常性
				(prev_msg.role ~= curr_msg.role) and 0.2 or 0,
			}

			local transition_score = 0
			for _, indicator in ipairs(coherence_indicators) do
				transition_score = transition_score + indicator
			end

			coherence_score = coherence_score + math.min(transition_score, 1.0)
		end
	end

	if transition_count == 0 then
		return 1.0
	end

	return coherence_score / transition_count
end

--- 评估主题连贯性
---@param prev_content string 前一条消息内容
---@param curr_content string 当前消息内容
---@return number topic_coherence 主题连贯性得分
local function assess_topic_coherence(prev_content, curr_content)
	-- 提取关键词
	local prev_words = {}
	local curr_words = {}

	for word in prev_content:gmatch("%w+") do
		if #word > 3 then
			prev_words[word] = true
		end
	end

	for word in curr_content:gmatch("%w+") do
		if #word > 3 then
			curr_words[word] = true
		end
	end

	-- 计算词汇重叠度
	local common_words = 0
	local total_words = 0

	for word in pairs(prev_words) do
		total_words = total_words + 1
		if curr_words[word] then
			common_words = common_words + 1
		end
	end

	if total_words == 0 then
		return 0.5
	end

	return common_words / total_words
end

--- 验证关键信息保留
---@param original_messages table 原始消息
---@param compressed_messages table 压缩后的消息
---@return number key_info_score 关键信息得分 (0-1)
local function validate_key_information(original_messages, compressed_messages)
	local key_indicators = {
		errors = { pattern = "error", weight = 0.3 },
		questions = { pattern = "%?", weight = 0.2 },
		code_blocks = { pattern = "```", weight = 0.2 },
		urls = { pattern = "http", weight = 0.1 },
		numbers = { pattern = "%d+", weight = 0.1 },
		commands = { pattern = "^%s*[%w_]+%s*%(", weight = 0.1 },
	}

	local original_indicators = {}
	local compressed_indicators = {}

	-- 统计原始消息中的关键信息
	for _, msg in ipairs(original_messages) do
		if msg.role ~= "system" then
			for name, indicator in pairs(key_indicators) do
				local count = 0
				for _ in msg.content:gmatch(indicator.pattern) do
					count = count + 1
				end
				original_indicators[name] = (original_indicators[name] or 0) + count
			end
		end
	end

	-- 统计压缩消息中的关键信息
	for _, msg in ipairs(compressed_messages) do
		if msg.role ~= "system" or not (msg.metadata and msg.metadata.type == "compression_marker") then
			for name, indicator in pairs(key_indicators) do
				local count = 0
				for _ in msg.content:gmatch(indicator.pattern) do
					count = count + 1
				end
				compressed_indicators[name] = (compressed_indicators[name] or 0) + count
			end
		end
	end

	-- 计算关键信息保留率
	local weighted_retention = 0
	local total_weight = 0

	for name, indicator in pairs(key_indicators) do
		local original_count = original_indicators[name] or 0
		local compressed_count = compressed_indicators[name] or 0

		if original_count > 0 then
			local retention_rate = math.min(compressed_count / original_count, 1.0)
			weighted_retention = weighted_retention + retention_rate * indicator.weight
			total_weight = total_weight + indicator.weight
		end
	end

	if total_weight == 0 then
		return 1.0
	end

	return weighted_retention / total_weight
end

--- 评估压缩效率
---@param original_messages table 原始消息
---@param compressed_messages table 压缩后的消息
---@param processing_time number 处理时间（毫秒）
---@return number efficiency_score 效率得分 (0-1)
local function assess_compression_efficiency(original_messages, compressed_messages, processing_time)
	local compression_ratio = (#original_messages - #compressed_messages) / #original_messages

	-- 时间效率评分
	local time_score = 1.0
	if processing_time > 5000 then -- 超过5秒
		time_score = 0.3
	elseif processing_time > 2000 then -- 超过2秒
		time_score = 0.6
	elseif processing_time > 1000 then -- 超过1秒
		time_score = 0.8
	end

	-- 压缩比效率评分
	local ratio_score = 1.0
	if compression_ratio < 0.1 then -- 压缩比太低
		ratio_score = 0.3
	elseif compression_ratio > 0.9 then -- 压缩比太高
		ratio_score = 0.5
	end

	return (time_score + ratio_score) / 2
end

--- 综合质量评估
---@param original_messages table 原始消息
---@param compressed_messages table 压缩后的消息
---@param compression_stats table 压缩统计信息
---@return table quality_assessment 质量评估结果
function M.assess_quality(original_messages, compressed_messages, compression_stats)
	local quality_config = config.get_config().context_compression.quality_assessment

	-- 各项质量指标评估
	local content_retention = assess_content_retention(original_messages, compressed_messages)
	local context_continuity = assess_context_continuity(compressed_messages)
	local key_information = validate_key_information(original_messages, compressed_messages)
	local efficiency =
		assess_compression_efficiency(original_messages, compressed_messages, compression_stats.processing_time or 0)

	-- 配置权重
	local weights = {
		content_retention = quality_config.content_retention_weight or 0.3,
		context_continuity = quality_config.context_continuity_weight or 0.3,
		key_information = quality_config.key_information_weight or 0.3,
		efficiency = quality_config.efficiency_weight or 0.1,
	}

	-- 计算综合得分
	local overall_score = weights.content_retention * content_retention
		+ weights.context_continuity * context_continuity
		+ weights.key_information * key_information
		+ weights.efficiency * efficiency

	-- 质量等级评定
	local quality_grade = "poor"
	if overall_score >= 0.8 then
		quality_grade = "excellent"
	elseif overall_score >= 0.6 then
		quality_grade = "good"
	elseif overall_score >= 0.4 then
		quality_grade = "fair"
	end

	-- 生成改进建议
	local recommendations = {}
	if content_retention < 0.6 then
		table.insert(recommendations, "考虑增加保留消息数量或改进内容选择算法")
	end
	if context_continuity < 0.6 then
		table.insert(recommendations, "注意保持对话流畅性，避免断章取义")
	end
	if key_information < 0.6 then
		table.insert(recommendations, "加强关键信息（错误、问题、代码）的保护")
	end
	if efficiency < 0.6 then
		table.insert(recommendations, "优化压缩算法性能，减少处理时间")
	end

	return {
		overall_score = overall_score,
		quality_grade = quality_grade,
		dimensions = {
			content_retention = content_retention,
			context_continuity = context_continuity,
			key_information = key_information,
			efficiency = efficiency,
		},
		recommendations = recommendations,
		passed = overall_score >= (quality_config.min_quality_score or 0.5),
		timestamp = os.time(),
	}
end

--- 检查压缩是否值得进行
---@param original_messages table 原始消息
---@param estimated_compressed_count number 估计压缩后数量
---@return boolean worthwhile 是否值得压缩
---@return string reason 原因
function M.is_compression_worthwhile(original_messages, estimated_compressed_count)
	local min_reduction = config.get_config().context_compression.quality_assessment.min_compression_ratio or 0.2

	local reduction_ratio = (#original_messages - estimated_compressed_count) / #original_messages

	if reduction_ratio < min_reduction then
		return false, "压缩收益不足"
	end

	if #original_messages <= 3 then
		return false, "消息数量太少，无需压缩"
	end

	if estimated_compressed_count <= 1 then
		return false, "压缩后消息数量过少"
	end

	return true, "压缩收益充足"
end

--- 生成质量报告
---@param quality_assessment table 质量评估结果
---@return string report 质量报告
function M.generate_quality_report(quality_assessment)
	local report = {
		"=== 压缩质量报告 ===",
		"",
		string.format("综合得分: %.2f (%s)", quality_assessment.overall_score, quality_assessment.quality_grade),
		"",
		"各维度评分:",
		string.format("• 内容保留: %.2f", quality_assessment.dimensions.content_retention),
		string.format("• 上下文连贯性: %.2f", quality_assessment.dimensions.context_continuity),
		string.format("• 关键信息: %.2f", quality_assessment.dimensions.key_information),
		string.format("• 效率: %.2f", quality_assessment.dimensions.efficiency),
		"",
	}

	if #quality_assessment.recommendations > 0 then
		table.insert(report, "改进建议:")
		for _, recommendation in ipairs(quality_assessment.recommendations) do
			table.insert(report, "• " .. recommendation)
		end
		table.insert(report, "")
	end

	table.insert(report, "=== 报告结束 ===")

	return table.concat(report, "\n")
end

return M
