-- dag/dag_types.lua
-- Type definitions for DAG checklist system

---@class DagChecklistTask
---@field text string
---@field status "pending"|"in_progress"|"completed"|"blocked"
---@field dependencies integer[] -- Array of task indices that must complete first
---@field mode "read"|"write"|"readwrite" -- Access mode for safety during parallel execution
---@field created_at integer
---@field completed_at? integer

---@class DagChecklistLogEntry
---@field action string
---@field subject string
---@field body string
---@field timestamp integer
---@field file_paths? string[]
---@field completed_task_ids? integer[]
---@field started_task_id? integer
---@field parallel_results? table<integer, string> -- Results from parallel task execution

---@class DagChecklist
---@field id integer
---@field goal string
---@field created_at integer
---@field tasks DagChecklistTask[]
---@field log DagChecklistLogEntry[]
---@field dependency_graph table<integer, integer[]> -- task_id -> dependent_task_ids
---@field execution_order integer[] -- Topologically sorted order for execution

---@class DagChecklistProgress
---@field total integer
---@field completed integer
---@field pending integer
---@field in_progress integer
---@field blocked integer

local M = {}

-- Task status constants (extends base types)
M.TASK_STATUS = {
  PENDING = "pending",
  IN_PROGRESS = "in_progress",
  COMPLETED = "completed",
  BLOCKED = "blocked" -- New status for tasks waiting on dependencies
}

-- Log action constants (extends base types)
M.LOG_ACTIONS = {
  CREATE = "create",
  COMPLETE_TASK = "complete_task",
  UPDATE = "update",
  PARALLEL_EXECUTION = "parallel_execution" -- New action for parallel task execution
}

-- Task access mode constants for safety
M.TASK_MODE = {
  READ = "read",          -- Safe for parallel execution - read-only operations
  WRITE = "write",        -- Requires context - modifies files/state
  READWRITE = "readwrite" -- Requires context - both reads and writes
}

-- Dependency resolution constants
M.DEPENDENCY_STATUS = {
  SATISFIED = "satisfied",
  UNSATISFIED = "unsatisfied",
  CIRCULAR = "circular"
}

return M
