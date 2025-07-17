local base_adapter = require("codecompanion_tools.adapters.base_adapter")
local dag_system = require("codecompanion_tools.dag.dag_system")
local config_utils = require("codecompanion_tools.config")

local adapter = base_adapter.new("dag", {
	enabled = true,
	storage_backend = "file",
	debug = false,
})

function adapter:init()
	-- 获取 DAG 系统实例
	self.dag_instance = dag_system.get_instance()

	-- 注册工具
	self.tools = {
		checklist = require("codecompanion_tools.dag.checklist_tool").checklist,
	}

	-- 创建命令
	config_utils.setup_commands("CodeCompanionDAG", {
		Reset = {
			callback = function()
				dag_system.reset()
				self.dag_instance = dag_system.get_instance()
				print("DAG system reset")
			end,
			desc = "Reset DAG system",
		},
		Debug = {
			callback = function()
				self.config.debug = not self.config.debug
				print("DAG debug mode:", self.config.debug)
			end,
			desc = "Toggle DAG debug mode",
		},
	})
end

return adapter
