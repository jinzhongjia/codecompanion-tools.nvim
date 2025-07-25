local utils = require("codecompanion_tools.utils")
local chat_utils = require("codecompanion_tools.chat")
local config_utils = require("codecompanion_tools.config")

local M = {}

---@class CodeCompanionRulesConfig
---@field rules_filenames string[]
---@field debug boolean
---@field enabled boolean
---@field extract_file_paths_from_chat_message? fun(message:table):string[]|nil

local DEFAULT_CONFIG = {
	rules_filenames = {
		".rules",
		".goosehints",
		".cursorrules",
		".windsurfrules",
		".clinerules",
		".github/copilot-instructions.md",
		"AGENT.md",
		"AGENTS.md",
		"CLAUDE.md",
		".codecompanionrules",
	},
	debug = false,
	enabled = true,
	extract_file_paths_from_chat_message = nil,
}

M.config = DEFAULT_CONFIG

-- Per-buffer caches
local enabled = {}
local fingerprint = {}

-- Extract file paths from chat
local function collect_paths(bufnr)
	if not M.config.enabled then
		return {}
	end

	-- Check codecompanion buffer
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		utils.log("collect_paths → not a codecompanion buffer, skipping", M.config.debug)
		return {}
	end

	local ok, chat_strategy = pcall(require, "codecompanion.strategies.chat")
	if not ok or not chat_strategy.buf_get_chat then
		return {}
	end

	local chat_ok, chat = pcall(chat_strategy.buf_get_chat, bufnr)
	if not chat_ok or not chat then
		utils.log("collect_paths → failed to get chat object", M.config.debug)
		return {}
	end

	local proj = utils.normalize_path(vim.fn.getcwd())
	local out, seen = {}, {}

	local function is_rule_file(p)
		local name = vim.fn.fnamemodify(p, ":t")
		return vim.tbl_contains(M.config.rules_filenames, name)
	end

	local function add(p)
		p = utils.normalize_path(utils.clean_path(p))
		if is_rule_file(p) then
			return
		end
		if p ~= "" and not seen[p] and p:match("^" .. vim.pesc(proj)) then
			table.insert(out, p)
			seen[p] = true
		end
	end

	-- Extract from refs
	for _, r in ipairs(chat.refs or {}) do
		if chat_utils.is_file_ref(r) then
			add(r.path ~= "" and r.path or chat_utils.id_to_path(r.id))
		end
	end

	-- Extract from messages
	for _, msg in ipairs(chat.messages) do
		if msg.opts and msg.opts.reference then
			local p = msg.opts.reference:match("^<file>([^<]+)</file>$")
				or msg.opts.reference:match("^<buf>([^<]+)</buf>$")
			if p then
				add(p)
			end
		end

		if msg.content then
			-- Check if custom extraction function is provided
			local cb = M.config.extract_file_paths_from_chat_message
			if type(cb) == "function" then
				local ok_cb, extra = pcall(cb, msg)
				if ok_cb and type(extra) == "table" then
					for _, p in ipairs(extra) do
						add(p)
					end
				end
			else
				-- Use default patterns if no custom function is provided
				for p in msg.content:gmatch("%*%*Insert Edit Into File Tool%*%*: `([^`]+)`") do
					add(p)
				end
				for p in msg.content:gmatch("%*%*Create File Tool%*%*: `([^`]+)`") do
					add(p)
				end
				for p in msg.content:gmatch("%*%*Read File Tool%*%*: Lines %d+ to %-?%d+ of ([^:]+):") do
					add(p)
				end
			end
		end
	end

	utils.log(("collect_paths → %d path(s)"):format(#out), M.config.debug)
	return out
end

-- Ascend directories to find rule files
local function collect_rules(paths)
	if not M.config.enabled then
		return {}
	end
	local proj = utils.normalize_path(vim.fn.getcwd())
	local out, seen = {}, {}

	local function ascend(dir)
		dir = utils.normalize_path(dir)
		-- Cross-platform root check
		local is_root = (dir == "/" or dir:match("^%a:[/\\]?$")) -- Unix root or Windows drive root
		while not is_root and dir:match("^" .. vim.pesc(proj)) do
			local f = utils.find_first_file(dir, M.config.rules_filenames)
			if f and not seen[f] then
				out[#out + 1] = f
				seen[f] = true
			end
			local parent = vim.fn.fnamemodify(dir, ":h")
			if parent == dir then
				break
			end
			dir = parent
			is_root = (dir == "/" or dir:match("^%a:[/\\]?$"))
		end
	end

	for _, p in ipairs(paths) do
		ascend(vim.fn.fnamemodify(p, ":h"))
	end

	table.sort(out, function(a, b)
		-- Sort by depth (deeper first) - cross-platform
		local sep = "[/\\]"
		return select(2, a:gsub(sep, "")) > select(2, b:gsub(sep, ""))
	end)

	utils.log(("collect_rules → %d rule file(s)"):format(#out), M.config.debug)
	return out
end

-- Sync chat refs with rule files
local function sync_refs(bufnr, rule_files)
	if not M.config.enabled then
		return
	end

	local function ref_opts(opts)
		return vim.tbl_extend("force", opts or {}, {
			rules_managed = true,
			pinned = true,
			watched = false,
		})
	end

	local function rerender_context(chat)
		vim.schedule(function()
			local start = chat.header_line + 1
			local i, last = start, vim.api.nvim_buf_line_count(chat.bufnr)
			while i < last do
				local l = vim.api.nvim_buf_get_lines(chat.bufnr, i, i + 1, false)[1] or ""
				if l == "" or l:match("^> ") then
					i = i + 1
				else
					break
				end
			end
			if i > start then
				chat.ui:unlock_buf()
				vim.api.nvim_buf_set_lines(chat.bufnr, start, i, false, {})
			end
			if chat.references and chat.references.render then
				chat.ui:unlock_buf()
				chat.references:render()
			end
			chat.ui:unlock_buf()
		end)
	end

	local ok, chat_strategy = pcall(require, "codecompanion.strategies.chat")
	if not ok or not chat_strategy.buf_get_chat then
		return
	end

	local chat_ok, chat = pcall(chat_strategy.buf_get_chat, bufnr)
	if not chat_ok or not chat then
		utils.log("sync_refs → failed to get chat object", M.config.debug)
		return
	end

	-- Build desired refs map
	local desired = {}
	for _, abs in ipairs(rule_files) do
		local rel = vim.fn.fnamemodify(abs, ":.")
		local bn = vim.fn.bufnr(rel)
		local id = (bn ~= -1 and vim.api.nvim_buf_is_loaded(bn)) and ("<buf>" .. rel .. "</buf>")
			or ("<file>" .. rel .. "</file>")
		desired[rel] = { id = id, bufnr = (id:match("^<buf>") and bn or nil) }
	end

	-- Index existing refs by path
	local existing = {}
	for i = #chat.refs, 1, -1 do
		local r = chat.refs[i]
		if chat_utils.is_file_ref(r) then
			local path = chat_utils.id_to_path(r.id)
			if existing[path] then
				table.remove(chat.refs, i)
			else
				existing[path] = r
			end
		end
	end

	-- Add missing refs
	local added_cnt = 0
	for path, want in pairs(desired) do
		local r = existing[path]
		if not r then
			local opts = ref_opts({})
			local buffer_cmd_ok, buffer_cmd = pcall(require, "codecompanion.strategies.chat.slash_commands.buffer")
			local file_cmd_ok, file_cmd = pcall(require, "codecompanion.strategies.chat.slash_commands.file")

			if want.bufnr and buffer_cmd_ok then
				buffer_cmd.new({ Chat = chat }):output({ bufnr = want.bufnr, path = path }, opts)
			elseif file_cmd_ok then
				file_cmd.new({ Chat = chat }):output({ path = path }, opts)
			end
			r = chat.refs[#chat.refs] -- last one is the ref we just added
			added_cnt = added_cnt + 1
		end
	end

	-- Remove obsolete refs
	local removed_cnt = 0
	for i = #chat.refs, 1, -1 do
		local r = chat.refs[i]
		if r.opts and r.opts.rules_managed then
			local p = chat_utils.id_to_path(r.id)
			if not desired[p] then
				local ref_id = r.id
				table.remove(chat.refs, i)
				for j = #chat.messages, 1, -1 do
					local m = chat.messages[j]
					if m.opts and m.opts.reference == ref_id then
						table.remove(chat.messages, j)
					end
				end
				removed_cnt = removed_cnt + 1
			end
		end
	end

	-- Notify and re-render if changed
	if added_cnt + removed_cnt > 0 then
		utils.log(string.format("sync_refs → +%d -%d", added_cnt, removed_cnt), M.config.debug)
		-- Build notification message
		local msg_parts = {}
		if added_cnt > 0 then
			table.insert(msg_parts, ("Added %d rule reference(s)"):format(added_cnt))
		end
		if removed_cnt > 0 then
			table.insert(msg_parts, ("Removed %d obsolete reference(s)"):format(removed_cnt))
		end
		if #msg_parts > 0 then
			utils.notify(table.concat(msg_parts, ", "))
		end
		chat_utils.rerender_context(chat)
	else
		utils.log("sync_refs → no change", M.config.debug)
	end
end

-- Main processing function
local function process(bufnr)
	if not M.config.enabled then
		return
	end
	utils.log("process → begin", M.config.debug)
	local paths = collect_paths(bufnr)
	local fp = utils.create_hash(paths)

	if fingerprint[bufnr] == fp then
		utils.log("process → fingerprint unchanged, skipping", M.config.debug)
		return
	end
	fingerprint[bufnr] = fp

	sync_refs(bufnr, collect_rules(paths))
	utils.log("process → done", M.config.debug)
end

-- Event handlers
local function on_mode(bufnr)
	utils.log("on_mode → begin", M.config.debug)
	if not M.config.enabled then
		return
	end

	-- Check buffer type
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	enabled[bufnr] = true
	process(bufnr)
end

local function on_tool(bufnr)
	utils.log("on_tool → begin", M.config.debug)
	if not M.config.enabled then
		return
	end

	-- Check buffer type
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	process(bufnr)
end

local function on_clear(bufnr)
	enabled[bufnr], fingerprint[bufnr] = nil, nil
end

-- Pre-submit processing function
local function on_pre_submit(bufnr)
	utils.log("on_pre_submit → begin", M.config.debug)
	if not M.config.enabled then
		return
	end

	-- Check buffer type
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	-- Process immediately for pre-submit
	process(bufnr)
end

-- Setup prompt decorator to trigger rule updates before message submission
local function setup_prompt_decorator()
	local ok, config = pcall(require, "codecompanion.config")
	if not ok then
		utils.log("setup_prompt_decorator → codecompanion.config not found", M.config.debug)
		return
	end

	-- Store original decorator if it exists
	local original_decorator = nil
	if
		config.strategies
		and config.strategies.chat
		and config.strategies.chat.opts
		and config.strategies.chat.opts.prompt_decorator
	then
		original_decorator = config.strategies.chat.opts.prompt_decorator
	end

	-- Create our decorator function
	local function rule_aware_decorator(message, adapter, context)
		utils.log("rule_aware_decorator → triggered", M.config.debug)

		-- Get current buffer from context
		local bufnr = context.bufnr or vim.api.nvim_get_current_buf()

		-- Update rules before message is sent
		on_pre_submit(bufnr)

		-- Call original decorator if it exists
		if original_decorator then
			return original_decorator(message, adapter, context)
		end

		return message
	end

	-- Initialize config structure if needed
	if not config.strategies then
		config.strategies = {}
	end
	if not config.strategies.chat then
		config.strategies.chat = {}
	end
	if not config.strategies.chat.opts then
		config.strategies.chat.opts = {}
	end

	-- Set our decorator
	config.strategies.chat.opts.prompt_decorator = rule_aware_decorator

	utils.log("setup_prompt_decorator → prompt decorator installed", M.config.debug)
end

-- Patch buffer slash command for event integration
local function patch_buffer_slash_command()
	if _G.__codecompanion_rules_buffer_patch then
		return
	end
	_G.__codecompanion_rules_buffer_patch = true

	local ok, BufferCmd = pcall(require, "codecompanion.strategies.chat.slash_commands.buffer")
	if not ok then
		utils.notify("Could not patch /buffer command", vim.log.levels.WARN, "Rules")
		return
	end

	local util_ok, util = pcall(require, "codecompanion.utils")
	if not util_ok then
		return
	end

	local old_output = BufferCmd.output

	function BufferCmd:output(...)
		old_output(self, ...)
		vim.schedule(function()
			util.fire("ToolFinished", { bufnr = self.Chat.bufnr })
		end)
	end
end

-- Setup function
function M.setup(opts)
	M.config = config_utils.merge_config(DEFAULT_CONFIG, opts)

	patch_buffer_slash_command()

	-- Setup prompt decorator for pre-submit rule updates
	setup_prompt_decorator()

	utils.log(vim.inspect(M.config), M.config.debug)

	local grp = config_utils.create_augroup("CodeCompanionRules")

	vim.api.nvim_create_autocmd("User", {
		group = grp,
		pattern = "CodeCompanionChatCreated",
		callback = function(args)
			-- Use the buffer from the event data, or fall back to current buffer
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			on_mode(bufnr)
		end,
	})

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = grp,
		pattern = "i:n",
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			if chat_utils.is_chat_buffer(bufnr) then
				on_mode(bufnr)
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = grp,
		pattern = { "CodeCompanionToolFinished", "CodeCompanionChatStopped" },
		callback = function(args)
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			on_tool(bufnr)
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = grp,
		pattern = { "CodeCompanionChatCleared", "CodeCompanionChatClosed" },
		callback = function(args)
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			on_clear(bufnr)
		end,
	})

	-- Setup user commands
	config_utils.setup_commands("CodeCompanionRules", {
		Process = {
			callback = function()
				on_mode(vim.api.nvim_get_current_buf())
			end,
			desc = "Re-evaluate rule references now",
		},
		Debug = {
			callback = function()
				M.config.debug = not M.config.debug
				utils.log("CodeCompanion-Rules debug = " .. tostring(M.config.debug), true)
			end,
			desc = "Toggle rules debug",
		},
		Enable = {
			callback = function()
				M.config.enabled = true
				utils.notify("Extension enabled", nil, "CodeCompanionRules")
				on_mode(vim.api.nvim_get_current_buf())
			end,
			desc = "Enable CodeCompanion-Rules extension",
		},
		Disable = {
			callback = function()
				M.config.enabled = false
				for bufnr in pairs(enabled) do
					enabled[bufnr] = nil
				end
				for bufnr in pairs(fingerprint) do
					fingerprint[bufnr] = nil
				end
				utils.notify("Extension disabled", nil, "CodeCompanionRules")
			end,
			desc = "Disable CodeCompanion-Rules extension",
		},
	})
end

return M
