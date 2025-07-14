local utils = require("codecompanion_tools.utils")

local M = {}

--- Get chat object for buffer
---@param bufnr integer
---@return table|nil
function M.get_chat(bufnr)
	local ok, chat_strategy = pcall(require, "codecompanion.strategies.chat")
	if not ok or not chat_strategy.buf_get_chat then
		return nil
	end

	local chat_ok, chat = pcall(chat_strategy.buf_get_chat, bufnr)
	return chat_ok and chat or nil
end

--- Check if buffer is codecompanion chat
---@param bufnr integer
---@return boolean
function M.is_chat_buffer(bufnr)
	return vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "codecompanion"
end

--- Get current model from chat
---@param chat table
---@return string|nil
function M.get_current_model(chat)
	if not chat or not chat.adapter then
		return nil
	end
	return (type(chat.adapter.model) == "table" and chat.adapter.model.name) or chat.settings.model
end

--- Apply model to chat
---@param chat table
---@param model string
function M.apply_model(chat, model)
	chat:apply_model(model)
	chat:apply_settings()
end

--- Check if reference is file reference
---@param ref table
---@return boolean
function M.is_file_ref(ref)
	return (type(ref.id) == "string" and (ref.id:match("^<file>") or ref.id:match("^<buf>")))
		or (type(ref.source) == "string" and (ref.source:match("%.file$") or ref.source:match("%.buffer$")))
end

--- Extract path from reference ID
---@param id string
---@return string
function M.id_to_path(id)
	return id:match("^<file>(.*)</file>$") or id:match("^<buf>(.*)</buf>$") or id
end

--- Create file reference
---@param chat table
---@param path string
---@param opts? table
---@return boolean success
function M.create_file_ref(chat, path, opts)
	opts = opts or {}
	local rel_path = vim.fn.fnamemodify(path, ":.")
	local bufnr = vim.fn.bufnr(rel_path)
	local is_loaded = bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)

	local buffer_cmd_ok, buffer_cmd = pcall(require, "codecompanion.strategies.chat.slash_commands.buffer")
	local file_cmd_ok, file_cmd = pcall(require, "codecompanion.strategies.chat.slash_commands.file")

	if is_loaded and buffer_cmd_ok then
		buffer_cmd.new({ Chat = chat }):output({ bufnr = bufnr, path = rel_path }, opts)
		return true
	elseif file_cmd_ok then
		file_cmd.new({ Chat = chat }):output({ path = rel_path }, opts)
		return true
	end

	return false
end

--- Re-render chat context
---@param chat table
function M.rerender_context(chat)
	vim.schedule(function()
		if not chat.bufnr or not vim.api.nvim_buf_is_valid(chat.bufnr) then
			return
		end

		local start = chat.header_line + 1
		local last = vim.api.nvim_buf_line_count(chat.bufnr)
		local i = start

		-- Find end of context area
		while i < last do
			local line = vim.api.nvim_buf_get_lines(chat.bufnr, i, i + 1, false)[1] or ""
			if line == "" or line:match("^> ") then
				i = i + 1
			else
				break
			end
		end

		-- Clear old context
		if i > start then
			chat.ui:unlock_buf()
			vim.api.nvim_buf_set_lines(chat.bufnr, start, i, false, {})
		end

		-- Re-render references
		if chat.references and chat.references.render then
			chat.ui:unlock_buf()
			chat.references:render()
		end

		chat.ui:unlock_buf()
	end)
end

return M
