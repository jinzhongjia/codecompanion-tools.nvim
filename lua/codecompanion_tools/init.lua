-- Main module for codecompanion-tools
-- The actual extension is located in lua/codecompanion/_extensions/codecompanion-tools/init.lua

local M = {}

--- Setup function (for backward compatibility)
---@param opts table Configuration options
function M.setup(opts)
	-- Delegate to the CodeCompanion extension
	local extension = require("codecompanion._extensions.codecompanion-tools")
	return extension.setup(opts)
end

--- Export functions (for backward compatibility)
M.exports = {
	toggle_model = function(bufnr)
		local extension = require("codecompanion._extensions.codecompanion-tools")
		return extension.exports.toggle_model(bufnr)
	end,
}

return M
