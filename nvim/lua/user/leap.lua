local api = vim.api
-- Note: The functions used here will be upstreamed eventually.
local ts_utils = require('nvim-treesitter.ts_utils')

local module = {}

local function get_nodes()
  local wininfo = vim.fn.getwininfo(api.nvim_get_current_win())[1]
  -- Get current TS node.
  local cur_node = ts_utils.get_node_at_cursor(0)
  if not cur_node then return end
  -- Get parent nodes recursively.
  local nodes = { cur_node }
  local parent = cur_node:parent()
  while parent do
    table.insert(nodes, parent)
    parent = parent:parent()
  end
  -- Create Leap targets from TS nodes.
  local targets = {}
  for _, node in ipairs(nodes) do
    startline, startcol, _, _ = node:range()  -- (0,0)
    if startline + 1 >= wininfo.topline then
      local target = { node = node, pos = { startline + 1, startcol + 1 } }
      table.insert(targets, target)
    end
  end
  if #targets >= 1 then return targets end
end

local function select_range(target)
  local mode = api.nvim_get_mode().mode
  if not mode:match('n?o') then
    -- Force going back to Normal (implies mode = v | V | ).
    vim.cmd('normal! ' .. mode)
  end
  local vmode = "charwise"
  if mode:match('V') then
    vmode = 'linewise'
  elseif mode:match('') then
    vmode = 'blockwise'
  end
  ts_utils.update_selection(0, target.node, vmode)
end

local function jump(target)
  startline, startcol, _, _ = target.node:range()          -- (0,0)
  api.nvim_win_set_cursor(0, { startline + 1, startcol })  -- (1,0)
end

-- Map this function to your preferred key.
function module.leap_ts_nodes()
  local targets = get_nodes()
  local action = api.nvim_get_mode().mode == 'n' and jump or select_range
  require('leap').leap { targets = targets, action = action, backward = true }
end

local function get_targets(winid)
  local wininfo =  vim.fn.getwininfo(winid)[1]
  local cur_line = vim.fn.line('.')
  -- Get targets.
  local targets = {}
  local lnum = wininfo.topline
  while lnum <= wininfo.botline do
    -- Skip folded ranges.
    local fold_end = vim.fn.foldclosedend(lnum)
    if fold_end ~= -1 then 
      lnum = fold_end + 1
    else
      if lnum ~= cur_line then
        table.insert(targets, { pos = { lnum, 1 } })
      end
      lnum = lnum + 1
    end
  end
  -- Sort them by vertical screen distance from cursor.
  local cur_screen_row = vim.fn.screenpos(winid, cur_line, 1)['row']
  local function screen_rows_from_cursor(t)
    local t_screen_row = vim.fn.screenpos(winid, t.pos[1], t.pos[2])['row']
    return math.abs(cur_screen_row - t_screen_row)
  end
  table.sort(targets, function (t1, t2)
    return screen_rows_from_cursor(t1) < screen_rows_from_cursor(t2)
  end)
  if #targets >= 1 then return targets end
end

-- Map this function to your preferred key.
function module.leap_lines()
  winid = vim.api.nvim_get_current_win()
  require('leap').leap { targets = get_targets(winid), target_windows = { winid }, }
end

return module
