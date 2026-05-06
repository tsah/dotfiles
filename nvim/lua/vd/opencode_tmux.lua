local M = {}

local function tmux(args)
    local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
    if result.code ~= 0 then
        error((result.stderr ~= "" and result.stderr or "tmux command failed"), 0)
    end
    return vim.trim(result.stdout)
end

local function current_location()
    local output = tmux({ "display-message", "-t", vim.env.TMUX_PANE, "-p", "#{window_index}\t#{pane_index}" })
    local window_index, pane_index = output:match("^(%d+)\t(%d+)$")
    return tonumber(window_index), tonumber(pane_index)
end

local function tmux_session_name()
    return tmux({ "display-message", "-t", vim.env.TMUX_PANE, "-p", "#{session_name}" })
end

local function list_opencode_panes(session_name, cwd)
    local output = tmux({
        "list-panes",
        "-a",
        "-F",
        "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}",
    })

    local panes = {}
    for line in output:gmatch("[^\r\n]+") do
        local pane_session_name, window_index, pane_index, pid, command, path = line:match("^([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]*)\t(.*)$")
        if pane_session_name == session_name and command == "opencode" and path == cwd then
            table.insert(panes, { window_index = tonumber(window_index), pane_index = tonumber(pane_index), pid = pid })
        end
    end
    return panes
end

local function pane_port(pane)
    local result = vim.system({ "pgrep", "-a", "-P", pane.pid }, { text = true }):wait()
    if result.code ~= 0 then
        return nil
    end

    for line in result.stdout:gmatch("[^\r\n]+") do
        local port = line:match("opencode.*%-%-port%s+(%d+)")
        if port then
            return tonumber(port)
        end
    end
    return nil
end

local function compare_panes(current_window_index, current_pane_index)
    return function(left, right)
        local left_window_distance = math.abs(left.window_index - current_window_index)
        local right_window_distance = math.abs(right.window_index - current_window_index)
        if left_window_distance ~= right_window_distance then
            return left_window_distance < right_window_distance
        end

        local left_pane_distance = math.abs(left.pane_index - current_pane_index)
        local right_pane_distance = math.abs(right.pane_index - current_pane_index)
        if left_pane_distance ~= right_pane_distance then
            return left_pane_distance < right_pane_distance
        end

        if left.window_index ~= right.window_index then
            return left.window_index > right.window_index
        end
        return left.pane_index > right.pane_index
    end
end

local function resolve_port()
    if not vim.env.TMUX then
        error("Not running inside tmux", 0)
    end

    local cwd = vim.fn.getcwd()
    local session_name = tmux_session_name()
    local current_window_index, current_pane_index = current_location()
    local panes = list_opencode_panes(session_name, cwd)
    table.sort(panes, compare_panes(current_window_index, current_pane_index))

    for _, pane in ipairs(panes) do
        local port = pane_port(pane)
        if port then
            return port
        end
    end

    error("No tmux-local opencode pane found for cwd: " .. cwd, 0)
end

local function post(port, body)
    local result = vim.system({
        "curl",
        "-s",
        "--connect-timeout",
        "1",
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-d",
        vim.fn.json_encode(body),
        "http://localhost:" .. port .. "/tui/publish",
    }, { text = true }):wait()

    if result.code ~= 0 then
        error(result.stderr ~= "" and result.stderr or "Failed to send prompt to opencode", 0)
    end
end

function M.prompt(prompt, opts)
    opts = opts or {}
    local context = opts.context or require("opencode.context").new()
    local rendered = context:render(prompt)
    local plaintext = context.plaintext(rendered.output)
    local port = resolve_port()

    post(port, { type = "tui.prompt.append", properties = { text = plaintext } })
    if opts.submit then
        post(port, { type = "tui.command.execute", properties = { command = "prompt.submit" } })
    end
    context:clear()
end

function M.ask(default, opts)
    opts = opts or {}
    local context = opts.context or require("opencode.context").new()
    return require("opencode.ui.ask")
        .ask(default, context)
        :next(function(input)
            opts.context = context
            M.prompt(input, opts)
        end)
        :catch(function(err)
            context:resume()
            if err then
                vim.notify(err, vim.log.levels.ERROR, { title = "opencode tmux" })
            end
        end)
end

function M.ask_this()
    return M.ask("@this: ", { submit = true })
end

function M.debug_resolve_port()
    return resolve_port()
end

return M
