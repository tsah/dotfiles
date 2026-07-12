local M = {}
local selected_pane = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agents" })
end
local function workflow(args, input)
  local cmd = { vim.fn.expand("~/dotfiles/bin/dotfiles-workflow") }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true, stdin = input }):wait()
end
local function agents()
  local result = workflow({ "agents", "--cwd", vim.fn.getcwd() })
  if result.code ~= 0 then notify(result.stderr, vim.log.levels.ERROR); return {} end
  local ok, rows = pcall(vim.json.decode, result.stdout)
  return ok and rows or {}
end
local function choose(callback)
  local rows = agents()
  if selected_pane then
    for _, row in ipairs(rows) do if row.pane == selected_pane then callback(row); return end end
    selected_pane = nil
  end
  if #rows == 1 then callback(rows[1]); return end
  vim.ui.select(rows, { prompt = "Current-worktree agent", format_item = function(row)
    return string.format("%s · %s · %s", row.harness, row.name, row.pane)
  end }, function(row) if row then selected_pane = row.pane; callback(row) end end)
end
local function reference(line1, line2)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then path = "[No Name]" end
  return string.format("%s:%d-%d", path, line1, line2)
end
local function send(text, append)
  choose(function(row)
    local args = { "send", "--pane", row.pane }
    if append then table.insert(args, "--no-submit") end
    local result = workflow(args, text)
    if result.code ~= 0 then notify(result.stderr, vim.log.levels.ERROR) else notify("Sent via acknowledged tmux paste bridge to " .. row.name) end
  end)
end
local function range(args)
  local first = args.range > 0 and args.line1 or vim.fn.line(".")
  local last = args.range > 0 and args.line2 or first
  return first, last
end
local function contents(first, last)
  return table.concat(vim.api.nvim_buf_get_lines(0, first - 1, last, false), "\n")
end
local function with_saved_choice(callback)
  if not vim.bo.modified then callback(false); return end
  vim.ui.select({ "save", "send contents", "cancel" }, { prompt = "Buffer has unsaved changes" }, function(choice)
    if choice == "save" then vim.cmd.write(); callback(false)
    elseif choice == "send contents" then callback(true) end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("AgentChoose", function() selected_pane = nil; choose(function(row) selected_pane = row.pane; notify("Agent: " .. row.name) end) end, {})
  vim.api.nvim_create_user_command("AgentSendReference", function(args) local a,b=range(args); send(reference(a,b), false) end, { range = true })
  vim.api.nvim_create_user_command("AgentSendContents", function(args) local a,b=range(args); with_saved_choice(function(all) send(contents(all and 1 or a, all and vim.api.nvim_buf_line_count(0) or b), false) end) end, { range = true })
  vim.api.nvim_create_user_command("AgentAppendContext", function(args) local a,b=range(args); send(reference(a,b) .. "\n" .. contents(a,b), true) end, { range = true })
  vim.api.nvim_create_user_command("AgentFocus", function() choose(function(row) vim.system({ "tmux", "select-window", "-t", row.window }):wait() end) end, {})
  vim.api.nvim_create_user_command("AgentSpawn", function(args) vim.ui.select({ "pi", "claude", "opencode" }, { prompt = "Harness" }, function(h) if h then workflow({ "agent", "--harness", h, args.args ~= "" and args.args or "Ready for Neovim context." }) end end) end, { nargs = "*" })
end
return M
