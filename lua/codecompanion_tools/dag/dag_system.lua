-- dag/dag_system.lua  
-- Shared DAG system singleton to avoid code duplication

local dag_manager_module = require('codecompanion_tools.dag.dag_manager')
local dag_formatter_module = require('codecompanion_tools.dag.dag_formatter')
local dag_executor = require('codecompanion_tools.dag.dag_executor')
local storage_module = require('codecompanion_tools.dag.storage')

local M = {}

-- Singleton instance
local dag_system = nil

-- Create a new DAG system instance
---@return table
local function create_dag_system()
  local storage = storage_module.new()
  local manager = dag_manager_module.new(storage)
  local formatter = dag_formatter_module.new()

  return {
    storage = storage,
    manager = manager,
    formatter = formatter
  }
end

-- Get the shared DAG system instance (singleton pattern)
---@return table
function M.get_instance()
  if not dag_system then
    dag_system = create_dag_system()
  end
  return dag_system
end

-- Reset the singleton (useful for testing)
function M.reset()
  dag_system = nil
end

return M