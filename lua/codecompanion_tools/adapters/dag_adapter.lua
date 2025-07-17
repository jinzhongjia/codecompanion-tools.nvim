local BaseAdapter = require("codecompanion_tools.adapters.base_adapter")
local dag_system = require("codecompanion_tools.dag.dag_system")

local DagAdapter = BaseAdapter:new("dag", {
	enabled = true,
	storage_backend = "file",
	debug = false,
})

function DagAdapter:initialize()
	BaseAdapter.initialize(self)

	-- 初始化 DAG 系统
	self.dag_instance = dag_system.get_instance()

	-- 创建工具
	self.tools = {
		checklist = self:create_checklist_tool(),
		dag_visualize = self:create_dag_visualize_tool(),
		dag_execute = self:create_dag_execute_tool(),
	}

	-- 创建命令
	self:setup_commands()
end

function DagAdapter:create_checklist_tool()
	local checklist_tool = require("codecompanion_tools.dag.checklist_tool")
	return checklist_tool.checklist
end

function DagAdapter:create_dag_visualize_tool()
	return {
		name = "dag_visualize",
		description = "Visualize DAG structure",
		parameters = {
			type = "object",
			properties = {
				format = {
					type = "string",
					enum = { "text", "json" },
					default = "text",
				},
			},
		},
		run = function(args)
			local formatter = self.dag_instance.formatter
			local manager = self.dag_instance.manager

			local dag_data = manager:get_all_nodes()
			if args.format == "json" then
				return vim.json.encode(dag_data)
			else
				return formatter:format_dag(dag_data)
			end
		end,
	}
end

function DagAdapter:create_dag_execute_tool()
	return {
		name = "dag_execute",
		description = "Execute DAG workflow",
		parameters = {
			type = "object",
			properties = {
				workflow_id = {
					type = "string",
					description = "Workflow ID to execute",
				},
			},
			required = { "workflow_id" },
		},
		run = function(args)
			local executor = require("codecompanion_tools.dag.dag_executor")
			return executor.execute_workflow(args.workflow_id)
		end,
	}
end

function DagAdapter:setup_commands()
	local config_utils = require("codecompanion_tools.config")

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

function DagAdapter:cleanup()
	-- 清理资源
	if self.dag_instance then
		dag_system.reset()
		self.dag_instance = nil
	end
end

return DagAdapter
