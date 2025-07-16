-- dag/dag_system.lua
-- DAG System Singleton Manager
--
-- This module provides a centralized singleton instance of the DAG (Directed Acyclic Graph)
-- system to ensure consistent state management across the entire application.
--
-- The DAG system is used for managing complex workflows with dependencies, such as:
-- - Checklist items with prerequisites
-- - Task execution with dependency resolution
-- - Workflow orchestration
--
-- By using a singleton pattern, we ensure that all components of the system
-- share the same DAG state, preventing inconsistencies and duplication.

local dag_manager_module = require("codecompanion_tools.dag.dag_manager")
local dag_formatter_module = require("codecompanion_tools.dag.dag_formatter")
local dag_executor = require("codecompanion_tools.dag.dag_executor")
local storage_module = require("codecompanion_tools.dag.storage")

local M = {}

-- Singleton instance storage
-- This holds the single shared instance of the DAG system
local dag_system = nil

-- Create a new DAG system instance
-- This function initializes all the components of the DAG system:
-- - Storage: Manages DAG data persistence
-- - Manager: Handles DAG operations and validation
-- - Formatter: Provides output formatting for DAG data
--
---@return table The complete DAG system instance with all components
local function create_dag_system()
	-- Initialize the core components of the DAG system
	local storage = storage_module.new() -- Data persistence layer
	local manager = dag_manager_module.new(storage) -- Core DAG operations
	local formatter = dag_formatter_module.new() -- Output formatting

	return {
		storage = storage, -- Access to data storage operations
		manager = manager, -- Access to DAG management functions
		formatter = formatter, -- Access to formatting utilities
	}
end

-- Get the shared DAG system instance (singleton pattern)
-- This function ensures that all parts of the application use the same
-- DAG system instance. If no instance exists, it creates one.
--
---@return table The shared DAG system instance
function M.get_instance()
	-- Create the singleton instance if it doesn't exist
	if not dag_system then
		dag_system = create_dag_system()
	end
	return dag_system
end

-- Reset the singleton instance
-- This function clears the singleton instance, forcing a new instance
-- to be created on the next get_instance() call.
-- Primarily useful for testing and cleanup scenarios.
function M.reset()
	-- Clear the singleton instance
	dag_system = nil
end

return M
