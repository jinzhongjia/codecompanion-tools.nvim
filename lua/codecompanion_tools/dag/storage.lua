-- dag/storage.lua
-- Storage layer for DAG checklists using standardized data directory

local utils = require("codecompanion_tools.utils")

local M = {}

---@class ChecklistStorage
---@field storage_path string
local ChecklistStorage = {}
ChecklistStorage.__index = ChecklistStorage

-- Create a new ChecklistStorage instance
function ChecklistStorage.new()
	local self = setmetatable({}, ChecklistStorage)
	self.storage_path = utils.get_data_dir() .. "/dag_checklists.json"
	return self
end

-- Load checklists from storage
function ChecklistStorage:load()
	local file = io.open(self.storage_path, "r")
	if not file then
		return {}, 1
	end

	local content = file:read("*a")
	file:close()

	if content == "" then
		return {}, 1
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return {}, 1
	end

	return data.checklists or {}, data.next_id or 1
end

-- Save checklists to storage
function ChecklistStorage:save(checklists, next_id)
	local data = {
		checklists = checklists,
		next_id = next_id,
	}

	local ok, content = pcall(vim.json.encode, data)
	if not ok then
		return false, "Failed to encode data"
	end

	local file = io.open(self.storage_path, "w")
	if not file then
		return false, "Failed to open file for writing"
	end

	file:write(content)
	file:close()

	return true, nil
end

-- Factory function
function M.new()
	return ChecklistStorage.new()
end

return M
