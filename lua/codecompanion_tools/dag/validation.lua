-- dag/validation.lua
-- Validation utilities for DAG checklist operations

local M = {}

-- Validate create action parameters
---@param args table
---@return boolean, string?
function M.validate_create_params(args)
  if not args.goal or args.goal == "" then
    return false, "Goal is required"
  end
  
  if not args.tasks or #args.tasks == 0 then
    return false, "At least one task is required"
  end
  
  if not args.subject or args.subject == "" then
    return false, "Subject is required"
  end
  
  if not args.body then
    return false, "Body is required"
  end
  
  return true
end

-- Validate complete action parameters
---@param args table
---@return boolean, string?
function M.validate_complete_params(args)
  if not args.task_id then
    return false, "task_id is required"
  end
  
  if not args.subject or args.subject == "" then
    return false, "subject is required"
  end
  
  if not args.body then
    return false, "body is required"
  end
  
  return true
end

-- Validate task input data
---@param task_input any
---@param index number
---@return boolean, string?
function M.validate_task_input(task_input, index)
  if type(task_input) == "string" then
    if task_input == "" then
      return false, string.format("Task %d cannot be empty", index)
    end
    return true
  elseif type(task_input) == "table" then
    if not task_input.text or task_input.text == "" then
      return false, string.format("Task %d text is required", index)
    end
    
    -- Validate dependencies
    if task_input.dependencies then
      if type(task_input.dependencies) ~= "table" then
        return false, string.format("Task %d dependencies must be an array", index)
      end
      for _, dep in ipairs(task_input.dependencies) do
        if type(dep) ~= "number" or dep < 1 then
          return false, string.format("Task %d dependency must be a positive integer", index)
        end
      end
    end
    
    -- Validate mode
    if task_input.mode then
      local valid_modes = { "read", "write", "readwrite" }
      local mode_valid = false
      for _, valid_mode in ipairs(valid_modes) do
        if task_input.mode == valid_mode then
          mode_valid = true
          break
        end
      end
      if not mode_valid then
        return false, string.format("Task %d mode must be one of: read, write, readwrite", index)
      end
    end
    
    return true
  else
    return false, string.format("Task %d must be a string or table", index)
  end
end

-- Validate all tasks input
---@param tasks_input table
---@return boolean, string?
function M.validate_tasks_input(tasks_input)
  for i, task_input in ipairs(tasks_input) do
    local valid, err = M.validate_task_input(task_input, i)
    if not valid then
      return false, err
    end
  end
  return true
end

return M