local M = {}

local config = {
  target = nil,
  buffer_name = "pi-tmux",
  mappings = true,
}

local resolved_target = nil

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "pi-tmux" })
end

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function system(cmd, input)
  local result = vim.system(cmd, { text = true, stdin = input }):wait()
  return result.code == 0, result.stdout or "", result.stderr or "", result.code
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function current_session()
  local ok, out = system({ "tmux", "display-message", "-p", "#{session_name}" })
  if ok then
    return trim(out)
  end
end

local function pane_for(target)
  if not target or target == "" then
    return nil
  end
  local ok, out = system({ "tmux", "display-message", "-p", "-t", target, "#{pane_id}" })
  if ok then
    local pane = trim(out)
    if pane ~= "" then
      return pane
    end
  end
end

local function discover_target()
  local session = current_session()
  local candidates = {}

  if session and session ~= "" then
    table.insert(candidates, session .. ":pi.0")
  end

  table.insert(candidates, ":pi.0")
  table.insert(candidates, ":pi")

  for _, candidate in ipairs(candidates) do
    if pane_for(candidate) then
      return candidate
    end
  end

  -- Pi's tmux window may not be named "pi". In this harness the pane title is
  -- usually "π - <repo>". Prefer a matching pane in the current session.
  local ok, out = system({ "tmux", "list-panes", "-s", "-F", "#{pane_id}\t#{pane_title}\t#{pane_current_command}" })
  if ok then
    for line in out:gmatch("[^\n]+") do
      local pane_id, title, command = line:match("^([^\t]+)\t([^\t]*)\t?(.*)$")
      title = title or ""
      command = command or ""
      if pane_id and (title:lower():find("^π") or title:lower():find("^pi") or command == "pi") then
        return pane_id
      end
    end
  end
end

local function wrap_context(text)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    file = "[No Name]"
  end

  return table.concat({
    "--- BEGIN NVIM CONTEXT ---",
    "File: " .. file,
    text,
    "--- END NVIM CONTEXT ---",
  }, "\n")
end

local function get_visual_selection()
  local mode = vim.fn.visualmode()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
  if #lines == 0 then
    return ""
  end

  if mode == "V" then
    return table.concat(lines, "\n")
  end

  if mode == "\022" then -- blockwise visual mode
    local left = math.min(start_col, end_col)
    local right = math.max(start_col, end_col)
    for i, line in ipairs(lines) do
      lines[i] = vim.fn.strpart(line, left - 1, right - left + 1)
    end
    return table.concat(lines, "\n")
  end

  if #lines == 1 then
    lines[1] = vim.fn.strpart(lines[1], start_col - 1, end_col - start_col + 1)
  else
    lines[1] = vim.fn.strpart(lines[1], start_col - 1)
    lines[#lines] = vim.fn.strpart(lines[#lines], 0, end_col)
  end

  return table.concat(lines, "\n")
end

function M.target()
  if resolved_target and pane_for(resolved_target) then
    return resolved_target
  end

  if config.target and config.target ~= "" then
    resolved_target = config.target
    return resolved_target
  end

  resolved_target = discover_target()
  return resolved_target
end

function M.validate_target()
  if not in_tmux() then
    notify("Neovim is not running inside tmux", vim.log.levels.ERROR)
    return nil
  end

  local target = M.target()
  if not target then
    notify("Could not find a tmux window/pane named 'pi'. Configure require('pi_tmux').setup({ target = '...' })", vim.log.levels.ERROR)
    return nil
  end

  local pane = pane_for(target)
  if not pane then
    notify("Tmux target not found: " .. target, vim.log.levels.ERROR)
    return nil
  end

  return target, pane
end

function M.send(text, opts)
  opts = opts or {}
  text = text or ""

  local target, pane = M.validate_target()
  if not target then
    return false
  end

  local payload = opts.raw and text or wrap_context(text)

  local ok, _, err = system({ "tmux", "load-buffer", "-b", config.buffer_name, "-" }, payload)
  if not ok then
    notify("Failed to load tmux buffer: " .. trim(err), vim.log.levels.ERROR)
    return false
  end

  ok, _, err = system({ "tmux", "paste-buffer", "-b", config.buffer_name, "-t", pane })
  if not ok then
    notify("Failed to paste into tmux target: " .. trim(err), vim.log.levels.ERROR)
    return false
  end

  ok, _, err = system({ "tmux", "send-keys", "-t", pane, "Enter" })
  if not ok then
    notify("Pasted text, but failed to press Enter: " .. trim(err), vim.log.levels.ERROR)
    return false
  end

  notify("Sent to Pi: " .. target)
  return true
end

function M.send_selection()
  local text = get_visual_selection()
  if text == "" then
    notify("No visual selection found", vim.log.levels.WARN)
    return false
  end
  return M.send(text)
end

function M.send_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return M.send(table.concat(lines, "\n"))
end

function M.prompt_send()
  vim.ui.input({ prompt = "Pi prompt: " }, function(input)
    if not input or input == "" then
      return
    end
    M.send(input, { raw = true })
  end)
end

function M.focus()
  local target, pane = M.validate_target()
  if not target then
    return false
  end

  local ok, window_id_or_err = system({ "tmux", "display-message", "-p", "-t", target, "#{window_id}" })
  if not ok then
    notify("Could not resolve target window", vim.log.levels.ERROR)
    return false
  end

  local window_id = trim(window_id_or_err)
  local _, current_window = system({ "tmux", "display-message", "-p", "#{window_id}" })
  current_window = trim(current_window)

  local err
  if window_id ~= "" and window_id ~= current_window then
    ok, _, err = system({ "tmux", "select-window", "-t", window_id })
    if not ok then
      notify("Failed to select Pi window: " .. trim(err), vim.log.levels.ERROR)
      return false
    end
  end

  ok, _, err = system({ "tmux", "select-pane", "-t", pane })
  if not ok then
    notify("Failed to select Pi pane: " .. trim(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

function M.toggle_or_focus()
  return M.focus()
end

local function create_commands()
  vim.api.nvim_create_user_command("PiSend", function(args)
    M.send(args.args, { raw = true })
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("PiSendSelection", function()
    M.send_selection()
  end, { range = true })

  vim.api.nvim_create_user_command("PiSendBuffer", function()
    M.send_buffer()
  end, {})

  vim.api.nvim_create_user_command("PiPrompt", function()
    M.prompt_send()
  end, {})

  vim.api.nvim_create_user_command("PiFocus", function()
    M.focus()
  end, {})

  vim.api.nvim_create_user_command("PiTarget", function(args)
    config.target = args.args
    resolved_target = nil
    if M.validate_target() then
      notify("Pi target set to: " .. args.args)
    end
  end, { nargs = 1, complete = "shellcmd" })
end

local function create_mappings()
  local map = vim.keymap.set
  map("n", "<leader>pp", M.prompt_send, { desc = "Pi: prompt and send" })
  map("v", "<leader>ps", function()
    vim.cmd.normal({ args = { "gv" }, bang = true })
    M.send_selection()
  end, { desc = "Pi: send selection" })
  map("n", "<leader>pb", M.send_buffer, { desc = "Pi: send buffer" })
  map("n", "<leader>pf", M.focus, { desc = "Pi: focus tmux target" })
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  resolved_target = nil
  create_commands()
  if config.mappings ~= false then
    create_mappings()
  end
end

return M
