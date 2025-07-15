-- dag/dag_formatter.lua
-- Handles DAG checklist output formatting and dependency visualization

local dag_types = require("codecompanion_tools.dag.dag_types")

local M = {}

---@class DagChecklistFormatter
local DagChecklistFormatter = {}
DagChecklistFormatter.__index = DagChecklistFormatter

-- Create a new DagChecklistFormatter instance
function DagChecklistFormatter.new()
	local self = setmetatable({}, DagChecklistFormatter)
	return self
end

-- Get status icon for a task status (includes blocked status)
function DagChecklistFormatter:get_status_icon(status)
	if status == dag_types.TASK_STATUS.COMPLETED then
		return "[✓]"
	elseif status == dag_types.TASK_STATUS.IN_PROGRESS then
		return "[~]"
	elseif status == dag_types.TASK_STATUS.BLOCKED then
		return "[!]"
	else
		return "[ ]"
	end
end

-- Format dependency information for a task
function DagChecklistFormatter:format_dependencies(task, task_idx, checklist)
	if not task.dependencies or #task.dependencies == 0 then
		return ""
	end

	local dep_strs = {}
	for _, dep_idx in ipairs(task.dependencies) do
		local dep_task = checklist.tasks[dep_idx]
		local dep_status = dep_task and self:get_status_icon(dep_task.status) or "?"
		table.insert(dep_strs, string.format("%d%s", dep_idx, dep_status))
	end

	return string.format(" *(needs: %s)*", table.concat(dep_strs, ","))
end

-- Get mode icon for a task access mode
function DagChecklistFormatter:get_mode_icon(mode)
	if mode == dag_types.TASK_MODE.READ then
		return "R"
	elseif mode == dag_types.TASK_MODE.WRITE then
		return "W"
	elseif mode == dag_types.TASK_MODE.READWRITE then
		return "RW"
	else
		return "?"
	end
end

-- Format a single DAG checklist for display (user-friendly version)
function DagChecklistFormatter:format_checklist(checklist, progress)
	if not checklist then
		return "No checklist data"
	end

	local output = string.format(
		"📋 **%s**\n*Created: %s*\n",
		checklist.goal or "Checklist",
		os.date("%m/%d %H:%M", checklist.created_at)
	)

	if #checklist.tasks == 0 then
		output = output .. "\n(No tasks)"
	else
		-- Show tasks in execution order if available, otherwise by index
		local display_order = checklist.execution_order and #checklist.execution_order > 0 and checklist.execution_order
			or {}

		-- If no execution order, fall back to index order
		if #display_order == 0 then
			for i = 1, #checklist.tasks do
				table.insert(display_order, i)
			end
		end

		for _, i in ipairs(display_order) do
			local task = checklist.tasks[i]
			if task then
				local status_icon = self:get_status_icon(task.status)
				local mode_icon = self:get_mode_icon(task.mode)
				local deps_info = self:format_dependencies(task, i, checklist)

				output = output .. string.format("\n%d. %s [%s] %s%s", i, status_icon, mode_icon, task.text, deps_info)
			end
		end
	end

	-- Show progress summary
	if progress then
		local status_parts = {}
		if progress.completed > 0 then
			table.insert(status_parts, string.format("✅ %d done", progress.completed))
		end
		if progress.in_progress > 0 then
			table.insert(status_parts, string.format("⏳ %d active", progress.in_progress))
		end
		if progress.blocked > 0 then
			table.insert(status_parts, string.format("⚠️ %d blocked", progress.blocked))
		end

		if #status_parts > 0 then
			output = output .. string.format("\n\n**Progress:** %s", table.concat(status_parts, " • "))
		end
	end

	return output
end

-- Format a DAG checklist summary for list view
function DagChecklistFormatter:format_checklist_summary(checklist, progress)
	local blocked_str = progress.blocked > 0 and string.format(", %d blocked", progress.blocked) or ""
	return string.format(
		"%d. %s (%d/%d%s) - %s [DAG]",
		checklist.id,
		checklist.goal or "No goal",
		progress.completed,
		progress.total,
		blocked_str,
		os.date("%m/%d %H:%M", checklist.created_at)
	)
end

-- Format multiple DAG checklists for list view
function DagChecklistFormatter:format_checklist_list(checklists_with_progress)
	if vim.tbl_isempty(checklists_with_progress) then
		return "📝 No checklists found. Create one to get started!"
	end

	-- Sort by creation time (newest first)
	local sorted_summaries = vim.deepcopy(checklists_with_progress)
	table.sort(sorted_summaries, function(a, b)
		return a.checklist.created_at > b.checklist.created_at
	end)

	local output = string.format("📝 **Active Checklists** (%d):\n\n", #sorted_summaries)

	for _, item in ipairs(sorted_summaries) do
		local progress = item.progress
		local status_emoji = "⏳"
		if progress.completed == progress.total then
			status_emoji = "✅"
		elseif progress.blocked > 0 then
			status_emoji = "⚠️"
		end

		output = output
			.. string.format(
				"%s **%s** - %d/%d tasks done\n",
				status_emoji,
				item.checklist.goal or "Checklist",
				progress.completed,
				progress.total
			)
	end

	return output
end

-- Format task completion result for DAG
function DagChecklistFormatter:format_task_completion(checklist, next_task_idx, next_task)
	if next_task then
		return string.format("✅ **Task completed!**\n\n⏭️ **Next up:** %s", next_task.text)
	else
		return "🎉 **Checklist completed!** All tasks are done."
	end
end

-- Factory function
function M.new()
	return DagChecklistFormatter.new()
end

return M
