-- dag/dag_executor.lua
-- Handles parallel execution of independent DAG tasks

local M = {}

-- Execute multiple tasks in parallel using CodeCompanion
function M.execute_tasks_parallel(tasks, parent_chat, callback)
  local results = {}
  local completed_count = 0
  local total_count = #tasks

  if total_count == 0 then
    callback({})
    return
  end

  -- Execute each task in parallel
  for _, task in ipairs(tasks) do
    local task_idx = task.index
    local task_text = task.text

    -- Create a simple execution context
    vim.schedule(function()
      -- For now, just return a placeholder result
      -- In a real implementation, this would execute the task
      local result = string.format("Task %d completed: %s", task_idx, task_text)
      
      results[task_idx] = result
      completed_count = completed_count + 1
      
      -- Check if all tasks are completed
      if completed_count == total_count then
        callback(results)
      end
    end)
  end
end

return M
