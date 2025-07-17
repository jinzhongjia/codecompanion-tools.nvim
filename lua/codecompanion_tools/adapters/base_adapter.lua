local BaseAdapter = {}
BaseAdapter.__index = BaseAdapter

function BaseAdapter:new(name, config)
	local adapter = {
		name = name,
		config = config or {},
		enabled = true,
		tools = {},
		commands = {},
		initialized = false,
	}
	setmetatable(adapter, self)
	return adapter
end

function BaseAdapter:setup(opts)
	self.config = vim.tbl_deep_extend("force", self.config, opts or {})
	self.enabled = self.config.enabled ~= false
	if self.enabled then
		self:initialize()
	end
end

function BaseAdapter:initialize()
	self.initialized = true
end

function BaseAdapter:enable()
	if not self.enabled then
		self.enabled = true
		if not self.initialized then
			self:initialize()
		end
	end
end

function BaseAdapter:disable()
	self.enabled = false
	self:cleanup()
end

function BaseAdapter:cleanup() end

function BaseAdapter:get_tools()
	return self.enabled and self.tools or {}
end

return BaseAdapter
