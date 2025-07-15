-- dag/checklist_tool.lua
-- Unified checklist tool with action-based interface

local dag_manager_module = require("codecompanion_tools.dag.dag_manager")
local dag_formatter_module = require("codecompanion_tools.dag.dag_formatter")
local dag_executor = require("codecompanion_tools.dag.dag_executor")
local storage_module = require("codecompanion_tools.dag.storage")

-- Create DAG system instance
---@return table
local function get_dag_system()
	local storage = storage_module.new()
	local manager = dag_manager_module.new(storage)
	local formatter = dag_formatter_module.new()

	return {
		storage = storage,
		manager = manager,
		formatter = formatter,
	}
end

-- Get the shared DAG system instance
local dag_system = nil
---@return table
local function get_shared_dag_system()
	if not dag_system then
		dag_system = get_dag_system()
	end
	return dag_system
end

---@class ChecklistTool
local ChecklistTool = {
	name = "checklist",
	cmds = {
		---@param agent table
		---@param args table
		---@param input string
		---@param cb function
		function(agent, args, input, cb)
			local action = args.action
			local system = get_shared_dag_system()
			local manager = system.manager
			local formatter = system.formatter

			if action == "create" then
				local goal = args.goal
				local tasks_input = args.tasks or {}
				local subject = args.subject
				local body = args.body

				-- Validation
				if not goal or goal == "" then
					return cb({ status = "error", data = {}, message = "Goal is required" })
				end
				if not tasks_input or #tasks_input == 0 then
					return cb({ status = "error", data = {}, message = "At least one task is required" })
				end
				if not subject or subject == "" then
					return cb({ status = "error", data = {}, message = "Subject is required" })
				end
				if not body then
					return cb({ status = "error", data = {}, message = "Body is required" })
				end

				-- Parse tasks with dependencies and modes
				local tasks_data = {}
				for i, task_input in ipairs(tasks_input) do
					if type(task_input) == "string" then
						table.insert(tasks_data, {
							text = task_input,
							dependencies = {},
							mode = "readwrite",
						})
					elseif type(task_input) == "table" then
						table.insert(tasks_data, {
							text = task_input.text or task_input[1] or "",
							dependencies = task_input.dependencies or {},
							mode = task_input.mode or "readwrite",
						})
					end
				end

				-- Get independent tasks for parallel execution
				local independent_tasks = manager:get_independent_tasks(tasks_data)

				if #independent_tasks > 0 then
					-- Prepare tasks for parallel execution
					local tasks_to_execute = {}
					for _, task_idx in ipairs(independent_tasks) do
						table.insert(tasks_to_execute, {
							index = task_idx,
							text = tasks_data[task_idx].text,
						})
					end

					-- Get current chat context
					local parent_bufnr = vim.api.nvim_get_current_buf()
					local parent_chat = require("codecompanion.strategies.chat").buf_get_chat(parent_bufnr)

					-- Execute independent tasks in parallel
					dag_executor.execute_tasks_parallel(tasks_to_execute, parent_chat, function(parallel_results)
						local checklist, err =
							manager:create_checklist(goal, tasks_data, subject, body, parallel_results)
						if not checklist then
							return cb({ status = "error", data = {}, message = err })
						end
						return cb({
							status = "success",
							data = { checklist = checklist, parallel_results = parallel_results },
						})
					end)
					return
				else
					-- No independent tasks, create checklist normally
					local checklist, err = manager:create_checklist(goal, tasks_data, subject, body, {})
					if not checklist then
						return cb({ status = "error", data = {}, message = err })
					end
					return cb({ status = "success", data = { checklist = checklist, parallel_results = {} } })
				end
			elseif action == "list" then
				local all_checklists = manager:get_all_checklists()
				return cb({ status = "success", data = all_checklists })
			elseif action == "status" then
				local checklist_id = args.checklist_id
				local checklist, err = manager:get_checklist(checklist_id)
				if not checklist then
					return cb({ status = "error", data = {}, message = err })
				end
				return cb({ status = "success", data = checklist })
			elseif action == "complete" then
				local checklist_id = args.checklist_id
				local task_id = args.task_id
				local subject = args.subject
				local body = args.body

				local checklist, err = manager:get_checklist(checklist_id)
				if not checklist then
					return cb({ status = "error", data = {}, message = err })
				end
				if not task_id then
					return cb({ status = "error", data = {}, message = "task_id is required" })
				end
				if not subject or subject == "" then
					return cb({ status = "error", data = {}, message = "subject is required" })
				end
				if not body then
					return cb({ status = "error", data = {}, message = "body is required" })
				end

				local success, msg = manager:complete_task(agent, checklist, task_id, subject, body)
				if not success then
					return cb({ status = "error", data = {}, message = msg })
				end
				return cb({ status = "success", data = checklist })
			else
				return cb({
					status = "error",
					data = {},
					message = "Invalid action. Use: create, list, status, or complete",
				})
			end
		end,
	},
	function_call = {},
	schema = {
		type = "function",
		["function"] = {
			name = "checklist",
			description = "Manage task checklists with dependency resolution and parallel execution",
			parameters = {
				type = "object",
				properties = {
					action = {
						type = "string",
						enum = { "create", "list", "status", "complete" },
						description = "Action to perform: create, list, status, or complete",
					},
					-- Create action parameters
					goal = { type = "string", description = "Goal of the checklist (for create action)" },
					tasks = {
						type = "array",
						items = {
							oneOf = {
								{ type = "string" },
								{
									type = "object",
									properties = {
										text = { type = "string", description = "Task description" },
										dependencies = {
											type = "array",
											items = { type = "integer" },
											description = "Array of task indices (1-based) that must complete first",
										},
										mode = {
											type = "string",
											enum = { "read", "write", "readwrite" },
											description = "Access mode: 'read' (safe for parallel), 'write' or 'readwrite' (requires context)",
										},
									},
									required = { "text" },
								},
							},
						},
						description = "Tasks with optional dependencies (for create action)",
					},
					subject = { type = "string", description = "Commit subject (for create/complete actions)" },
					body = { type = "string", description = "Commit body (for create/complete actions)" },
					-- Status/complete action parameters
					checklist_id = {
						type = "string",
						description = "Checklist ID (optional, defaults to latest incomplete)",
					},
					task_id = { type = "string", description = "Task ID to mark complete (for complete action)" },
				},
				required = { "action" },
				additionalProperties = false,
			},
			strict = true,
		},
	},
	system_prompt = [[
Use this tool to manage task checklists with dependency resolution and parallel execution.

Actions available:
- create: Create a new checklist with tasks and dependencies
- list: List all existing checklists
- status: Get detailed status of a checklist
- complete: Mark a task as complete

Task modes:
- "read": Safe for parallel execution (analysis, search, reading files)
- "write": Requires context (file modifications, destructive operations)
- "readwrite": Requires context (operations that both read and modify)

Examples:

1. Create a checklist:
checklist({
  action = "create",
  goal = "Implement user authentication",
  tasks = [
    { text = "Analyze current code", mode = "read", dependencies = [] },
    { text = "Design schema", mode = "readwrite", dependencies = [1] },
    { text = "Write tests", mode = "write", dependencies = [2] },
    { text = "Implement logic", mode = "write", dependencies = [1, 2, 3] }
  ],
  subject = "Auth implementation",
  body = "Complete authentication system"
})

2. List all checklists:
checklist({ action = "list" })

3. Check status:
checklist({ action = "status", checklist_id = "2" })

4. Complete a task:
checklist({
  action = "complete",
  task_id = "1",
  subject = "Completed analysis",
  body = "Analyzed codebase patterns"
})

Features:
- Tasks with mode="read" and no dependencies execute in parallel automatically
- Dependency resolution prevents circular dependencies
- Progress tracking with visual indicators
- Persistent storage across sessions
]],
	opts = { requires_approval = true },
	env = nil,
	handlers = {},
	output = {
		success = function(tool, agent, cmd, stdout)
			local response_data = stdout[1]
			local action = tool.args.action
			local system = get_shared_dag_system()
			local formatter = system.formatter
			local manager = system.manager

			if action == "create" then
				if response_data and response_data.checklist then
					local checklist = response_data.checklist
					local parallel_results = response_data.parallel_results or {}
					local progress = manager:get_progress(checklist)

					local llm_output = vim.inspect({
						checklist = checklist,
						progress = progress,
						parallel_results = parallel_results,
					})

					local user_formatted = formatter:format_checklist(checklist, progress)
					if not vim.tbl_isempty(parallel_results) then
						user_formatted = user_formatted .. "\n\nParallel execution results:"
						for task_idx, result in pairs(parallel_results) do
							local truncated = #result > 80 and (result:sub(1, 77) .. "...") or result
							user_formatted = user_formatted .. string.format("\n  Task %d: %s", task_idx, truncated)
						end
					end

					agent.chat:add_tool_output(tool, llm_output, user_formatted)
				else
					agent.chat:add_tool_output(tool, "No checklist data available")
				end
			elseif action == "list" then
				local checklists = response_data
				local checklists_with_progress = {}
				for _, checklist in ipairs(checklists) do
					local progress = manager:get_progress(checklist)
					table.insert(checklists_with_progress, {
						checklist = checklist,
						progress = progress,
					})
				end

				local llm_output = vim.inspect(checklists_with_progress)

				local user_msg
				if #checklists == 0 then
					user_msg = "**Checklist Tool**: No checklists found"
				else
					user_msg = string.format(
						"**Checklist Tool**: Found %d checklist%s:\n",
						#checklists,
						#checklists == 1 and "" or "s"
					)

					local sorted_for_display = vim.deepcopy(checklists_with_progress)
					table.sort(sorted_for_display, function(a, b)
						return a.checklist.created_at > b.checklist.created_at
					end)

					for i, item in ipairs(sorted_for_display) do
						local checklist = item.checklist
						local progress = item.progress
						user_msg = user_msg
							.. string.format(
								"%d. **%s** (ID: %d)\n   • Progress: %d/%d tasks complete (%d blocked)\n   • Created: %s\n",
								i,
								checklist.goal or "No goal",
								checklist.id,
								progress.completed,
								progress.total,
								progress.blocked,
								os.date("%Y-%m-%d %H:%M", checklist.created_at)
							)
					end
				end

				agent.chat:add_tool_output(tool, llm_output, user_msg)
			elseif action == "status" then
				local checklist = response_data
				if checklist then
					local progress = manager:get_progress(checklist)
					local llm_output = vim.inspect({ checklist = checklist, progress = progress })
					local user_formatted = formatter:format_checklist(checklist, progress)
					agent.chat:add_tool_output(tool, llm_output, user_formatted)
				else
					agent.chat:add_tool_output(tool, "No checklist data available")
				end
			elseif action == "complete" then
				local checklist = response_data
				if checklist then
					local next_idx, next_task = manager:get_next_in_progress_task(checklist)
					local llm_output = vim.inspect({
						checklist = checklist,
						next_task_idx = next_idx,
						next_task = next_task,
					})
					local user_formatted = formatter:format_task_completion(checklist, next_idx, next_task)
					agent.chat:add_tool_output(tool, llm_output, user_formatted)
				else
					agent.chat:add_tool_output(tool, "No checklist data available")
				end
			end
		end,

		error = function(tool, agent, cmd, stderr)
			local response = stderr[1]
			local error_msg = response and response.message or "Unknown error"
			agent.chat:add_tool_output(tool, string.format("**Checklist Tool Error**: %s", error_msg))
		end,

		rejected = function(tool, agent, cmd)
			agent.chat:add_tool_output(tool, "**Checklist Tool**: User declined to execute the operation")
		end,
	},
	["output.prompt"] = function(tool, agent)
		local action = tool.args.action
		if action == "create" then
			local tasks_count = tool.args.tasks and #tool.args.tasks or 0
			local read_only_count = 0
			if tool.args.tasks then
				for _, task in ipairs(tool.args.tasks) do
					local deps = type(task) == "table" and task.dependencies or {}
					local mode = type(task) == "table" and task.mode or "readwrite"
					if (#deps == 0) and (mode == "read") then
						read_only_count = read_only_count + 1
					end
				end
			end
			return string.format(
				"Create checklist: '%s' (%d tasks, %d read-only will execute in parallel)?",
				tool.args.goal or "(no goal)",
				tasks_count,
				read_only_count
			)
		elseif action == "complete" then
			return string.format(
				"Complete task %s in checklist %s?",
				tool.args.task_id or "(n/a)",
				tool.args.checklist_id or "latest"
			)
		else
			return string.format("Execute checklist %s action?", action)
		end
	end,
	args = {},
	tool = {},
}

local M = {
	checklist = {
		description = "Manage task checklists with dependency resolution and parallel execution",
		callback = ChecklistTool,
	},
}

return M
