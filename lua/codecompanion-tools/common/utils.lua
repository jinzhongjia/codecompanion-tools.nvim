-- 通用工具函数
local M = {}

-- 获取选中的文本
function M.get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos_start = vim.fn.getpos("'<")
  local pos_end = vim.fn.getpos("'>")

  -- 无有效可视选区时退回当前行
  if pos_start[2] == 0 or pos_end[2] == 0 then
    local l = vim.fn.line('.')
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1] or ''
    return line, l, l
  end

  local sline, scol = pos_start[2], pos_start[3]
  local eline, ecol = pos_end[2], pos_end[3]
  if (eline < sline) or (eline == sline and ecol < scol) then
    -- 交换，保证 (sline,scol) 在前
    sline, eline = eline, sline
    scol, ecol = ecol, scol
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, sline - 1, eline, false)
  local vmode = vim.fn.visualmode() or ''

  if vmode == 'V' then
    -- 行可视：整行直接返回
    return table.concat(lines, '\n'), sline, eline
  elseif vmode == '\22' then -- 块可视 (CTRL-V)
    local min_col = math.min(scol, ecol)
    local max_col = math.max(scol, ecol)
    for i, l in ipairs(lines) do
      -- sub 的结束是包含的，因此直接 max_col
      lines[i] = l:sub(min_col, max_col)
    end
    return table.concat(lines, '\n'), sline, eline
  else
    -- 字符可视：裁剪首尾行列；注意 ecol 需包含
    if #lines > 0 then
      lines[1] = lines[1]:sub(scol)
      if #lines == 1 then
        lines[1] = lines[1]:sub(1, ecol - scol + 1)
      else
        lines[#lines] = lines[#lines]:sub(1, ecol)
      end
    end
    return table.concat(lines, '\n'), sline, eline
  end
end

-- 严格模式：若没有有效可视选区，返回 nil（不回退到当前行）
function M.get_strict_visual_selection()
  local ok_start = pcall(vim.fn.getpos, "'<")
  local ok_end = pcall(vim.fn.getpos, "'>")
  if not ok_start or not ok_end then return nil end
  local ps = vim.fn.getpos("'<")
  local pe = vim.fn.getpos("'>")
  local sline, scol = ps[2], ps[3]
  local eline, ecol = pe[2], pe[3]
  if sline == 0 or eline == 0 then return nil end
  if (eline < sline) or (eline == sline and ecol < scol) then
    sline, eline = eline, sline
    scol, ecol = ecol, scol
  end
  if sline == eline and scol == ecol then return nil end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, sline - 1, eline, false)
  local vmode = vim.fn.visualmode() or ''

  if vmode == 'V' then
    return table.concat(lines, '\n'), sline, eline
  elseif vmode == '\22' then
    local min_col = math.min(scol, ecol)
    local max_col = math.max(scol, ecol)
    for i, l in ipairs(lines) do
      lines[i] = l:sub(min_col, max_col)
    end
    return table.concat(lines, '\n'), sline, eline
  else
    if #lines > 0 then
      lines[1] = lines[1]:sub(scol)
      if #lines == 1 then
        lines[1] = lines[1]:sub(1, ecol - scol + 1)
      else
        lines[#lines] = lines[#lines]:sub(1, ecol)
      end
    end
    return table.concat(lines, '\n'), sline, eline
  end
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