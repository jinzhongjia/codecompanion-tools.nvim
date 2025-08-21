-- 通用工具函数
local M = {}

-- 获取选中的文本
function M.get_visual_selection()
  local mode = vim.fn.mode()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line
  if mode == 'v' or mode == 'V' then
    start_line = vim.fn.getpos("'<")[2]
    end_line = vim.fn.getpos("'>")[2]
  else
    start_line = vim.fn.line("'<")
    end_line = vim.fn.line("'>")
    if start_line == 0 or end_line == 0 then
      start_line = vim.fn.line('.')
      end_line = start_line
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  return table.concat(lines, '\n'), start_line, end_line
end

-- 严格模式：若没有有效可视选区，返回 nil（不回退到当前行）
function M.get_strict_visual_selection()
  local ok_start = pcall(vim.fn.getpos, "'<")
  local ok_end = pcall(vim.fn.getpos, "'>")
  if not ok_start or not ok_end then return nil end
  local sline = vim.fn.getpos("'<")[2]
  local eline = vim.fn.getpos("'>")[2]
  if sline == 0 or eline == 0 or sline > eline then return nil end
  if sline == eline then
    local start_col = vim.fn.getpos("'<")[3]
    local end_col = vim.fn.getpos("'>")[3]
    if start_col == end_col then return nil end
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, sline - 1, eline, false)
  return table.concat(lines, '\n'), sline, eline
end

-- 安全的深度合并配置
function M.merge_config(defaults, user)
  user = user or {}
  return vim.tbl_deep_extend("force", defaults, user)
end

-- 创建用户命令的辅助函数
function M.create_command(name, handler, opts)
  opts = opts or {}
  vim.api.nvim_create_user_command(name, handler, opts)
end

-- 通知用户的辅助函数
function M.notify(msg, level, title)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, {
      title = title or "CodeCompanion Tools",
      timeout = 3000
    })
  end)
end

-- 检查 CodeCompanion 是否可用
function M.check_codecompanion()
  local ok = pcall(require, "codecompanion")
  if not ok then
    M.notify("CodeCompanion is not installed or loaded", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M