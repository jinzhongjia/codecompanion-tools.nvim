-- dag/dag_manager.lua
-- Handles DAG checklist business logic and dependency management

local dag_types = require("codecompanion_tools.dag.dag_types")
local storage_module = require("codecompanion_tools.dag.storage")

local M = {}

---@class DagChecklistManager
---@field storage ChecklistStorage
---@field checklists table<integer, DagChecklist>
---@field next_id integer
local DagChecklistManager = {}
DagChecklistManager.__index = DagChecklistManager

-- Create a new DagChecklistManager instance
function DagChecklistManager.new(storage)
	local self = setmetatable({}, DagChecklistManager)
	self.storage = storage or storage_module.new()
	self.checklists, self.next_id = self.storage:load()
	return self
end

-- Validate dependencies and detect cycles
function DagChecklistManager:validate_dependencies(tasks_data)
	local num_tasks = #tasks_data
	local visited = {}
	local rec_stack = {}

	local function has_cycle(task_idx, adj_list)
		visited[task_idx] = true
		rec_stack[task_idx] = true

		local deps = adj_list[task_idx] or {}
		for _, dep_idx in ipairs(deps) do
			if not visited[dep_idx] then
				if has_cycle(dep_idx, adj_list) then
					return true
				end
			elseif rec_stack[dep_idx] then
				return true
			end
		end

		rec_stack[task_idx] = false
		return false
	end

	-- Build adjacency list
	local adj_list = {}
	for i, task_data in ipairs(tasks_data) do
		local deps = task_data.dependencies or {}
		for _, dep in ipairs(deps) do
			if dep < 1 or dep > num_tasks then
				return false, string.format("Invalid dependency: task %d depends on non-existent task %d", i, dep)
			end
			if dep == i then
				return false, string.format("Self-dependency detected: task %d depends on itself", i)
			end
		end
		adj_list[i] = deps
	end

	-- Check for cycles
	for i = 1, num_tasks do
		if not visited[i] then
			if has_cycle(i, adj_list) then
				return false, "Circular dependency detected"
			end
		end
	end

	return true, nil
end

-- Get topological sort order for task execution
function DagChecklistManager:get_execution_order(tasks)
	local num_tasks = #tasks
	local in_degree = {}
	local adj_list = {}
	local order = {}

	-- Initialize
	for i = 1, num_tasks do
		in_degree[i] = 0
		adj_list[i] = {}
	end

	-- Build graph and calculate in-degrees
	for i, task in ipairs(tasks) do
		local deps = task.dependencies or {}
		for _, dep_idx in ipairs(deps) do
			table.insert(adj_list[dep_idx], i)
			in_degree[i] = in_degree[i] + 1
		end
	end

	-- Kahn's algorithm
	local queue = {}
	for i = 1, num_tasks do
		if in_degree[i] == 0 then
			table.insert(queue, i)
		end
	end

	while #queue > 0 do
		local current = table.remove(queue, 1)
		table.insert(order, current)

		for _, neighbor in ipairs(adj_list[current]) do
			in_degree[neighbor] = in_degree[neighbor] - 1
			if in_degree[neighbor] == 0 then
				table.insert(queue, neighbor)
			end
		end
	end

	return order
end

-- Get tasks with no dependencies that are safe for parallel execution
function DagChecklistManager:get_independent_tasks(tasks)
	local independent = {}
	for i, task in ipairs(tasks) do
		local deps = task.dependencies or {}
		local mode = task.mode or dag_types.TASK_MODE.READWRITE -- Default to safe mode
		-- Only allow parallel execution for read-only tasks with no dependencies
		if #deps == 0 and mode == dag_types.TASK_MODE.READ then
			table.insert(independent, i)
		end
	end
	return independent
end

-- Check if a task's dependencies are satisfied
function DagChecklistManager:are_dependencies_satisfied(checklist, task_idx)
	local task = checklist.tasks[task_idx]
	if not task or not task.dependencies then
		return true
	end

	for _, dep_idx in ipairs(task.dependencies) do
		local dep_task = checklist.tasks[dep_idx]
		if not dep_task or dep_task.status ~= dag_types.TASK_STATUS.COMPLETED then
			return false
		end
	end

	return true
end

-- Get next tasks that can be started (dependencies satisfied)
function DagChecklistManager:get_ready_tasks(checklist)
	local ready = {}
	for i, task in ipairs(checklist.tasks) do
		if task.status == dag_types.TASK_STATUS.PENDING or task.status == dag_types.TASK_STATUS.BLOCKED then
			if self:are_dependencies_satisfied(checklist, i) then
				table.insert(ready, i)
			end
		end
	end
	return ready
end

-- Update task statuses based on dependency resolution
function DagChecklistManager:update_task_statuses(checklist)
	local ready_tasks = self:get_ready_tasks(checklist)

	-- Update blocked tasks to pending if dependencies are satisfied
	for _, task_idx in ipairs(ready_tasks) do
		local task = checklist.tasks[task_idx]
		if task.status == dag_types.TASK_STATUS.BLOCKED then
			task.status = dag_types.TASK_STATUS.PENDING
		end
	end

	-- Set blocked status for tasks with unsatisfied dependencies
	for i, task in ipairs(checklist.tasks) do
		if task.status == dag_types.TASK_STATUS.PENDING then
			if not self:are_dependencies_satisfied(checklist, i) then
				task.status = dag_types.TASK_STATUS.BLOCKED
			end
		end
	end
end

-- Get progress statistics for a DAG checklist
function DagChecklistManager:get_progress(checklist)
	local total = #checklist.tasks
	local completed = 0
	local pending = 0
	local in_progress = 0
	local blocked = 0

	for _, task in ipairs(checklist.tasks) do
		if task.status == dag_types.TASK_STATUS.COMPLETED then
			completed = completed + 1
		elseif task.status == dag_types.TASK_STATUS.PENDING then
			pending = pending + 1
		elseif task.status == dag_types.TASK_STATUS.IN_PROGRESS then
			in_progress = in_progress + 1
		elseif task.status == dag_types.TASK_STATUS.BLOCKED then
			blocked = blocked + 1
		end
	end

	return {
		total = total,
		completed = completed,
		pending = pending,
		in_progress = in_progress,
		blocked = blocked,
	}
end

-- Get the latest incomplete checklist
function DagChecklistManager:get_latest_incomplete()
	local latest = nil
	for _, checklist in pairs(self.checklists) do
		local progress = self:get_progress(checklist)
		if progress.completed < progress.total then
			if not latest or checklist.created_at > latest.created_at then
				latest = checklist
			end
		end
	end
	return latest
end

-- Get a checklist by ID or latest incomplete if no ID provided
function DagChecklistManager:get_checklist(id)
	if not id or id == "" then
		local latest = self:get_latest_incomplete()
		if not latest then
			return nil, "No incomplete checklist found"
		end
		return latest, nil
	end

	local checklist_id = tonumber(id)
	if not checklist_id then
		return nil, "Invalid checklist ID format"
	end

	local checklist = self.checklists[checklist_id]
	if not checklist then
		return nil, "Checklist not found"
	end

	return checklist, nil
end

-- Get all checklists as an array
function DagChecklistManager:get_all_checklists()
	local checklists_array = {}
	for _, checklist in pairs(self.checklists) do
		table.insert(checklists_array, checklist)
	end
	return checklists_array
end

-- Create a new DAG checklist
function DagChecklistManager:create_checklist(goal, tasks_data, subject, body, parallel_results)
	local id = self.next_id
	self.next_id = self.next_id + 1

	-- Validate dependencies
	local valid, err = self:validate_dependencies(tasks_data)
	if not valid then
		return nil, err
	end

	local checklist = {
		id = id,
		goal = goal,
		created_at = os.time(),
		tasks = {},
		log = {
			{
				action = dag_types.LOG_ACTIONS.CREATE,
				subject = subject,
				body = body,
				timestamp = os.time(),
				parallel_results = parallel_results,
			},
		},
		dependency_graph = {},
		execution_order = {},
	}

	-- Process and add tasks
	for i, task_data in ipairs(tasks_data or {}) do
		local task_text = task_data.text or task_data
		if task_text and task_text:match("%S") then
			local task = {
				text = task_text:gsub("^%s*[-*+]?%s*", ""),
				dependencies = task_data.dependencies or {},
				mode = task_data.mode or dag_types.TASK_MODE.READWRITE, -- Default to safe mode
				created_at = os.time(),
			}

			-- Handle parallel execution results (mark as completed but don't store result in task)
			if parallel_results and parallel_results[i] then
				task.status = dag_types.TASK_STATUS.COMPLETED
				task.completed_at = os.time()
			else
				task.status = dag_types.TASK_STATUS.PENDING
			end

			table.insert(checklist.tasks, task)
		end
	end

	-- Calculate execution order
	checklist.execution_order = self:get_execution_order(checklist.tasks)

	-- Update task statuses based on dependencies
	self:update_task_statuses(checklist)

	-- Set first ready task to in_progress
	local ready_tasks = self:get_ready_tasks(checklist)
	if #ready_tasks > 0 then
		checklist.tasks[ready_tasks[1]].status = dag_types.TASK_STATUS.IN_PROGRESS
	end

	self.checklists[id] = checklist
	self:save()
	return checklist, nil
end

-- Find the next in-progress task
function DagChecklistManager:get_next_in_progress_task(checklist)
	for i, task in ipairs(checklist.tasks) do
		if task.status == dag_types.TASK_STATUS.IN_PROGRESS then
			return i, task
		end
	end
	return nil, nil
end

-- Extract file paths from agent references
local function extract_file_paths_from_refs(agent)
	local paths = {}
	local seen = {}
	if agent and agent.chat and agent.chat.refs then
		for _, ref in pairs(agent.chat.refs) do
			local path = nil
			if ref.path then
				path = ref.path
			elseif ref.bufnr then
				path = vim.api.nvim_buf_get_name(ref.bufnr)
			end
			if path and not seen[path] then
				table.insert(paths, path)
				seen[path] = true
			end
		end
	end
	return paths
end

-- Complete a task in DAG checklist
function DagChecklistManager:complete_task(agent, checklist, task_id, subject, body)
	local task_id_num = tonumber(task_id)
	if not task_id_num or task_id_num < 1 or task_id_num > #checklist.tasks then
		return false, "Invalid task ID"
	end

	local task = checklist.tasks[task_id_num]
	if task.status ~= dag_types.TASK_STATUS.IN_PROGRESS then
		return false, "Only tasks that are in progress can be completed"
	end

	task.status = dag_types.TASK_STATUS.COMPLETED
	task.completed_at = os.time()

	-- Update task statuses based on new completion
	self:update_task_statuses(checklist)

	-- Set next ready task to in_progress
	local ready_tasks = self:get_ready_tasks(checklist)
	local next_in_progress = nil
	for _, ready_idx in ipairs(ready_tasks) do
		if checklist.tasks[ready_idx].status == dag_types.TASK_STATUS.PENDING then
			checklist.tasks[ready_idx].status = dag_types.TASK_STATUS.IN_PROGRESS
			next_in_progress = ready_idx
			break
		end
	end

	table.insert(checklist.log, {
		action = dag_types.LOG_ACTIONS.COMPLETE_TASK,
		subject = subject,
		body = body,
		timestamp = os.time(),
		file_paths = extract_file_paths_from_refs(agent),
		completed_task_ids = { task_id_num },
		started_task_id = next_in_progress,
	})

	self:save()
	return true, "Task marked complete"
end

-- Save checklists to storage
function DagChecklistManager:save()
	return self.storage:save(self.checklists, self.next_id)
end

-- Reload checklists from storage
function DagChecklistManager:reload()
	self.checklists, self.next_id = self.storage:load()
end

-- Factory function
function M.new(storage)
	return DagChecklistManager.new(storage)
end

return M
