local M = {}

--- Get extension configuration from CodeCompanion config
---@param extension_name string
---@param sub_config? string
---@return table
function M.get_extension_config(extension_name, sub_config)
	local ok, cfg = pcall(require, "codecompanion.config")
	if not ok then
		return {}
	end

	local ext_config = cfg.extensions and cfg.extensions[extension_name] and cfg.extensions[extension_name].opts

	if not ext_config then
		return {}
	end

	if sub_config then
		return ext_config[sub_config] or {}
	end

	return ext_config
end

--- Deep merge configuration with defaults
---@param default table
---@param override table
---@return table
function M.merge_config(default, override)
	return vim.tbl_deep_extend("force", default, override or {})
end

--- Setup autocmd group with cleanup
---@param name string
---@return integer group_id
function M.create_augroup(name)
	return vim.api.nvim_create_augroup(name, { clear = true })
end

--- Setup user commands with consistent naming
---@param prefix string
---@param commands table<string, {callback: function, desc: string}>
function M.setup_commands(prefix, commands)
	for name, cmd in pairs(commands) do
		local command_name = prefix .. name
		vim.api.nvim_create_user_command(command_name, cmd.callback, {
			desc = cmd.desc,
		})
	end
end

--- Setup buffer-local keymap for codecompanion buffers
---@param key string
---@param callback function
---@param desc string
function M.setup_buffer_keymap(key, callback, desc)
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "codecompanion",
		callback = function(args)
			vim.keymap.set("n", key, callback, {
				buffer = args.buf,
				desc = desc,
				silent = true,
			})
		end,
	})
end

--- Setup CodeCompanion strategy keymap
---@param key string
---@param callback function
---@param desc string
---@param keymap_name string
function M.setup_strategy_keymap(key, callback, desc, keymap_name)
	local ok, cfg = pcall(require, "codecompanion.config")
	if not ok then
		return
	end

	if cfg.strategies and cfg.strategies.chat and type(cfg.strategies.chat.keymaps) == "table" then
		cfg.strategies.chat.keymaps[keymap_name] = {
			modes = { n = key },
			description = desc,
			callback = callback,
		}
	end
end

return M
