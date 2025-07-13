local M = {}

---@class CodeCompanionRulesConfig
---@field rules_filenames string[]
---@field debug boolean
---@field enabled boolean
---@field extract_file_paths_from_chat_message? fun(message:table):string[]|nil

-- Configuration with defaults
M.config = {
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

-- Per-buffer caches
local enabled = {}
local fingerprint = {}

-- Helper functions
local function log(msg)
	if M.config.debug then
		print("[Rules] " .. msg)
	end
end

local function notify(msg, level)
	vim.schedule(function()
		vim.notify("[CodeCompanionRules] " .. msg, level or vim.log.levels.INFO, { title = "CodeCompanionRules" })
	end)
end

local function normalize(p)
	return vim.fn.fnamemodify(p, ":p"):gsub("/$", "")
end

local function clean(p)
	return p:gsub("^[`\"'%s]+", ""):gsub("[`\"'%s]+$", "")
end

local function hash(list)
	if #list == 0 then
		return ""
	end
	table.sort(list)
	return table.concat(list, "|")
end

local function is_file_ref(ref)
	return (type(ref.id) == "string" and (ref.id:match("^<file>") or ref.id:match("^<buf>")))
		or (type(ref.source) == "string" and (ref.source:match("%.file$") or ref.source:match("%.buffer$")))
end

local function id_to_path(id)
	return id:match("^<file>(.*)</file>$") or id:match("^<buf>(.*)</buf>$") or id
end

-- Find the first existing file from a list of names in a directory
local function find_first_file(dir, names)
	for _, name in ipairs(names) do
		local path = dir .. "/" .. name
		if vim.fn.filereadable(path) == 1 then
			return path
		end
		if r then
			r.opts = ref_opts(r.opts) -- normalize flags
		end
	end
end

-- Extract paths mentioned in chat
local function collect_paths(bufnr)
	if not M.config.enabled then
		return {}
	end

	-- Check if this is a codecompanion buffer
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		log("collect_paths → not a codecompanion buffer, skipping")
		return {}
	end

	local ok, chat_strategy = pcall(require, "codecompanion.strategies.chat")
	if not ok or not chat_strategy.buf_get_chat then
		return {}
	end

	local chat_ok, chat = pcall(chat_strategy.buf_get_chat, bufnr)
	if not chat_ok or not chat then
		log("collect_paths → failed to get chat object")
		return {}
	end

	local proj = normalize(vim.fn.getcwd())
	local out, seen = {}, {}

	local function is_rule_file(p)
		local name = vim.fn.fnamemodify(p, ":t")
		return vim.tbl_contains(M.config.rules_filenames, name)
	end

	local function add(p)
		p = normalize(clean(p))
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
		if is_file_ref(r) then
			add(r.path ~= "" and r.path or id_to_path(r.id))
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

	log(("collect_paths → %d path(s)"):format(#out))
	return out
end

-- Ascend directories to find rule files
local function collect_rules(paths)
	if not M.config.enabled then
		return {}
	end
	local proj = normalize(vim.fn.getcwd())
	local out, seen = {}, {}

	local function ascend(dir)
		dir = normalize(dir)
		while dir ~= "/" and dir:match("^" .. vim.pesc(proj)) do
			local f = find_first_file(dir, M.config.rules_filenames)
			if f and not seen[f] then
				out[#out + 1] = f
				seen[f] = true
			end
			local parent = vim.fn.fnamemodify(dir, ":h")
			if parent == dir then
				break
			end
			dir = parent
		end
	end

	for _, p in ipairs(paths) do
		ascend(vim.fn.fnamemodify(p, ":h"))
	end

	table.sort(out, function(a, b)
		return select(2, a:gsub("/", "")) > select(2, b:gsub("/", ""))
	end)

	log(("collect_rules → %d rule file(s)"):format(#out))
	return out
end

-- Keep chat.refs in sync with rule files
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
		log("sync_refs → failed to get chat object")
		return
	end

	-- Desired refs keyed by project-relative path
	local desired = {}
	for _, abs in ipairs(rule_files) do
		local rel = vim.fn.fnamemodify(abs, ":.")
		local bn = vim.fn.bufnr(rel)
		local id = (bn ~= -1 and vim.api.nvim_buf_is_loaded(bn)) and ("<buf>" .. rel .. "</buf>")
			or ("<file>" .. rel .. "</file>")
		desired[rel] = { id = id, bufnr = (id:match("^<buf>") and bn or nil) }
	end

	-- Existing refs - de-duplicate & index by path
	local existing = {}
	for i = #chat.refs, 1, -1 do
		local r = chat.refs[i]
		if is_file_ref(r) then
			local path = id_to_path(r.id)
			if existing[path] then
				table.remove(chat.refs, i)
			else
				existing[path] = r
			end
		end
	end

	-- Ensure every desired ref exists & is normalized
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

	-- Drop obsolete rule-managed refs
	local removed_cnt = 0
	for i = #chat.refs, 1, -1 do
		local r = chat.refs[i]
		if r.opts and r.opts.rules_managed then
			local p = id_to_path(r.id)
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

	-- Feedback + context re-render
	if added_cnt + removed_cnt > 0 then
		log(string.format("sync_refs → +%d -%d", added_cnt, removed_cnt))
		-- Create notification message parts
		local msg_parts = {}
		if added_cnt > 0 then
			table.insert(msg_parts, ("Added %d rule reference(s)"):format(added_cnt))
		end
		if removed_cnt > 0 then
			table.insert(msg_parts, ("Removed %d obsolete reference(s)"):format(removed_cnt))
		end
		if #msg_parts > 0 then
			notify(table.concat(msg_parts, ", "))
		end
		rerender_context(chat)
	else
		log("sync_refs → no change")
	end
end

-- Main worker
local function process(bufnr)
	if not M.config.enabled then
		return
	end
	log("process → begin")
	local paths = collect_paths(bufnr)
	local fp = hash(paths)

	if fingerprint[bufnr] == fp then
		log("process → fingerprint unchanged, skipping")
		return
	end
	fingerprint[bufnr] = fp

	sync_refs(bufnr, collect_rules(paths))
	log("process → done")
end

-- Event handlers
local function on_mode(bufnr)
	if not M.config.enabled then
		return
	end

	-- Only process codecompanion buffers
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	enabled[bufnr] = true
	process(bufnr)
end

local function on_submit(bufnr)
	if not M.config.enabled then
		return
	end

	-- Only process codecompanion buffers
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	process(bufnr)
end

local function on_tool(bufnr)
	if not M.config.enabled then
		return
	end

	-- Only process codecompanion buffers
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	if filetype ~= "codecompanion" then
		return
	end

	process(bufnr)
end

local function on_clear(bufnr)
	enabled[bufnr], fingerprint[bufnr] = nil, nil
end

-- Patch buffer slash command
local function patch_buffer_slash_command()
	if _G.__codecompanion_rules_buffer_patch then
		return
	end
	_G.__codecompanion_rules_buffer_patch = true

	local ok, BufferCmd = pcall(require, "codecompanion.strategies.chat.slash_commands.buffer")
	if not ok then
		vim.schedule(function()
			vim.notify("[CodeCompanionRules] Could not patch /buffer slash-command", vim.log.levels.WARN)
		end)
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
	if opts then
		M.config = vim.tbl_deep_extend("force", M.config, opts)
	end

	patch_buffer_slash_command()

	log(vim.inspect(M.config))

	local grp = vim.api.nvim_create_augroup("CodeCompanionRules", { clear = true })

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
			local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if filetype == "codecompanion" then
				on_mode(bufnr)
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = grp,
		pattern = "CodeCompanionChatSubmitted",
		callback = function(args)
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			on_submit(bufnr)
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

	vim.api.nvim_create_user_command("CodeCompanionRulesProcess", function()
		on_mode(vim.api.nvim_get_current_buf())
	end, { desc = "Re-evaluate rule references now" })

	vim.api.nvim_create_user_command("CodeCompanionRulesDebug", function()
		M.config.debug = not M.config.debug
		log("CodeCompanion-Rules debug = " .. tostring(M.config.debug))
	end, { desc = "Toggle rules debug" })

	vim.api.nvim_create_user_command("CodeCompanionRulesEnable", function()
		M.config.enabled = true
		notify("Extension enabled")
		on_mode(vim.api.nvim_get_current_buf())
	end, { desc = "Enable CodeCompanion-Rules extension" })

	vim.api.nvim_create_user_command("CodeCompanionRulesDisable", function()
		M.config.enabled = false
		for bufnr in pairs(enabled) do
			enabled[bufnr] = nil
		end
		for bufnr in pairs(fingerprint) do
			fingerprint[bufnr] = nil
		end
		notify("Extension disabled")
	end, { desc = "Disable CodeCompanionRules extension" })
end

return M
