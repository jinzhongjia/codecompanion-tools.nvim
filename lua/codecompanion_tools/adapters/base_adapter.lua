local M = {}

function M.new(name, default_config)
	local adapter = {
		name = name,
		config = default_config or {},
		enabled = true,
		tools = {},
	}

	function adapter:setup(opts)
		self.config = vim.tbl_deep_extend("force", self.config, opts or {})
		self.enabled = self.config.enabled ~= false
		if self.enabled then
			self:init()
		end
	end

	function adapter:init()
		-- Override in subclasses
	end

	function adapter:get_tools()
		return self.enabled and self.tools or {}
	end

	return adapter
end

return M
