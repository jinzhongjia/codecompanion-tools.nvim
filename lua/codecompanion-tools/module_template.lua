-- 这是一个模块模板，新模块可以参考此结构
-- 将此文件复制到新模块目录并修改

local M = {}

-- 模块配置
local config = {
  -- 默认配置
}

-- 模块核心功能
local function core_function()
  -- 实现核心功能
end

-- 设置函数
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  
  -- 创建命令
  vim.api.nvim_create_user_command("CodeCompanionYourModule", function(cmd)
    -- 命令处理逻辑
  end, {
    nargs = "*",
    desc = "Your module description"
  })
end

return M