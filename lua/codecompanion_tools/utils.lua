local M = {}

--- Normalize path using Neovim's built-in functions
---@param path string
---@return string
function M.normalize_path(path)
	if not path or path == "" then
		return ""
	end
	-- Use Neovim's built-in path normalization
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

--- Clean whitespace and quotes from path
---@param path string
---@return string
function M.clean_path(path)
	if not path then
		return ""
	end
	return path:gsub("^[`\"'%s]+", ""):gsub("[`\"'%s]+$", "")
end

--- Check if file exists and is readable
---@param path string
---@return boolean
function M.file_exists(path)
	return vim.uv.fs_stat(path) ~= nil
end

--- Find first existing file from a list in directory
---@param dir string
---@param filenames string[]
---@return string|nil
function M.find_first_file(dir, filenames)
	for _, name in ipairs(filenames) do
		local path = vim.fs.joinpath(dir, name)
		if M.file_exists(path) then
			return path
		end
	end
	return nil
end

--- Get project root directory
---@return string
function M.get_project_root()
	return M.normalize_path(vim.fn.getcwd())
end

--- Check if path is within project
---@param path string
---@param project_root? string
---@return boolean
function M.is_within_project(path, project_root)
	project_root = project_root or M.get_project_root()
	local normalized_path = M.normalize_path(path)
	return vim.startswith(normalized_path, project_root)
end

--- Create hash from string list
---@param list string[]
---@return string
function M.create_hash(list)
	if #list == 0 then
		return ""
	end
	local sorted = vim.deepcopy(list)
	table.sort(sorted)
	return table.concat(sorted, "|")
end

--- Log debug message
---@param msg string
---@param debug boolean
function M.log(msg, debug)
	if debug then
		print("[CodeCompanion-Tools] " .. msg)
	end
end

--- Show notification
---@param msg string
---@param level? integer
---@param title? string
function M.notify(msg, level, title)
	vim.schedule(function()
		vim.notify(msg, level or vim.log.levels.INFO, {
			title = title or "CodeCompanion-Tools"
		})
	end)
end

return M