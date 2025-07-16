-- codecompanion_tools/context_compression/importance_scorer.lua
-- 内容重要性评分算法 - 实现抽象架构中的多维度评分系统

local M = {}

--- 时间衰减因子计算
---@param time_distance number 时间距离（消息索引差）
---@param lambda number 衰减系数
---@return number time_score 时间得分 (0-1)
function M.calculate_time_decay(time_distance, lambda)
	lambda = lambda or 0.1
	return math.exp(-lambda * time_distance)
end

--- 语义相关性评分
---@param fragment string 内容片段
---@param global_context string 全局上下文
---@param current_topic string? 当前主题
---@return number semantic_score 语义得分 (0-1)
function M.calculate_semantic_relevance(fragment, global_context, current_topic)
	if not fragment or fragment == "" then
		return 0.0
	end

	local relevance_score = 0.0

	-- 1. 关键词匹配分析
	local keywords = {}
	local context_text = (global_context or "") .. " " .. (current_topic or "")

	-- 提取上下文关键词
	for word in context_text:gmatch("%w+") do
		if #word > 3 then
			keywords[word:lower()] = (keywords[word:lower()] or 0) + 1
		end
	end

	-- 计算片段中关键词的覆盖度
	local fragment_words = {}
	local total_words = 0
	local matched_words = 0

	for word in fragment:gmatch("%w+") do
		if #word > 3 then
			total_words = total_words + 1
			local word_lower = word:lower()
			fragment_words[word_lower] = true

			if keywords[word_lower] then
				matched_words = matched_words + 1
			end
		end
	end

	if total_words > 0 then
		relevance_score = relevance_score + (matched_words / total_words) * 0.5
	end

	-- 2. 主题相关性
	if current_topic and current_topic ~= "" then
		local topic_words = {}
		for word in current_topic:gmatch("%w+") do
			if #word > 3 then
				topic_words[word:lower()] = true
			end
		end

		local topic_matches = 0
		for word in pairs(fragment_words) do
			if topic_words[word] then
				topic_matches = topic_matches + 1
			end
		end

		if total_words > 0 then
			relevance_score = relevance_score + (topic_matches / total_words) * 0.3
		end
	end

	-- 3. 上下文连贯性
	local coherence_indicators = {
		-- 问答关系
		(fragment:match("%?") and global_context:match("answer")) and 0.1 or 0,
		-- 代码相关性
		(fragment:match("```") and global_context:match("code")) and 0.1 or 0,
		-- 错误处理
		(fragment:match("error") and global_context:match("fix")) and 0.1 or 0,
	}

	for _, indicator in ipairs(coherence_indicators) do
		relevance_score = relevance_score + indicator
	end

	return math.min(relevance_score, 1.0)
end

--- 用户交互强度评分
---@param message table 消息对象
---@param interaction_context table 交互上下文
---@return number interaction_score 交互得分 (0-1)
function M.calculate_user_interaction_intensity(message, interaction_context)
	local score = 0.0
	local content = message.content or ""

	-- 1. 消息角色权重
	if message.role == "user" then
		score = score + 0.4 -- 用户消息基础分更高
	elseif message.role == "assistant" then
		score = score + 0.2 -- 助手消息
	end

	-- 2. 交互类型分析
	local interaction_patterns = {
		-- 问题类型
		question = { patterns = { "%?", "how", "what", "why", "when", "where", "which" }, weight = 0.2 },
		-- 请求类型
		request = { patterns = { "please", "can you", "help", "need", "want" }, weight = 0.15 },
		-- 反馈类型
		feedback = { patterns = { "thank", "good", "bad", "wrong", "correct", "yes", "no" }, weight = 0.1 },
		-- 纠错类型
		correction = {
			patterns = { "actually", "but", "however", "instead", "not", "error", "mistake" },
			weight = 0.25,
		},
		-- 确认类型
		confirmation = { patterns = { "ok", "okay", "right", "sure", "understand", "got it" }, weight = 0.05 },
	}

	for _, pattern_info in pairs(interaction_patterns) do
		for _, pattern in ipairs(pattern_info.patterns) do
			if content:lower():match(pattern) then
				score = score + pattern_info.weight
				break
			end
		end
	end

	-- 3. 交互强度指标
	local intensity_factors = {
		-- 消息长度（较长的消息通常更重要）
		length = math.min(#content / 500, 1.0) * 0.1,
		-- 大写字母比例（可能表示强调）
		emphasis = math.min(#content:match("[A-Z]") or 0, 10) / 10 * 0.05,
		-- 感叹号数量
		exclamation = math.min(#content:match("!") or 0, 3) / 3 * 0.05,
		-- 代码块存在
		code_block = content:match("```") and 0.1 or 0,
	}

	for _, factor in pairs(intensity_factors) do
		score = score + factor
	end

	-- 4. 历史交互权重
	if interaction_context.reply_count then
		score = score + math.min(interaction_context.reply_count / 10, 0.1)
	end

	if interaction_context.user_feedback_positive then
		score = score + 0.15
	end

	return math.min(score, 1.0)
end

--- 内容类型权重评分
---@param message table 消息对象
---@return number type_score 类型得分 (0-1)
function M.calculate_content_type_weight(message)
	local content = message.content or ""
	local score = 0.3 -- 基础分

	-- 1. 消息角色权重
	if message.role == "system" then
		return 1.0 -- 系统消息最高权重
	elseif message.role == "user" then
		score = score + 0.2 -- 用户消息权重较高
	end

	-- 2. 内容类型分析
	local content_types = {
		-- 代码相关
		code_block = { pattern = "```[^`]*```", weight = 0.25 },
		inline_code = { pattern = "`[^`]+`", weight = 0.1 },

		-- 错误和异常
		error_message = { pattern = "[eE]rror", weight = 0.3 },
		exception = { pattern = "[eE]xception", weight = 0.25 },
		warning = { pattern = "[wW]arning", weight = 0.2 },

		-- 结构化内容
		list_item = { pattern = "^%s*[%-%*%+]", weight = 0.15 },
		numbered_list = { pattern = "^%s*%d+%.", weight = 0.15 },
		heading = { pattern = "^#+%s", weight = 0.2 },

		-- 链接和引用
		url = { pattern = "https?://[%w%.%-%/%?%=%%&]+", weight = 0.15 },
		reference = { pattern = "%[.-%]%(.-%)", weight = 0.1 },

		-- 命令和函数
		command = { pattern = "%$%s*[%w_%-]+", weight = 0.1 },
		function_call = { pattern = "%w+%s*%(", weight = 0.15 },

		-- 重要标记
		todo = { pattern = "TODO", weight = 0.2 },
		note = { pattern = "NOTE", weight = 0.15 },
		important = { pattern = "IMPORTANT", weight = 0.25 },
	}

	for _, type_info in pairs(content_types) do
		if content:match(type_info.pattern) then
			score = score + type_info.weight
		end
	end

	-- 3. 特殊内容处理
	-- 多行代码块额外权重
	local code_blocks = content:match("```[^`]*```")
	if code_blocks then
		local line_count = select(2, code_blocks:gsub("\n", ""))
		score = score + math.min(line_count / 10, 0.2)
	end

	-- 数学公式
	if content:match("%$[^%$]+%$") then
		score = score + 0.1
	end

	-- 表格
	if content:match("|.-|") then
		score = score + 0.15
	end

	return math.min(score, 1.0)
end

--- 引用频率评分
---@param message table 消息对象
---@param all_messages table 所有消息
---@param message_index number 消息索引
---@return number reference_score 引用得分 (0-1)
function M.calculate_reference_frequency(message, all_messages, message_index)
	local content = message.content or ""
	local score = 0.0

	-- 1. 后续消息引用检测
	local reference_count = 0
	local potential_references = 0

	-- 提取当前消息的关键内容
	local key_terms = {}
	local unique_terms = {}

	-- 提取代码块中的标识符
	for code_block in content:gmatch("```[^`]*```") do
		for identifier in code_block:gmatch("%w+") do
			if #identifier > 3 then
				key_terms[identifier:lower()] = true
			end
		end
	end

	-- 提取重要词汇
	for word in content:gmatch("%w+") do
		if #word > 4 then
			key_terms[word:lower()] = true
		end
	end

	-- 提取特殊术语
	for term in content:gmatch("%w+%s*%([^%)]*%)") do
		unique_terms[term] = true
	end

	-- 检查后续消息中的引用
	for i = message_index + 1, #all_messages do
		local later_message = all_messages[i]
		if later_message.content then
			potential_references = potential_references + 1

			-- 检查关键词引用
			local later_content = later_message.content:lower()
			for term in pairs(key_terms) do
				if later_content:match(term) then
					reference_count = reference_count + 1
					break
				end
			end

			-- 检查特殊术语引用
			for term in pairs(unique_terms) do
				if later_message.content:match(term) then
					reference_count = reference_count + 2 -- 特殊术语权重更高
					break
				end
			end
		end
	end

	-- 2. 直接引用检测
	local direct_references = 0
	for i = message_index + 1, #all_messages do
		local later_message = all_messages[i]
		if later_message.content then
			-- 检查引用标记
			if
				later_message.content:match("above")
				or later_message.content:match("previous")
				or later_message.content:match("earlier")
			then
				direct_references = direct_references + 1
			end
		end
	end

	-- 3. 计算引用得分
	if potential_references > 0 then
		score = score + (reference_count / potential_references) * 0.6
	end

	score = score + math.min(direct_references / 5, 0.3)

	-- 4. 特殊内容引用权重
	if content:match("function") or content:match("class") or content:match("method") then
		score = score + 0.1 -- 定义性内容更容易被引用
	end

	return math.min(score, 1.0)
end

--- 综合重要性评分
---@param message table 消息对象
---@param message_index number 消息索引
---@param all_messages table 所有消息
---@param global_context string 全局上下文
---@param current_topic string? 当前主题
---@param weights table 权重配置
---@return number importance_score 重要性得分 (0-1)
---@return table score_breakdown 得分详情
function M.calculate_importance_score(message, message_index, all_messages, global_context, current_topic, weights)
	local time_distance = #all_messages - message_index

	-- 计算各维度得分
	local time_score = M.calculate_time_decay(time_distance, weights.time_decay_lambda or 0.1)
	local semantic_score = M.calculate_semantic_relevance(message.content, global_context, current_topic)
	local interaction_score = M.calculate_user_interaction_intensity(message, {})
	local type_score = M.calculate_content_type_weight(message)
	local reference_score = M.calculate_reference_frequency(message, all_messages, message_index)

	-- 应用权重
	local weighted_scores = {
		time = (weights.time_weight or 0.2) * time_score,
		semantic = (weights.semantic_weight or 0.3) * semantic_score,
		interaction = (weights.interaction_weight or 0.2) * interaction_score,
		type = (weights.type_weight or 0.2) * type_score,
		reference = (weights.reference_weight or 0.1) * reference_score,
	}

	-- 计算总分
	local total_score = 0
	for _, score in pairs(weighted_scores) do
		total_score = total_score + score
	end

	-- 得分详情
	local score_breakdown = {
		total = total_score,
		dimensions = {
			time = time_score,
			semantic = semantic_score,
			interaction = interaction_score,
			type = type_score,
			reference = reference_score,
		},
		weighted = weighted_scores,
	}

	return math.min(total_score, 1.0), score_breakdown
end

--- 批量计算消息重要性得分
---@param messages table 消息数组
---@param global_context string 全局上下文
---@param current_topic string? 当前主题
---@param weights table 权重配置
---@return table scored_messages 已评分的消息
function M.score_messages(messages, global_context, current_topic, weights)
	local scored_messages = {}

	for i, message in ipairs(messages) do
		local score, breakdown =
			M.calculate_importance_score(message, i, messages, global_context, current_topic, weights)

		table.insert(scored_messages, {
			message = message,
			index = i,
			score = score,
			breakdown = breakdown,
		})
	end

	return scored_messages
end

--- 获取重要性得分统计
---@param scored_messages table 已评分的消息
---@return table statistics 统计信息
function M.get_score_statistics(scored_messages)
	if #scored_messages == 0 then
		return {
			count = 0,
			mean = 0,
			median = 0,
			max = 0,
			min = 0,
			std_dev = 0,
			distribution = {},
		}
	end

	local scores = {}
	for _, scored_msg in ipairs(scored_messages) do
		table.insert(scores, scored_msg.score)
	end

	table.sort(scores)

	local sum = 0
	for _, score in ipairs(scores) do
		sum = sum + score
	end

	local mean = sum / #scores
	local median = scores[math.ceil(#scores / 2)]
	local max_score = scores[#scores]
	local min_score = scores[1]

	-- 计算标准差
	local variance = 0
	for _, score in ipairs(scores) do
		variance = variance + (score - mean) ^ 2
	end
	local std_dev = math.sqrt(variance / #scores)

	-- 得分分布
	local distribution = {}
	for i = 0, 10 do
		local range = i / 10
		distribution[range] = 0
	end

	for _, score in ipairs(scores) do
		local bucket = math.floor(score * 10) / 10
		distribution[bucket] = (distribution[bucket] or 0) + 1
	end

	return {
		count = #scored_messages,
		mean = mean,
		median = median,
		max = max_score,
		min = min_score,
		std_dev = std_dev,
		distribution = distribution,
	}
end

return M
