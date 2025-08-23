-- Common utility functions
local M = {}

-- Get selected text
function M.get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok_start, pos_start = pcall(vim.fn.getpos, "'<")
  local ok_end, pos_end = pcall(vim.fn.getpos, "'>")

  -- Fall back to current line when no valid visual selection
  if not ok_start or not ok_end or pos_start[2] == 0 or pos_end[2] == 0 then
    local l = vim.fn.line(".")
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1] or ""
    return line, l, l
  end

  local sline, scol = pos_start[2], pos_start[3]
  local eline, ecol = pos_end[2], pos_end[3]
  if (eline < sline) or (eline == sline and ecol < scol) then
    -- Swap to ensure (sline,scol) comes first
    sline, eline = eline, sline
    scol, ecol = ecol, scol
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, sline - 1, eline, false)
  local vmode = vim.fn.visualmode() or ""

  if vmode == "V" then
    -- Line visual: return entire lines
    return table.concat(lines, "\n"), sline, eline
  elseif vmode == "\22" then -- Block visual (CTRL-V)
    local min_col = math.min(scol, ecol)
    local max_col = math.max(scol, ecol)
    for i, l in ipairs(lines) do
      -- sub's end is inclusive, so use max_col directly
      lines[i] = l:sub(min_col, max_col)
    end
    return table.concat(lines, "\n"), sline, eline
  else
    -- Character visual: trim first and last lines; note ecol should be included
    if #lines > 0 then
      lines[1] = lines[1]:sub(scol)
      if #lines == 1 then
        lines[1] = lines[1]:sub(1, ecol - scol + 1)
      else
        lines[#lines] = lines[#lines]:sub(1, ecol)
      end
    end
    return table.concat(lines, "\n"), sline, eline
  end
end

-- Strict mode: return nil if no valid visual selection (no fallback to current line)
function M.get_strict_visual_selection()
  local ok_start, ps = pcall(vim.fn.getpos, "'<")
  local ok_end, pe = pcall(vim.fn.getpos, "'>")
  if not ok_start or not ok_end then
    return nil
  end
  local sline, scol = ps[2], ps[3]
  local eline, ecol = pe[2], pe[3]
  if sline == 0 or eline == 0 then
    return nil
  end
  if (eline < sline) or (eline == sline and ecol < scol) then
    sline, eline = eline, sline
    scol, ecol = ecol, scol
  end
  if sline == eline and scol == ecol then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, sline - 1, eline, false)
  local vmode = vim.fn.visualmode() or ""

  if vmode == "V" then
    return table.concat(lines, "\n"), sline, eline
  elseif vmode == "\22" then
    local min_col = math.min(scol, ecol)
    local max_col = math.max(scol, ecol)
    for i, l in ipairs(lines) do
      lines[i] = l:sub(min_col, max_col)
    end
    return table.concat(lines, "\n"), sline, eline
  else
    if #lines > 0 then
      lines[1] = lines[1]:sub(scol)
      if #lines == 1 then
        lines[1] = lines[1]:sub(1, ecol - scol + 1)
      else
        lines[#lines] = lines[#lines]:sub(1, ecol)
      end
    end
    return table.concat(lines, "\n"), sline, eline
  end
end

-- Safe deep merge configuration
function M.merge_config(defaults, user)
  user = user or {}
  return vim.tbl_deep_extend("force", defaults, user)
end

-- Helper function to create user commands
function M.create_command(name, handler, opts)
  opts = opts or {}
  vim.api.nvim_create_user_command(name, handler, opts)
end

-- Helper function to notify users
function M.notify(msg, level, title)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, {
      title = title or "CodeCompanion Tools",
      timeout = 3000,
    })
  end)
end

-- Check if CodeCompanion is available
function M.check_codecompanion()
  local ok = pcall(require, "codecompanion")
  if not ok then
    M.notify("CodeCompanion is not installed or loaded", vim.log.levels.ERROR)
    return false
  end
  return true
end

return M
