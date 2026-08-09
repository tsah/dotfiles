local M = {}
local selected_clanker = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "clankers" })
end
local function clankers(args, input)
  local cmd = { vim.fn.expand("~/dotfiles/bin/clankers") }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true, stdin = input }):wait()
end
local function list_clankers()
  local result = clankers({ "list", "--cwd", vim.fn.getcwd() })
  if result.code ~= 0 then notify(vim.trim(result.stderr), vim.log.levels.ERROR); return {} end
  local ok, rows = pcall(vim.json.decode, result.stdout)
  return ok and rows or {}
end
local function choose(callback)
  local rows = list_clankers()
  if selected_clanker then
    for _, row in ipairs(rows) do if row.id == selected_clanker then callback(row); return end end
    selected_clanker = nil
  end
  if #rows == 0 then notify("No clankers found for the current workshop", vim.log.levels.WARN); return end
  if #rows == 1 then callback(rows[1]); return end
  vim.ui.select(rows, { prompt = "Current-workshop clanker", format_item = function(row)
    return string.format("%s · %s · %s", row.harness, row.name, row.id)
  end }, function(row) if row then selected_clanker = row.id; callback(row) end end)
end
local function reference(line1, line2)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then path = "[No Name]" end
  return string.format("%s:%d-%d", path, line1, line2)
end
local function send(text, follow_up)
  choose(function(row)
    local args = { "send", row.id }
    if follow_up then vim.list_extend(args, { "--delivery", "follow-up" }) end
    local result = clankers(args, text)
    if result.code ~= 0 then notify(vim.trim(result.stderr), vim.log.levels.ERROR)
    else notify((follow_up and "Sent native follow-up to " or "Sent native message to ") .. row.name) end
  end)
end
local function range(args)
  local first = args.range > 0 and args.line1 or vim.fn.line(".")
  return first, args.range > 0 and args.line2 or first
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

local commands = {
  Choose = function() selected_clanker = nil; choose(function(row) selected_clanker = row.id; notify("Clanker: " .. row.name) end) end,
  SendReference = function(args) local a,b=range(args); send(reference(a,b), false) end,
  SendContents = function(args) local a,b=range(args); with_saved_choice(function(all) send(contents(all and 1 or a, all and vim.api.nvim_buf_line_count(0) or b), false) end) end,
  AppendContext = function(args) local a,b=range(args); send(reference(a,b) .. "\n" .. contents(a,b), true) end,
  Focus = function() choose(function(row) vim.system({ "tmux", "select-window", "-t", row.window }):wait() end) end,
  Spawn = function(args) vim.ui.select({ "pi", "claude", "opencode", "codex" }, { prompt = "Harness" }, function(h)
    if h then clankers({ "spawn", "--workshop", vim.fn.getcwd(), "--name", h, "--harness", h, "--prompt", args.args ~= "" and args.args or "Ready for Neovim context." }) end
  end)
  end,
}

function M.setup()
  for suffix, callback in pairs(commands) do
    local options = {}
    if suffix == "SendReference" or suffix == "SendContents" or suffix == "AppendContext" then options = { range = true } end
    if suffix == "Spawn" then options = { nargs = "*" } end
    vim.api.nvim_create_user_command("Clanker" .. suffix, callback, options)
  end
end
return M
