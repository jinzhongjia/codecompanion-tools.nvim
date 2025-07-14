local M = {}

---@alias ModelName string

---@class ModelToggleOpts
---@field keymap string? Keymap to toggle models (default: "<S-Tab>")
---@field models? table<string, ModelName|ModelName[]> Model(s) per adapter
---@field sequence? table<integer, {adapter: string, model: string}> Predefined adapter+model sequence

---@type table<integer, table<string, integer>>
local model_indices = {}

---@type table<integer, {adapter: string, model: string}>
local original_adapters = {}

---@type table<integer, integer>
local sequence_indices = {}

---@return CodeCompanion.Chat|nil
local function get_chat_for_buffer(bufnr)
	local chat_strategy = require("codecompanion.strategies.chat")
	return chat_strategy.buf_get_chat and chat_strategy.buf_get_chat(bufnr) or nil
end

local function load_config()
	local cfg = require("codecompanion.config")
	return (
		cfg.extensions
		and cfg.extensions["codecompanion-tools"]
		and cfg.extensions["codecompanion-tools"].opts
		and cfg.extensions["codecompanion-tools"].opts.model_toggle
	) or {}
end

-- Toggle using sequence mode
---@param bufnr integer
---@param chat table
---@param cfg ModelToggleOpts
local function toggle_sequence_mode(bufnr, chat, cfg)
	local sequence = cfg.sequence
	local current_adapter = chat.adapter.name
	local current_model = (type(chat.adapter.model) == "table" and chat.adapter.model.name) or chat.settings.model
	local original = original_adapters[bufnr]

	-- Filter sequence for current adapter
	local adapter_sequence = {}
	for _, item in ipairs(sequence) do
		if item.adapter == current_adapter then
			table.insert(adapter_sequence, item.model)
		end
	end

	if #adapter_sequence == 0 then
		vim.notify(
			string.format("No models configured for current adapter '%s' in sequence", current_adapter),
			vim.log.levels.WARN
		)
		return
	end

	-- Initialize sequence index for this buffer
	if not sequence_indices[bufnr] then
		sequence_indices[bufnr] = 0 -- 0 means original
	end

	-- Find current position in adapter sequence
	local current_index = nil
	for i, model in ipairs(adapter_sequence) do
		if current_model == model then
			current_index = i
			break
		end
	end

	local target_model

	if current_index then
		-- Current position is in sequence, move to next
		if current_index < #adapter_sequence then
			sequence_indices[bufnr] = current_index + 1
			target_model = adapter_sequence[sequence_indices[bufnr]]
		else
			-- At end of sequence, go back to original
			sequence_indices[bufnr] = 0
			target_model = original.model
		end
	elseif current_model == original.model then
		-- Currently at original, move to first in sequence
		sequence_indices[bufnr] = 1
		target_model = adapter_sequence[1]
	else
		-- Current position is not in sequence and not original, go to first in sequence
		sequence_indices[bufnr] = 1
		target_model = adapter_sequence[1]
	end

	-- Apply the target model
	chat:apply_model(target_model)
	chat:apply_settings()

	vim.notify(string.format("Switched to %s:%s", current_adapter, target_model), vim.log.levels.INFO)
end

-- Toggle using models mode
---@param bufnr integer
---@param chat table
---@param cfg ModelToggleOpts
local function toggle_models_mode(bufnr, chat, cfg)
	local adapter_name = chat.adapter.name
	local configured_models = cfg.models and cfg.models[adapter_name]

	-- Support single model or multiple models
	local model_list = {}
	if type(configured_models) == "string" then
		model_list = { configured_models }
	elseif type(configured_models) == "table" then
		model_list = configured_models
	else
		vim.notify(string.format("No models configured for adapter '%s'", adapter_name), vim.log.levels.WARN)
		return
	end

	if #model_list == 0 then
		vim.notify(string.format("Empty model list for adapter '%s'", adapter_name), vim.log.levels.WARN)
		return
	end

	-- Initialize model index tracking for this buffer and adapter
	if not model_indices[bufnr] then
		model_indices[bufnr] = {}
	end
	if not model_indices[bufnr][adapter_name] then
		model_indices[bufnr][adapter_name] = 1
	end

	local current = (type(chat.adapter.model) == "table" and chat.adapter.model.name) or chat.settings.model
	local original = original_adapters[bufnr].model

	-- Determine target model based on current state
	local target
	if current == original then
		-- Switch to first configured model
		target = model_list[1]
		model_indices[bufnr][adapter_name] = 1
	else
		-- Check if current model is in our configured list
		local current_index = nil
		for i, model in ipairs(model_list) do
			if current == model then
				current_index = i
				break
			end
		end

		if current_index then
			-- Cycle to next model, or back to original if at end
			if current_index < #model_list then
				model_indices[bufnr][adapter_name] = current_index + 1
				target = model_list[model_indices[bufnr][adapter_name]]
			else
				-- Back to original model
				target = original
				model_indices[bufnr][adapter_name] = 1
			end
		else
			-- Current model not in list, switch to first configured model
			target = model_list[1]
			model_indices[bufnr][adapter_name] = 1
		end
	end

	chat:apply_model(target)
	chat:apply_settings()

	vim.notify(string.format("Switched model to %s", target), vim.log.levels.INFO)
end

-- Toggle between models in chat buffer
---@param bufnr integer
local function toggle_model(bufnr)
	local chat = get_chat_for_buffer(bufnr)
	if not chat or not chat.adapter then
		vim.notify("No CodeCompanion chat in this buffer", vim.log.levels.WARN)
		return
	end

	local cfg = load_config()

	-- Store original adapter and model the first time
	if original_adapters[bufnr] == nil then
		local current_model = (type(chat.adapter.model) == "table" and chat.adapter.model.name) or chat.settings.model
		original_adapters[bufnr] = {
			adapter = chat.adapter.name,
			model = current_model,
		}
	end

	-- Check if sequence mode is configured
	if cfg.sequence and type(cfg.sequence) == "table" and #cfg.sequence > 0 then
		toggle_sequence_mode(bufnr, chat, cfg)
	else
		toggle_models_mode(bufnr, chat, cfg)
	end
end

-- Setup keymaps
---@param opts ModelToggleOpts
local function setup_keymaps(opts)
	local key = opts.keymap or "<S-Tab>"
	local cfg = require("codecompanion.config")

	if cfg.strategies and cfg.strategies.chat and type(cfg.strategies.chat.keymaps) == "table" then
		cfg.strategies.chat.keymaps.toggle_model = {
			modes = { n = key },
			description = "Toggle chat model",
			callback = function()
				toggle_model(vim.api.nvim_get_current_buf())
			end,
		}
	end

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "codecompanion",
		callback = function(args)
			vim.keymap.set("n", key, function()
				toggle_model(args.buf)
			end, {
				buffer = args.buf,
				desc = "Toggle chat model",
				silent = true,
			})
		end,
	})
end

-- Cleanup caches on buffer deletion
local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("CodeCompanionModelToggle", { clear = true })
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			model_indices[args.buf] = nil
			original_adapters[args.buf] = nil
			sequence_indices[args.buf] = nil
		end,
	})
end

-- Setup function
---@param opts ModelToggleOpts
function M.setup(opts)
	opts = opts or {}
	setup_keymaps(opts)
	setup_autocmds()
end

-- Export functions
M.exports = {
	toggle_model = toggle_model,
}

return M
