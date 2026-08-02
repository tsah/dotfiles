-- Neovim bridge for existing Waystation agents and the opencode.nvim provider.
-- Agent messages use the native Waystation API. Tmux is limited to metadata,
-- focus, and spawning an OpenCode pane for the provider startup hook.

local M = {}

local function notify(message, level)
    vim.schedule(function()
        vim.notify(tostring(message), level or vim.log.levels.INFO, { title = "agents" })
    end)
end

local function run(command, args, input)
    local cmd = { vim.fn.expand(command) }
    vim.list_extend(cmd, args)
    return vim.system(cmd, { text = true, stdin = input }):wait()
end

local function git_root(path)
    local result = vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait()
    return result.code == 0 and vim.trim(result.stdout) or vim.fn.fnamemodify(path, ":p")
end

local function project_anchor()
    local name = vim.api.nvim_buf_get_name(0)
    local directory = name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
    return git_root(directory)
end

local function list_agents()
    local result = run("~/dotfiles/bin/waystation", { "agent", "list", "--cwd", project_anchor() })
    if result.code ~= 0 then
        return nil, vim.trim(result.stderr)
    end
    local ok, rows = pcall(vim.json.decode, result.stdout)
    if not ok or type(rows) ~= "table" then
        return nil, "Waystation returned invalid agent metadata"
    end
    return rows
end

local function native_targets()
    local rows, err = list_agents()
    if not rows then
        return nil, err
    end
    local targets = {}
    for _, row in ipairs(rows) do
        if row.capabilities and row.capabilities.send == "unix-socket" then
            table.insert(targets, row)
        end
    end
    table.sort(targets, function(left, right)
        if left.harness ~= right.harness then
            return left.harness == "pi"
        end
        return (left.name or left.id) < (right.name or right.id)
    end)
    return targets, nil, rows
end

local function capture_selection()
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then
        return nil
    end
    local first, last
    if vim.fn.mode():match("^[vV\22]") then
        first, last = vim.fn.line("v"), vim.fn.line(".")
    else
        first = vim.fn.line(".")
        last = first
    end
    if first > last then
        first, last = last, first
    end
    return { path = vim.fn.fnamemodify(name, ":p"), first = first, last = last }
end

local function compose(selection, message)
    if not selection then
        return message
    end
    return string.format("%s:%d-%d %s", selection.path, selection.first, selection.last, message)
end

local function send_native(agent, text)
    local result = run("~/dotfiles/bin/waystation", { "agent", "send", agent.id }, text)
    if result.code ~= 0 then
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
        return false
    end
    notify("Sent native message to " .. (agent.name or agent.id))
    return true
end

local function choose_target(callback)
    local targets, err, all = native_targets()
    if not targets then
        notify(err, vim.log.levels.ERROR)
        return
    end
    if #targets == 0 then
        local harnesses = {}
        for _, row in ipairs(all or {}) do
            harnesses[row.harness or "unknown"] = true
        end
        local names = vim.tbl_keys(harnesses)
        table.sort(names)
        local suffix = #names > 0 and " (found: " .. table.concat(names, ", ") .. ")" or ""
        notify("No current-worktree agent advertises native send" .. suffix, vim.log.levels.ERROR)
        return
    end
    if #targets == 1 then
        callback(targets[1])
        return
    end
    vim.ui.select(targets, {
        prompt = "Native Waystation agent",
        format_item = function(row)
            return string.format("%s · %s · %s", row.harness, row.name, row.id)
        end,
    }, function(row)
        if row then callback(row) end
    end)
end

function M.ask()
    local selection = capture_selection()
    if vim.fn.mode():match("^[vV\22]") then
        vim.cmd("normal! \27")
    end
    vim.ui.input({ prompt = "Ask agent: " }, function(input)
        local message = input and vim.trim(input) or ""
        if message == "" then return end
        choose_target(function(agent)
            send_native(agent, compose(selection, message))
        end)
    end)
end

M.ask_this = M.ask

local function generated_id(pane)
    local seed = table.concat({ pane, tostring(vim.uv.hrtime()), tostring(math.random()) }, ":")
    return "ws-" .. vim.fn.sha256(seed):sub(1, 36)
end

-- opencode.nvim owns its HTTP communication. This hook only ensures a visible
-- OpenCode process exists; Waystation intentionally exposes no OpenCode send or
-- result capability until that HTTP mutation contract is verified.
function M.ensure_sync()
    local rows = list_agents()
    if rows then
        for _, row in ipairs(rows) do
            if row.harness == "opencode" then return end
        end
    end
    if not vim.env.TMUX then return end
    local pane_result = vim.system({ "tmux", "display-message", "-p", "#{pane_id}" }, { text = true }):wait()
    if pane_result.code ~= 0 then return end
    local pane = vim.trim(pane_result.stdout)
    local spawn = vim.system({
        "tmux", "split-window", "-h", "-t", pane, "-P", "-F", "#{pane_id}",
        "-c", project_anchor(), "oc", "--new",
    }, { text = true }):wait()
    if spawn.code ~= 0 then
        notify(vim.trim(spawn.stderr), vim.log.levels.ERROR)
        return
    end
    local spawned_pane = vim.trim(spawn.stdout)
    vim.system({ "tmux", "set-option", "-p", "-t", spawned_pane, "@waystation_agent_id", generated_id(spawned_pane) }):wait()
    vim.system({ "tmux", "set-option", "-p", "-t", spawned_pane, "@dotfiles_agent", "opencode" }):wait()
end

M.ensure = M.ensure_sync
M._find_target = function()
    local targets = native_targets()
    return targets and targets[1] or nil
end
M._origin = project_anchor
M._deliver = send_native
M._capture_selection = capture_selection

return M
