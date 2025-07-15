-- dag/dag_formatter.lua
-- Handles DAG checklist output formatting and dependency visualization

local dag_types = require('codecompanion_tools.dag.dag_types')

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

  return string.format(" (deps: %s)", table.concat(dep_strs, ","))
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

-- Format a single DAG checklist for display
function DagChecklistFormatter:format_checklist(checklist, progress)
  if not checklist then
    return "No checklist data"
  end

  local output = string.format("DAG CHECKLIST %d: %s\nCreated: %s\n\nTasks:",
    checklist.id,
    checklist.goal or "No goal",
    os.date("%m/%d %H:%M", checklist.created_at)
  )

  if #checklist.tasks == 0 then
    output = output .. "\n  (none)"
  else
    -- Show tasks in execution order if available, otherwise by index
    local display_order = checklist.execution_order and #checklist.execution_order > 0
        and checklist.execution_order
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

        output = output .. string.format("\n%d. %s [%s] %s%s",
          i, status_icon, mode_icon, task.text, deps_info)
      end
    end
  end

  -- Show dependency graph
  if checklist.dependency_graph and not vim.tbl_isempty(checklist.dependency_graph) then
    output = output .. "\n\nDependency graph:"
    for task_idx, dependents in pairs(checklist.dependency_graph) do
      if #dependents > 0 then
        output = output .. string.format("\n  %d enables: %s",
          task_idx, table.concat(dependents, ","))
      end
    end
  end

  if checklist.log and #checklist.log > 0 then
    output = output .. "\n\nLog:"
    local sorted_log = vim.deepcopy(checklist.log)
    table.sort(sorted_log, function(a, b)
      return a.timestamp > b.timestamp
    end)

    for _, entry in ipairs(sorted_log) do
      local details = {}
      if entry.subject and entry.subject ~= "" then
        table.insert(details, entry.subject)
      end
      if entry.completed_task_ids and #entry.completed_task_ids > 0 then
        table.insert(details, "completed: " .. table.concat(entry.completed_task_ids, ","))
      end
      if entry.file_paths and #entry.file_paths > 0 then
        table.insert(details, "files: " .. table.concat(entry.file_paths, ","))
      end
      if entry.parallel_results and not vim.tbl_isempty(entry.parallel_results) then
        local results = {}
        for task_idx, result in pairs(entry.parallel_results) do
          local truncated = #result > 30 and (result:sub(1, 27) .. "...") or result
          table.insert(results, string.format("%d:%s", task_idx, truncated))
        end
        table.insert(details, "parallel: " .. table.concat(results, ";"))
      end

      local detail_str = #details > 0 and (" (" .. table.concat(details, "; ") .. ")") or ""
      output = output .. string.format("\n  %s %s%s",
        os.date("%m/%d %H:%M", entry.timestamp),
        entry.action,
        detail_str
      )
    end
  end

  if progress then
    output = output .. string.format("\n\nProgress: %d/%d complete",
      progress.completed, progress.total)
    if progress.in_progress > 0 then
      output = output .. string.format(", %d in progress", progress.in_progress)
    end
    if progress.blocked > 0 then
      output = output .. string.format(", %d blocked", progress.blocked)
    end
  end

  return output
end

-- Format a DAG checklist summary for list view
function DagChecklistFormatter:format_checklist_summary(checklist, progress)
  local blocked_str = progress.blocked > 0 and string.format(", %d blocked", progress.blocked) or ""
  return string.format("%d. %s (%d/%d%s) - %s [DAG]",
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
    return "No DAG checklists found. Use create tool to make one."
  end

  -- Sort by creation time (newest first)
  local sorted_summaries = vim.deepcopy(checklists_with_progress)
  table.sort(sorted_summaries, function(a, b)
    return a.checklist.created_at > b.checklist.created_at
  end)

  local output = string.format("DAG Checklists (%d):\n", #sorted_summaries)

  for _, item in ipairs(sorted_summaries) do
    output = output .. self:format_checklist_summary(item.checklist, item.progress) .. "\n"
  end

  return output
end

-- Format task completion result for DAG
function DagChecklistFormatter:format_task_completion(checklist, next_task_idx, next_task)
  if next_task then
    local deps_info = self:format_dependencies(next_task, next_task_idx, checklist)
    return string.format("Next: %d. %s%s", next_task_idx, next_task.text, deps_info)
  else
    return "DAG checklist complete."
  end
end

-- Factory function
function M.new()
  return DagChecklistFormatter.new()
end

return M
