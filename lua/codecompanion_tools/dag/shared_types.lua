-- dag/shared_types.lua
-- Minimal shared type definitions for standardized command responses

---@class StandardToolResponse
---@field status "success" | "error"
---@field data any  -- Actual data varies by tool, error message string on error

local M = {}

-- Tool response status constants
M.RESPONSE_STATUS = {
  SUCCESS = "success",
  ERROR = "error"
}

-- Create a standardized tool response
---@param status "success" | "error"
---@param data any
---@return StandardToolResponse
function M.create_response(status, data)
  return {
    status = status,
    data = data
  }
end

return M
