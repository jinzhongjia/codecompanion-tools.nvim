-- Backward compatibility module
-- Extension is in lua/codecompanion/_extensions/codecompanion-tools/init.lua

local M = {}

--- Setup function for backward compatibility
---@param opts table Configuration options
function M.setup(opts)
	return require("codecompanion._extensions.codecompanion-tools").setup(opts)
end

--- Export functions for backward compatibility
M.exports = {
	toggle_model = function(bufnr)
		return require("codecompanion._extensions.codecompanion-tools").exports.toggle_model(bufnr)
	end,
}

return M
