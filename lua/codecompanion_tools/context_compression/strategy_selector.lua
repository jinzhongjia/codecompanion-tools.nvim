-- codecompanion_tools/context_compression/strategy_selector.lua
-- Strategy selection logic for context compression

local config = require("codecompanion_tools.context_compression.config")

local M = {}

--- Available strategies registry
M.strategies = {}

--- Register a compression strategy
---@param strategy table Strategy implementation
function M.register_strategy(strategy)
	if not strategy or not strategy.name then
		return false, "Strategy must have a name"
	end

	if not strategy.compress or type(strategy.compress) ~= "function" then
		return false, "Strategy must have a compress function"
	end

	M.strategies[strategy.name] = strategy

	if config.is_debug() then
		print("[Strategy Selector] Registered strategy:", strategy.name)
	end

	return true
end

--- Get registered strategy by name
---@param name string Strategy name
---@return table? strategy
function M.get_strategy(name)
	return M.strategies[name]
end

--- Get all registered strategies
---@return table strategies
function M.get_all_strategies()
	return vim.deepcopy(M.strategies)
end

--- Analyze context characteristics
---@param messages table Array of message objects
---@return table context_analysis
local function analyze_context(messages)
	local analysis = {
		message_count = #messages,
		total_length = 0,
		code_density = 0,
		conversation_type = "general",
		complexity_score = 0,
		has_system_messages = false,
		has_tool_outputs = false,
		recent_activity = true,
	}

	local code_patterns = {
		"```",
		"function",
		"class",
		"import",
		"require",
		"def ",
		"var ",
		"let ",
		"const ",
	}

	local code_blocks = 0
	local technical_terms = 0

	for _, message in ipairs(messages) do
		if message.content then
			local content = message.content
			analysis.total_length = analysis.total_length + string.len(content)

			-- Check for code blocks
			local code_block_count = select(2, content:gsub("```", ""))
			code_blocks = code_blocks + code_block_count

			-- Check for technical patterns
			for _, pattern in ipairs(code_patterns) do
				if content:match(pattern) then
					technical_terms = technical_terms + 1
				end
			end

			-- Check message types
			if message.role == "system" then
				analysis.has_system_messages = true
			elseif message.role == "tool" then
				analysis.has_tool_outputs = true
			end
		end
	end

	-- Calculate code density
	if analysis.total_length > 0 then
		analysis.code_density = (code_blocks + technical_terms) / analysis.message_count
	end

	-- Determine conversation type
	if analysis.code_density > 0.5 then
		analysis.conversation_type = "technical"
	elseif analysis.has_tool_outputs then
		analysis.conversation_type = "tool_heavy"
	elseif analysis.has_system_messages then
		analysis.conversation_type = "structured"
	end

	-- Calculate complexity score
	analysis.complexity_score = math.min(
		1.0,
		(analysis.code_density * 0.4 + (analysis.message_count / 50) * 0.3 + (analysis.total_length / 10000) * 0.3)
	)

	return analysis
end

--- Calculate strategy cost-benefit score
---@param strategy table Strategy implementation
---@param context_analysis table Context analysis results
---@param urgency string Compression urgency level
---@return number score
local function calculate_strategy_score(strategy, context_analysis, urgency)
	local base_score = 0

	-- Factor in strategy quality and cost
	local quality_weight = 0.6
	local cost_weight = 0.4

	base_score = (strategy.quality or 0.5) * quality_weight - (strategy.cost or 0.5) * cost_weight

	-- Adjust based on urgency
	if urgency == "red" then
		-- High urgency: prefer fast, low-cost strategies
		base_score = base_score + (1 - (strategy.cost or 0.5)) * 0.3
	elseif urgency == "yellow" then
		-- Medium urgency: balance quality and cost
		base_score = base_score + (strategy.quality or 0.5) * 0.1
	end

	-- Adjust based on context type
	if context_analysis.conversation_type == "technical" then
		-- Technical conversations may benefit from higher quality compression
		base_score = base_score + (strategy.quality or 0.5) * 0.2
	elseif context_analysis.conversation_type == "tool_heavy" then
		-- Tool-heavy conversations may need specific handling
		if strategy.name == "simple_truncation" then
			base_score = base_score + 0.1 -- Simple truncation handles tool outputs well
		end
	end

	-- Adjust based on complexity
	if context_analysis.complexity_score > 0.7 then
		-- High complexity: prefer quality over speed
		base_score = base_score + (strategy.quality or 0.5) * 0.15
	end

	return base_score
end

--- Select optimal compression strategy
---@param messages table Array of message objects
---@param urgency string Compression urgency level ("green", "yellow", "red")
---@param constraints table? Optional constraints
---@return table? selected_strategy
---@return string? error_message
function M.select_strategy(messages, urgency, constraints)
	local debug = config.is_debug()
	constraints = constraints or {}

	if debug then
		print("[Strategy Selector] Selecting strategy for", #messages, "messages, urgency:", urgency)
	end

	-- Get available strategies
	local available_strategies = {}

	-- Check primary strategy first
	local primary_strategy_name = config.get("primary_strategy")
	local primary_strategy = M.strategies[primary_strategy_name]

	if primary_strategy then
		table.insert(available_strategies, primary_strategy)
	end

	-- Add fallback strategy
	local fallback_strategy_name = config.get("fallback_strategy")
	local fallback_strategy = M.strategies[fallback_strategy_name]

	if fallback_strategy and fallback_strategy ~= primary_strategy then
		table.insert(available_strategies, fallback_strategy)
	end

	-- Add other enabled strategies
	for _, strategy in pairs(M.strategies) do
		if strategy ~= primary_strategy and strategy ~= fallback_strategy then
			local strategy_config = config.get(strategy.name)
			if strategy_config and strategy_config.enabled then
				table.insert(available_strategies, strategy)
			end
		end
	end

	if #available_strategies == 0 then
		return nil, "No strategies available"
	end

	-- Analyze context
	local context_analysis = analyze_context(messages)

	if debug then
		print("[Strategy Selector] Context analysis:", vim.inspect(context_analysis))
	end

	-- Calculate scores for each strategy
	local strategy_scores = {}

	for _, strategy in ipairs(available_strategies) do
		-- Check if strategy can handle this context
		if strategy.validate then
			local can_handle, error_msg = strategy.validate(messages)
			if can_handle then
				local score = calculate_strategy_score(strategy, context_analysis, urgency)
				table.insert(strategy_scores, {
					strategy = strategy,
					score = score,
					name = strategy.name,
				})
			else
				if debug then
					print("[Strategy Selector] Strategy", strategy.name, "cannot handle context:", error_msg)
				end
			end
		else
			-- If no validation function, assume it can handle the context
			local score = calculate_strategy_score(strategy, context_analysis, urgency)
			table.insert(strategy_scores, {
				strategy = strategy,
				score = score,
				name = strategy.name,
			})
		end
	end

	if #strategy_scores == 0 then
		return nil, "No strategies can handle the current context"
	end

	-- Sort by score (highest first)
	table.sort(strategy_scores, function(a, b)
		return a.score > b.score
	end)

	local selected = strategy_scores[1]

	if debug then
		print("[Strategy Selector] Selected strategy:", selected.name, "with score:", selected.score)
		print(
			"[Strategy Selector] All scores:",
			vim.inspect(vim.tbl_map(function(s)
				return { name = s.name, score = s.score }
			end, strategy_scores))
		)
	end

	return selected.strategy
end

--- Get strategy recommendation without selection
---@param messages table Array of message objects
---@param urgency string Compression urgency level
---@return table recommendations
function M.get_strategy_recommendations(messages, urgency)
	local context_analysis = analyze_context(messages)
	local recommendations = {}

	for name, strategy in pairs(M.strategies) do
		local score = calculate_strategy_score(strategy, context_analysis, urgency)
		local can_handle = true
		local error_msg = nil

		if strategy.validate then
			can_handle, error_msg = strategy.validate(messages)
		end

		table.insert(recommendations, {
			name = name,
			strategy = strategy,
			score = score,
			can_handle = can_handle,
			error_message = error_msg,
			cost = strategy.cost or 0.5,
			quality = strategy.quality or 0.5,
		})
	end

	-- Sort by score
	table.sort(recommendations, function(a, b)
		if a.can_handle and not b.can_handle then
			return true
		end
		if not a.can_handle and b.can_handle then
			return false
		end
		return a.score > b.score
	end)

	return {
		context_analysis = context_analysis,
		recommendations = recommendations,
	}
end

--- Initialize strategy selector with default strategies
function M.init()
	-- Register simple truncation strategy
	local simple_truncation = require("codecompanion_tools.context_compression.strategies.simple_truncation")
	M.register_strategy(simple_truncation)

	-- Register other strategies when they become available
	-- This allows for graceful degradation if some strategies are not implemented
	local strategies_to_try = {
		"structured_summary",
		"priority_truncation",
	}

	for _, strategy_name in ipairs(strategies_to_try) do
		local ok, strategy = pcall(require, "codecompanion_tools.context_compression.strategies." .. strategy_name)
		if ok and strategy then
			M.register_strategy(strategy)
		end
	end

	if config.is_debug() then
		print("[Strategy Selector] Initialized with strategies:", vim.inspect(vim.tbl_keys(M.strategies)))
	end
end

return M
