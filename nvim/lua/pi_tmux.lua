local M = {}
local selected_agent = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agents" })
end
local function run(command, args, input)
  local cmd = { vim.fn.expand(command) }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true, stdin = input }):wait()
end
local function waystation(args, input)
  return run("~/dotfiles/bin/waystation", args, input)
end
local function workflow(args, input)
  return run("~/dotfiles/bin/dotfiles-workflow", args, input)
end
local function agents()
  local result = waystation({ "agent", "list", "--cwd", vim.fn.getcwd() })
  if result.code ~= 0 then notify(result.stderr, vim.log.levels.ERROR); return {} end
  local ok, rows = pcall(vim.json.decode, result.stdout)
  return ok and rows or {}
end
local function choose(callback)
  local rows = agents()
  if selected_agent then
    for _, row in ipairs(rows) do if row.id == selected_agent then callback(row); return end end
    selected_agent = nil
  end
  if #rows == 0 then notify("No agents found for the current worktree", vim.log.levels.WARN); return end
  if #rows == 1 then callback(rows[1]); return end
  vim.ui.select(rows, { prompt = "Current-worktree agent", format_item = function(row)
    return string.format("%s · %s · %s", row.harness, row.name, row.id)
  end }, function(row) if row then selected_agent = row.id; callback(row) end end)
end
local function reference(line1, line2)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then path = "[No Name]" end
  return string.format("%s:%d-%d", path, line1, line2)
end
local function send(text, follow_up)
  choose(function(row)
    local args = { "agent", "send", row.id }
    if follow_up then vim.list_extend(args, { "--delivery", "follow-up" }) end
    local result = waystation(args, text)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr), vim.log.levels.ERROR)
    else
      notify((follow_up and "Sent native follow-up to " or "Sent native message to ") .. row.name)
    end
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
  vim.api.nvim_create_user_command("AgentChoose", function() selected_agent = nil; choose(function(row) selected_agent = row.id; notify("Agent: " .. row.name) end) end, {})
  vim.api.nvim_create_user_command("AgentSendReference", function(args) local a,b=range(args); send(reference(a,b), false) end, { range = true })
  vim.api.nvim_create_user_command("AgentSendContents", function(args) local a,b=range(args); with_saved_choice(function(all) send(contents(all and 1 or a, all and vim.api.nvim_buf_line_count(0) or b), false) end) end, { range = true })
  vim.api.nvim_create_user_command("AgentAppendContext", function(args) local a,b=range(args); send(reference(a,b) .. "\n" .. contents(a,b), true) end, { range = true })
  vim.api.nvim_create_user_command("AgentFocus", function() choose(function(row) vim.system({ "tmux", "select-window", "-t", row.window }):wait() end) end, {})
  vim.api.nvim_create_user_command("AgentSpawn", function(args) vim.ui.select({ "pi", "claude", "opencode" }, { prompt = "Harness" }, function(h) if h then workflow({ "agent", "--harness", h, args.args ~= "" and args.args or "Ready for Neovim context." }) end end) end, { nargs = "*" })
end
return M
