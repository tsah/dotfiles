local M = {}

local MAX_PORT_ATTEMPTS = 50
local PORT_POLL_MS = 100
local SESSION_NEW_DELAY_MS = 400

-- Diagnostic trace. Set vim.g.opencode_tmux_trace = true to log every step of a
-- delivery to /tmp/oc_tmux_trace.log (mode, path taken, port, curl results).
local TRACE_FILE = "/tmp/oc_tmux_trace.log"
local function trace(step, extra)
    if not vim.g.opencode_tmux_trace then
        return
    end
    local ok, line = pcall(function()
        local ms = vim.uv and vim.uv.now() or 0
        local mode = (vim.api.nvim_get_mode() or {}).mode
        local parts = { string.format("%d", ms), step, "mode=" .. tostring(mode) }
        if extra ~= nil then
            table.insert(parts, type(extra) == "table" and vim.inspect(extra):gsub("%s+", " ") or tostring(extra))
        end
        return table.concat(parts, " | ")
    end)
    if ok then
        pcall(function()
            local fh = io.open(TRACE_FILE, "a")
            if fh then
                fh:write(line .. "\n")
                fh:close()
            end
        end)
    end
end

local function tmux(args)
    local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
    if result.code ~= 0 then
        error((result.stderr ~= "" and result.stderr or "tmux command failed"), 0)
    end
    return vim.trim(result.stdout)
end

local function origin_pane()
    return vim.env.TMUX_PANE
end

local function current_location(tmux_pane)
    tmux_pane = tmux_pane or origin_pane()
    local output = tmux({ "display-message", "-t", tmux_pane, "-p", "#{window_index}\t#{pane_index}" })
    local window_index, pane_index = output:match("^(%d+)\t(%d+)$")
    return tonumber(window_index), tonumber(pane_index)
end

local function tmux_session_name(tmux_pane)
    tmux_pane = tmux_pane or origin_pane()
    return tmux({ "display-message", "-t", tmux_pane, "-p", "#{session_name}" })
end

local function capture_delivery()
    return {
        tmux_pane = origin_pane(),
        cwd = vim.fn.getcwd(),
    }
end

local function list_opencode_panes(session_name, cwd, window_index)
    local output = tmux({
        "list-panes",
        "-a",
        "-F",
        "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}\t#{pane_current_path}",
    })

    local panes = {}
    for line in output:gmatch("[^\r\n]+") do
        local pane_session_name, windex, pane_index, pid, path = line:match("^([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
        if pane_session_name == session_name and path == cwd and tonumber(windex) == window_index then
            table.insert(panes, {
                window_index = tonumber(windex),
                pane_index = tonumber(pane_index),
                pid = pid,
            })
        end
    end
    return panes
end

local function pane_port(pane)
    local pane_process = vim.system({ "ps", "-p", pane.pid, "-o", "args=" }, { text = true }):wait()
    if pane_process.code == 0 then
        local port = pane_process.stdout:match("opencode.*%-%-port%s+(%d+)")
        if port then
            return tonumber(port)
        end
    end

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

local function compare_panes(current_pane_index)
    return function(left, right)
        local left_distance = math.abs(left.pane_index - current_pane_index)
        local right_distance = math.abs(right.pane_index - current_pane_index)
        if left_distance ~= right_distance then
            return left_distance < right_distance
        end
        return left.pane_index > right.pane_index
    end
end

local function find_existing_port_in_current_window(delivery)
    delivery = delivery or capture_delivery()
    local cwd = delivery.cwd
    local session_name = tmux_session_name(delivery.tmux_pane)
    local window_index, pane_index = current_location(delivery.tmux_pane)
    local panes = list_opencode_panes(session_name, cwd, window_index)
    table.sort(panes, compare_panes(pane_index))

    for _, pane in ipairs(panes) do
        local port = pane_port(pane)
        if port then
            return port
        end
    end
    return nil
end

-- Spawn opencode in a new pane that is FOCUSED (note: no `-d`).
--
-- At startup opencode probes the terminal for capabilities (Kitty graphics
-- `\27_Gi=31337,a=q...`, DA, DECRPM, OSC colors). Under ghostty+tmux these are
-- forwarded to the outer terminal and the responses come back to tmux, which
-- routes them to whichever pane is *focused*. If we spawned detached (nvim
-- focused), the responses leak into the nvim buffer as literal keystrokes
-- (`\27_Gi=31337;OK` → `i` enters insert mode, `=31337;OK` is typed, a stray
-- `\` trips the yazi mapping, and the hit-enter prompt freezes nvim's loop).
-- Spawning opencode focused makes its own pane receive those responses
-- harmlessly. The caller restores focus to nvim once opencode is past the
-- probing phase (i.e. its HTTP server is up). Returns `origin` so callers know
-- which pane to focus back.
local function spawn_opencode_pane(cwd, tmux_pane)
    tmux_pane = tmux_pane or origin_pane()
    local pane_id = tmux({
        "split-window",
        "-h",
        "-t",
        tmux_pane,
        "-P",
        "-F",
        "#{pane_id}",
        "-c",
        cwd,
        "oc",
        "--new",
    })
    local pid = tmux({ "display-message", "-p", "-t", pane_id, "#{pane_pid}" })
    return { pane_id = pane_id, pid = pid, origin = tmux_pane }
end

-- Move tmux focus back to the given pane (the nvim pane). Best-effort.
local function restore_focus(tmux_pane)
    if tmux_pane then
        pcall(tmux, { "select-pane", "-t", tmux_pane })
    end
end

-- A freshly spawned opencode loads plugins/MCP before its HTTP server answers,
-- which can take well over 5s on a cold start, so allow a generous budget.
local HTTP_READY_ATTEMPTS = 200 -- ~200 * 100ms = 20s
local function verify_port_http_async(port, on_ready, on_error, attempt)
    attempt = attempt or 0
    vim.system({
        "curl",
        "-s",
        "-f",
        "-o",
        "/dev/null",
        "--connect-timeout",
        "1",
        -- Bound the whole request: a cold opencode accepts the TCP connection
        -- before its HTTP server answers, and without --max-time curl hangs on
        -- that first request forever, stalling the readiness poll.
        "--max-time",
        "2",
        "http://127.0.0.1:" .. port .. "/global/health",
    }, {}, function(result)
        if result.code == 0 then
            trace("http_ready", { port = port, attempt = attempt })
            on_ready(port)
            return
        end
        if attempt >= HTTP_READY_ATTEMPTS then
            trace("http_timeout", { port = port })
            on_error("opencode HTTP API not ready on port " .. port)
            return
        end
        vim.defer_fn(function()
            verify_port_http_async(port, on_ready, on_error, attempt + 1)
        end, PORT_POLL_MS)
    end)
end

local function wait_for_pane_port_async(pane, on_ready, on_error, attempt)
    attempt = attempt or 0
    local ok, port = pcall(pane_port, pane)
    trace("wait_pane_port", { attempt = attempt, ok = ok, port = ok and port or tostring(port) })
    if ok and port then
        verify_port_http_async(port, on_ready, on_error, 0)
        return
    end
    if attempt >= MAX_PORT_ATTEMPTS then
        on_error("opencode pane started but --port not ready")
        return
    end
    vim.defer_fn(function()
        wait_for_pane_port_async(pane, on_ready, on_error, attempt + 1)
    end, PORT_POLL_MS)
end

---@param on_ready fun(port: integer, reused: boolean)
local function resolve_port_async(on_ready, on_error, delivery)
    delivery = delivery or capture_delivery()
    if not vim.env.TMUX then
        on_error("Not running inside tmux")
        return
    end

    local port = find_existing_port_in_current_window(delivery)
    trace("resolve_port", { found = port, delivery = delivery })
    if port then
        verify_port_http_async(port, function(ready_port)
            trace("resolve_port.reused.ready", ready_port)
            on_ready(ready_port, true, nil)
        end, on_error, 0)
        return
    end

    trace("resolve_port.spawning")
    local ok, pane = pcall(spawn_opencode_pane, delivery.cwd, delivery.tmux_pane)
    trace("resolve_port.spawned", { ok = ok, pane = ok and pane or tostring(pane) })
    if not ok then
        on_error(pane)
        return
    end
    wait_for_pane_port_async(pane, function(ready_port)
        -- HTTP is up => opencode is past its terminal-probing startup, so it is
        -- now safe to move focus back to nvim without leaking probe responses.
        restore_focus(pane.origin)
        trace("resolve_port.focus_restored", pane.origin)
        on_ready(ready_port, false, pane.pane_id)
    end, on_error)
end

local function post_async(port, body, on_done)
    -- vim.fn.json_encode is not allowed in vim.system callbacks (fast events).
    vim.schedule(function()
        local payload = vim.json.encode(body)
        vim.system({
            "curl",
            "-s",
            "-f",
            "--connect-timeout",
            "2",
            "--max-time",
            "5",
            "-X",
            "POST",
            "-H",
            "Content-Type: application/json",
            "-d",
            payload,
            "http://127.0.0.1:" .. port .. "/tui/publish",
        }, { text = true }, function(result)
            vim.schedule(function()
                if on_done then
                    on_done(result)
                end
            end)
        end)
    end)
end

-- Empty the TUI input field so a new prompt never concatenates with leftover
-- unsubmitted text (session.new clears chat history but not the input box).
local function clear_prompt_async(port, on_done)
    vim.system({
        "curl",
        "-s",
        "-f",
        "--connect-timeout",
        "2",
        "--max-time",
        "5",
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-d",
        "{}",
        "http://127.0.0.1:" .. port .. "/tui/clear-prompt",
    }, { text = true }, function(result)
        vim.schedule(function()
            if on_done then
                on_done(result)
            end
        end)
    end)
end

local TUI_READY_ATTEMPTS = 40 -- ~40 * 200ms = 8s
local TUI_READY_POLL_MS = 200
local TUI_SENTINEL = "OPENCODE_NVIM_READY_PROBE"

-- After spawning, opencode's HTTP server (which answers /global/health) is up
-- well before the TUI client subscribes to the event stream. A prompt published
-- in that gap is silently dropped. Probe by appending a sentinel and confirming
-- it actually rendered in the pane; only then is the TUI ready for real input.
local function wait_for_tui_ready_async(port, pane_id, on_ready, on_error, attempt)
    attempt = attempt or 0
    post_async(port, { type = "tui.prompt.append", properties = { text = TUI_SENTINEL } }, function()
        vim.defer_fn(function()
            vim.system({ "tmux", "capture-pane", "-p", "-t", pane_id }, { text = true }, function(result)
                local rendered = result.code == 0 and result.stdout:find(TUI_SENTINEL, 1, true) ~= nil
                vim.schedule(function()
                    trace("tui_ready.probe", { attempt = attempt, rendered = rendered })
                    if rendered then
                        clear_prompt_async(port, function()
                            on_ready()
                        end)
                        return
                    end
                    if attempt >= TUI_READY_ATTEMPTS then
                        on_error("opencode TUI did not become ready for input")
                        return
                    end
                    wait_for_tui_ready_async(port, pane_id, on_ready, on_error, attempt + 1)
                end)
            end)
        end, TUI_READY_POLL_MS)
    end)
end

local function notify_error(err)
    vim.schedule(function()
        vim.notify(tostring(err), vim.log.levels.ERROR, { title = "opencode tmux" })
    end)
end

local function render_prompt(prompt, context)
    if context == nil then
        return prompt
    end
    local rendered = context:render(prompt, {})
    return context.plaintext(rendered.output)
end

local function defer(fn, delay_ms)
    vim.defer_fn(fn, delay_ms)
end

local function append_and_submit(port, plaintext, opts)
    if plaintext == nil or plaintext == "" then
        notify_error("Prompt is empty")
        return
    end
    trace("append_and_submit", { port = port, submit = opts.submit, len = #plaintext })
    clear_prompt_async(port, function(clear_result)
        trace("clear.done", { code = clear_result.code, stderr = clear_result.stderr })
        if clear_result.code ~= 0 then
            notify_error(clear_result.stderr ~= "" and clear_result.stderr or "Failed to clear opencode prompt")
            return
        end
        post_async(port, { type = "tui.prompt.append", properties = { text = plaintext } }, function(append_result)
            trace("append.done", { code = append_result.code, stdout = append_result.stdout, stderr = append_result.stderr })
            if append_result.code ~= 0 then
                notify_error(append_result.stderr ~= "" and append_result.stderr or "Failed to send prompt to opencode")
                return
            end
            if not opts.submit then
                return
            end
            post_async(port, { type = "tui.command.execute", properties = { command = "prompt.submit" } }, function(submit_result)
                trace("submit.done", { code = submit_result.code, stdout = submit_result.stdout, stderr = submit_result.stderr })
                if submit_result.code ~= 0 then
                    notify_error(submit_result.stderr ~= "" and submit_result.stderr or "Failed to submit opencode prompt")
                end
            end)
        end)
    end)
end

function M.deliver_async(plaintext, opts, delivery)
    opts = opts or {}
    delivery = delivery or capture_delivery()
    if opts.new_session == nil then
        opts.new_session = false
    end

    resolve_port_async(function(port, reused, pane_id)
        if not reused then
            -- Freshly spawned: `oc --new` already starts a new session, so we
            -- only need to wait until the TUI can actually receive input.
            wait_for_tui_ready_async(port, pane_id, function()
                append_and_submit(port, plaintext, opts)
            end, notify_error)
            return
        end
        if opts.new_session then
            post_async(port, { type = "tui.command.execute", properties = { command = "session.new" } }, function(session_result)
                if session_result.code ~= 0 then
                    notify_error(session_result.stderr ~= "" and session_result.stderr or "Failed to start new opencode session")
                    return
                end
                defer(function()
                    append_and_submit(port, plaintext, opts)
                end, SESSION_NEW_DELAY_MS)
            end)
            return
        end
        append_and_submit(port, plaintext, opts)
    end, notify_error, delivery)
end

---Spawn opencode in the current tmux window if missing.
---Used by opencode.nvim discovery polling. The new pane is spawned focused (so
---opencode's terminal-probe responses don't leak into nvim); focus is restored
---to the origin pane once opencode's HTTP server is up.
function M.ensure_sync()
    if not vim.env.TMUX then
        return
    end
    if find_existing_port_in_current_window() then
        return
    end
    local origin = origin_pane()
    local ok, pane = pcall(spawn_opencode_pane, vim.fn.getcwd(), origin)
    if not ok then
        return
    end
    wait_for_pane_port_async(pane, function()
        restore_focus(pane.origin)
    end, function()
        restore_focus(pane.origin)
    end)
end

function M.ensure()
    M.ensure_sync()
end

local function open_ask_input(default, context, on_submit)
    local input_opts = {
        prompt = "Ask opencode: ",
        default = default,
    }

    local ok_cfg, cfg = pcall(require, "opencode.config")
    if ok_cfg and cfg.opts.ask then
        input_opts = vim.tbl_deep_extend("force", input_opts, cfg.opts.ask)
    end

    if context ~= nil then
        local rendered = context:render(default or "", {})
        input_opts.highlight = function(text)
            local live = context:render(text, {})
            return context.input_highlight(live.input)
        end
    end

    vim.ui.input(input_opts, on_submit)
end

function M.ask(default, opts)
    opts = opts or {}
    if not vim.env.TMUX then
        vim.notify("Not running inside tmux", vim.log.levels.ERROR, { title = "opencode tmux" })
        return
    end

    local context = nil
    local ok_context, resolved_context = pcall(function()
        return require("opencode.context").new()
    end)
    if ok_context then
        context = resolved_context
    end

    trace("M.ask.open", { default = default })
    open_ask_input(default, context, function(input)
        trace("M.ask.on_submit", { input = input })
        local delivery = capture_delivery()
        if input == nil or input == "" then
            if context ~= nil then
                context:clear()
            end
            return
        end

        local plaintext = render_prompt(input, context)
        trace("M.ask.rendered", { plaintext = plaintext })
        if context ~= nil then
            context:clear()
        end
        -- Defer delivery so the snacks input float fully tears down before any
        -- blocking tmux/ps/curl work runs. Running the synchronous port
        -- resolution inside the input callback disrupts the float teardown,
        -- leaving nvim stuck in insert mode (keystrokes leak as buffer text)
        -- and spilling terminal escape sequences into the window.
        defer(function()
            trace("M.ask.deferred_deliver")
            M.deliver_async(plaintext, opts, delivery)
        end, 50)
    end)
end

function M.ask_this()
    return M.ask("@this: ", { submit = true })
end

function M.debug_resolve_port()
    return find_existing_port_in_current_window()
end

return M
