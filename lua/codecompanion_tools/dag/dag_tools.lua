-- dag/dag_tools.lua
-- DAG checklist tools with proper type annotations and standardized returns

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

---@class ChecklistDagCreateTool
local ChecklistDagCreateTool = {
	name = "checklist_dag_create",
	cmds = {
		---@param agent table
		---@param args table
		---@param input string
		---@param cb function
		function(agent, args, input, cb)
			local goal = args.goal
			local tasks_input = args.tasks or {}
			local subject = args.subject
			local body = args.body

			if not goal or goal == "" then
				return cb({
					status = "error",
					data = {},
					message = "Goal is required",
				})
			end
			if not tasks_input or #tasks_input == 0 then
				return cb({
					status = "error",
					data = {},
					message = "At least one task is required",
				})
			end
			if not subject or subject == "" then
				return cb({
					status = "error",
					data = {},
					message = "subject is required",
				})
			end
			if not body then
				return cb({
					status = "error",
					data = {},
					message = "body is required",
				})
			end

			local system = get_shared_dag_system()
			local manager = system.manager

			-- Parse tasks with dependencies and modes
			local tasks_data = {}
			for i, task_input in ipairs(tasks_input) do
				if type(task_input) == "string" then
					table.insert(tasks_data, {
						text = task_input,
						dependencies = {},
						mode = "readwrite", -- Default to safe mode for string inputs
					})
				elseif type(task_input) == "table" then
					table.insert(tasks_data, {
						text = task_input.text or task_input[1] or "",
						dependencies = task_input.dependencies or {},
						mode = task_input.mode or "readwrite", -- Default to safe mode
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
					-- Create checklist with parallel results
					local checklist, err = manager:create_checklist(goal, tasks_data, subject, body, parallel_results)
					if not checklist then
						return cb({
							status = "error",
							data = {},
							message = err,
						})
					end

					return cb({
						status = "success",
						data = {
							checklist = checklist,
							parallel_results = parallel_results,
						},
					})
				end)

				-- Return early - don't continue to the else branch
				return
			else
				-- No independent tasks, create checklist normally
				local checklist, err = manager:create_checklist(goal, tasks_data, subject, body, {})
				if not checklist then
					return cb({
						status = "error",
						data = {},
						message = err,
					})
				end

				return cb({
					status = "success",
					data = {
						checklist = checklist,
						parallel_results = {},
					},
				})
			end
		end,
	},
	function_call = {},
	schema = {
		type = "function",
		["function"] = {
			name = "checklist_dag_create",
			description = "Create a DAG-enabled checklist with task dependencies and parallel execution of independent tasks",
			parameters = {
				type = "object",
				properties = {
					goal = { type = "string", description = "Goal of the checklist" },
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
						description = "Tasks with optional dependencies",
					},
					subject = { type = "string", description = "Commit subject (summary/title)" },
					body = { type = "string", description = "Commit body (detailed explanation)" },
				},
				required = { "goal", "tasks", "subject", "body" },
				additionalProperties = false,
			},
			strict = true,
		},
	},
	system_prompt = [[Use this tool to create and manage a structured checklist for your current coding session. This helps you track progress, organize complex tasks, and demonstrate thoroughness to the user.

When to use:
- For complex multi-step tasks (3 or more steps)
- For non-trivial and complex work
- When the user explicitly requests a checklist
- When the user provides multiple tasks
- After receiving new instructions or requirements

When NOT to use:
- If there is only a single, trivial task
- If the task can be completed in less than 3 trivial steps
- If the task is purely conversational or informational

Checklist behavior:
- The first task will automatically be set to "in_progress".
- Only read-only tasks with no dependencies will be executed in parallel for safety.

Task modes:
- "read": Safe for parallel execution (analysis, search, reading files)
- "write": Requires context (file modifications, destructive operations)
- "readwrite": Requires context (operations that both read and modify)

Usage:
- All fields are required: goal, tasks, subject, body.
- Tasks can specify mode for safety control.
- Returns the created checklist with all tasks and progress.

Examples:
- checklist_dag_create({
    goal = "Build authentication system",
    tasks = [
      {"text": "Analyze current auth code", "mode": "read", "dependencies": []},
      {"text": "Design auth schema", "mode": "readwrite", "dependencies": []},
      {"text": "Write unit tests", "mode": "write", "dependencies": [2]},
      {"text": "Implement auth logic", "mode": "write", "dependencies": [1, 2, 3]}
    ],
    subject = "Auth system implementation",
    body = "Build complete authentication system with safe parallel execution."
  })
]],
	opts = { requires_approval = true },
	env = nil,
	handlers = {},
	output = {
		success = function(tool, agent, cmd, stdout)
			local response_data = stdout[1]

			if response_data and response_data.checklist then
				local checklist = response_data.checklist
				local parallel_results = response_data.parallel_results or {}

				local system = get_shared_dag_system()
				local dag_formatter = system.formatter
				local manager = system.manager
				local progress = manager:get_progress(checklist)

				-- LLM gets full structured data including parallel results
				local llm_output = vim.inspect({
					checklist = checklist,
					progress = progress,
					parallel_results = parallel_results,
				})

				-- User gets formatted display with parallel results info
				local user_formatted = dag_formatter:format_checklist(checklist, progress)

				-- Add parallel results info to user display if any exist
				if not vim.tbl_isempty(parallel_results) then
					user_formatted = user_formatted .. "\n\nParallel execution results:"
					for task_idx, result in pairs(parallel_results) do
						local truncated = #result > 80 and (result:sub(1, 77) .. "...") or result
						user_formatted = user_formatted .. string.format("\n  Task %d: %s", task_idx, truncated)
					end
				end

				agent.chat:add_tool_output(tool, llm_output, user_formatted)
			else
				agent.chat:add_tool_output(tool, "No DAG checklist data available")
			end
		end,

		error = function(tool, agent, cmd, stderr)
			local response = stderr[1]
			local error_msg = response and response.message or "Unknown error"
			agent.chat:add_tool_output(tool, string.format("**Checklist DAG Tool Error**: %s", error_msg))
		end,

		rejected = function(tool, agent, cmd)
			agent.chat:add_tool_output(tool, "**Checklist DAG Tool**: User declined to execute the operation")
		end,
	},
	["output.prompt"] = function(tool, agent)
		local tasks_count = tool.args.tasks and #tool.args.tasks or 0
		local read_only_count = 0
		if tool.args.tasks then
			for _, task in ipairs(tool.args.tasks) do
				local deps = type(task) == "table" and task.dependencies or {}
				local mode = type(task) == "table" and task.mode or "readwrite"
				-- Only read-only tasks with no dependencies can execute in parallel
				if (#deps == 0) and (mode == "read") then
					read_only_count = read_only_count + 1
				end
			end
		end

		return string.format(
			"Create DAG checklist: '%s' (%d tasks, %d read-only will execute in parallel)?",
			tool.args.goal or "(no goal)",
			tasks_count,
			read_only_count
		)
	end,
	args = {},
	tool = {},
}

---@class ChecklistDagStatusTool
local ChecklistDagStatusTool = {
	name = "checklist_dag_status",
	cmds = {
		---@param agent table
		---@param args table|nil
		---@param input string
		---@param cb function
		function(agent, args, input, cb)
			args = args or {}
			local checklist_id = args.checklist_id
			local system = get_shared_dag_system()
			local manager = system.manager

			local checklist, err = manager:get_checklist(checklist_id)
			if not checklist then
				return cb({
					status = "error",
					data = {},
					message = err,
				})
			end

			return cb({
				status = "success",
				data = checklist,
			})
		end,
	},
	function_call = {},
	schema = {
		type = "function",
		["function"] = {
			name = "checklist_dag_status",
			description = "Use this tool to read the status of a specific DAG checklist. If checklist_id is omitted, the latest incomplete checklist will be used.",
			parameters = {
				type = "object",
				properties = {
					checklist_id = {
						type = "string",
						description = "Checklist ID to show status for (optional, defaults to latest incomplete checklist)",
					},
				},
				required = {},
				additionalProperties = false,
			},
			strict = true,
		},
	},
	system_prompt = [[Use this tool to read the status, log, and progress details of a specific checklist.

When to use:
- When you need to see the full details, log, and progress of a specific checklist
- Before making changes, marking tasks complete, or reporting progress

When NOT to use:
- If you want to see all checklists, use checklist_dag_list instead.

Usage:
- checklist_id is optional. If omitted, pass an empty object: {}.
- Returns full checklist details including tasks, log, and progress metrics.
- This is read-only.

Examples:
- checklist_dag_status({}) -- status of latest incomplete DAG checklist
- checklist_dag_status({ checklist_id = "2" }) -- status of DAG checklist with ID 2
]],
	opts = {},
	env = nil,
	handlers = {},
	output = {
		success = function(tool, agent, cmd, stdout)
			local checklist = stdout[1]

			if checklist then
				local system = get_shared_dag_system()
				local dag_formatter = system.formatter
				local manager = system.manager
				local progress = manager:get_progress(checklist)

				-- LLM gets full structured data
				local llm_output = vim.inspect({
					checklist = checklist,
					progress = progress,
				})

				-- User gets formatted display
				local user_formatted = dag_formatter:format_checklist(checklist, progress)
				agent.chat:add_tool_output(tool, llm_output, user_formatted)
			else
				agent.chat:add_tool_output(tool, "No DAG checklist data available")
			end
		end,

		error = function(tool, agent, cmd, stderr)
			local response = stderr[1]
			local error_msg = response and response.message or "Unknown error"
			agent.chat:add_tool_output(tool, string.format("**Checklist DAG Status Tool Error**: %s", error_msg))
		end,

		rejected = function(tool, agent, cmd)
			agent.chat:add_tool_output(tool, "**Checklist DAG Status Tool**: User declined to execute the operation")
		end,
	},
	args = {},
	tool = {},
}

---@class ChecklistDagListTool
local ChecklistDagListTool = {
	name = "checklist_dag_list",
	cmds = {
		---@param agent table
		---@param args table
		---@param input string
		---@param cb function
		function(agent, args, input, cb)
			local system = get_shared_dag_system()
			local manager = system.manager

			local all_checklists = manager:get_all_checklists()

			return cb({
				status = "success",
				data = all_checklists,
			})
		end,
	},
	function_call = {},
	schema = {
		type = "function",
		["function"] = {
			name = "checklist_dag_list",
			description = "Use this tool to read the current DAG checklist(s) for the workspace",
		},
	},
	system_prompt = [[Use this tool to read the current checklist(s) for the workspace.

When to use:
- At the beginning of conversations to see what's pending
- Before starting new tasks to prioritize work
- When the user asks about previous tasks or plans
- Whenever you're uncertain about what to do next
- After completing tasks to update your understanding of remaining work
- After every few messages to ensure you're on track

When NOT to use:
- If you only need the status of a specific checklist, use checklist_dag_status instead.

Usage:
- This tool takes in no parameters. Call it with no arguments.
- Returns a list of checklists with their status, progress, and tasks.
- If no checklists exist yet, an empty list will be returned.

Examples:
- checklist_dag_list()
]],
	opts = {},
	env = nil,
	handlers = {},
	output = {
		success = function(tool, agent, cmd, stdout)
			local checklists = stdout[1]

			-- Extract progress for each checklist
			local system = get_shared_dag_system()
			local manager = system.manager
			local checklists_with_progress = {}
			for _, checklist in ipairs(checklists) do
				local progress = manager:get_progress(checklist)
				table.insert(checklists_with_progress, {
					checklist = checklist,
					progress = progress,
				})
			end

			-- LLM sees structured data, user sees formatted list
			local llm_output = vim.inspect(checklists_with_progress)

			-- Generate detailed user message with numbered entries
			local user_msg
			if #checklists == 0 then
				user_msg = "**Checklist DAG List Tool**: No DAG checklists found"
			else
				user_msg = string.format(
					"**Checklist DAG List Tool**: Found %d DAG checklist%s:\n",
					#checklists,
					#checklists == 1 and "" or "s"
				)

				-- Sort by creation time (newest first) for display
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
		end,

		error = function(tool, agent, cmd, stderr)
			local response = stderr[1]
			local error_msg = response and response.message or "Unknown error"
			agent.chat:add_tool_output(tool, string.format("**Checklist DAG List Tool Error**: %s", error_msg))
		end,

		rejected = function(tool, agent, cmd)
			agent.chat:add_tool_output(tool, "**Checklist DAG List Tool**: User declined to execute the operation")
		end,
	},
	args = {},
	tool = {},
}

---@class ChecklistDagCompleteTaskTool
local ChecklistDagCompleteTaskTool = {
	name = "checklist_dag_complete_task",
	cmds = {
		---@param agent table
		---@param args table
		---@param input string
		---@param cb function
		function(agent, args, input, cb)
			local checklist_id = args.checklist_id
			local task_id = args.task_id
			local subject = args.subject
			local body = args.body

			local system = get_shared_dag_system()
			local manager = system.manager

			local checklist, err = manager:get_checklist(checklist_id)
			if not checklist then
				return cb({
					status = "error",
					data = {},
					message = err,
				})
			end
			if not task_id then
				return cb({
					status = "error",
					data = {},
					message = "task_id is required",
				})
			end
			if not subject or subject == "" then
				return cb({
					status = "error",
					data = {},
					message = "subject is required",
				})
			end
			if not body then
				return cb({
					status = "error",
					data = {},
					message = "body is required",
				})
			end

			local success, msg = manager:complete_task(agent, checklist, task_id, subject, body)
			if not success then
				return cb({
					status = "error",
					data = {},
					message = msg,
				})
			end

			return cb({
				status = "success",
				data = checklist,
			})
		end,
	},
	function_call = {},
	schema = {
		type = "function",
		["function"] = {
			name = "checklist_dag_complete_task",
			description = "Use this tool to mark the current in-progress task as complete in a DAG checklist. If checklist_id is omitted, the latest incomplete checklist will be used.",
			parameters = {
				type = "object",
				properties = {
					checklist_id = {
						type = "string",
						description = "Checklist ID to update (optional, defaults to latest incomplete checklist)",
					},
					task_id = { type = "string", description = "Task ID to mark complete (must be in progress)" },
					subject = { type = "string", description = "Commit subject (summary/title)" },
					body = { type = "string", description = "Commit body (detailed explanation)" },
				},
				required = { "task_id", "subject", "body" },
				additionalProperties = false,
			},
			strict = true,
		},
	},
	system_prompt = [[Use this tool to mark the current in-progress task as complete in a checklist. Only one task can be completed at a time. When a task is completed, the next pending task (if any) is automatically set to "in_progress". If checklist_id is omitted, the latest incomplete checklist will be used.

When to use:
- Immediately after completing the current in-progress task
- After verification and testing
- When user confirms acceptance

When NOT to use:
- If there is no checklist or no in-progress task

Checklist behavior:
- Only tasks that are "in_progress" can be completed.
- The next pending task will automatically be set to "in_progress".

Usage:
- checklist_id is optional.
- All other fields are required: task_id, subject, body.
- Returns the updated checklist with all tasks and progress.

Examples:
- checklist_dag_complete_task({
    task_id = "1",
    subject = "Completed auth schema design",
    body = "Designed comprehensive authentication schema with user roles."
  })
- checklist_dag_complete_task({
    checklist_id = "2",
    task_id = "3",
    subject = "Updated docs",
    body = "Documentation updated for new auth flow."
  })
]],
	opts = { requires_approval = true },
	env = nil,
	handlers = {},
	output = {
		success = function(tool, agent, cmd, stdout)
			local checklist = stdout[1]

			if checklist then
				local system = get_shared_dag_system()
				local dag_formatter = system.formatter
				local manager = system.manager

				-- Get next in-progress task or completion message
				local next_idx, next_task = manager:get_next_in_progress_task(checklist)

				-- LLM gets full structured data
				local llm_output = vim.inspect({
					checklist = checklist,
					next_task_idx = next_idx,
					next_task = next_task,
				})

				-- User gets formatted completion message
				local user_formatted = dag_formatter:format_task_completion(checklist, next_idx, next_task)
				agent.chat:add_tool_output(tool, llm_output, user_formatted)
			else
				agent.chat:add_tool_output(tool, "No DAG checklist data available")
			end
		end,

		error = function(tool, agent, cmd, stderr)
			local response = stderr[1]
			local error_msg = response and response.message or "Unknown error"
			agent.chat:add_tool_output(tool, string.format("**Checklist DAG Complete Task Tool Error**: %s", error_msg))
		end,

		rejected = function(tool, agent, cmd)
			agent.chat:add_tool_output(
				tool,
				"**Checklist DAG Complete Task Tool**: User declined to execute the operation"
			)
		end,
	},
	["output.prompt"] = function(tool, agent)
		return string.format(
			"Complete DAG task %s in checklist %s?",
			tool.args.task_id or "(n/a)",
			tool.args.checklist_id or "latest"
		)
	end,
	args = {},
	tool = {},
}

local M = {
	checklist_dag_list = {
		description = "Read the current DAG checklist(s) for the workspace",
		callback = ChecklistDagListTool,
	},
	checklist_dag_create = {
		description = "Create a DAG-enabled checklist with task dependencies and parallel execution",
		callback = ChecklistDagCreateTool,
	},
	checklist_dag_status = {
		description = "Read the status of a specific DAG checklist (or latest incomplete)",
		callback = ChecklistDagStatusTool,
	},
	checklist_dag_complete_task = {
		description = "Mark the current in-progress task as complete in a DAG checklist",
		callback = ChecklistDagCompleteTaskTool,
	},
}

return M
