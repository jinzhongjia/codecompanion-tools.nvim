local M = {}

---@class CodeCompanionToolsConfig
 ---@field translator table|nil 翻译模块配置
 ---@field modules table<string, boolean|table> 模块启用状态和配置
 
 -- 可用的模块列表
 local available_modules = {
   translator = "codecompanion-tools.translator",
   -- 未来可以添加更多模块，例如:
   -- formatter = "codecompanion-tools.formatter",
   -- refactor = "codecompanion-tools.refactor",
   -- docgen = "codecompanion-tools.docgen",
 }

---Setup entry for codecompanion-tools
---@param opts CodeCompanionToolsConfig
function M.setup(opts)
  opts = opts or {}
   
   -- 检查 CodeCompanion 是否可用
   local utils = require("codecompanion-tools.common.utils")
   if not utils.check_codecompanion() then
     return
  end
  
  -- 加载各个模块
  for module_name, module_path in pairs(available_modules) do
    local module_config = opts[module_name]
    
    -- 如果模块配置不是 false，则加载模块
    if module_config ~= false then
      local ok, module = pcall(require, module_path)
      if ok then
        -- 如果配置是 true 或 nil，使用默认配置
        -- 如果配置是 table，使用用户配置
        local config = (type(module_config) == "table") and module_config or {}
        module.setup(config)
        
        -- 记录已加载的模块
        M[module_name] = module
      else
        vim.notify(
          string.format("Failed to load module '%s': %s", module_name, module),
          vim.log.levels.WARN,
          { title = "CodeCompanion Tools" }
        )
      end
    end
  end
end

-- 获取已加载的模块列表
function M.loaded_modules()
  local modules = {}
  for name, _ in pairs(available_modules) do
    if M[name] then
      table.insert(modules, name)
    end
  end
  return modules
end

-- 健康检查
function M.health()
  local health = vim.health or require("health")
  
  health.start("CodeCompanion Tools")
  
  -- 检查 CodeCompanion
  local cc_ok = pcall(require, "codecompanion")
  if cc_ok then
    health.ok("CodeCompanion is installed")
  else
    health.error("CodeCompanion is not installed")
    return
  end
  
  -- 检查已加载的模块
  local loaded = M.loaded_modules()
  if #loaded > 0 then
    health.ok(string.format("Loaded modules: %s", table.concat(loaded, ", ")))
  else
    health.warn("No modules loaded")
  end
end

return M
