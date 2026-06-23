-- Send a prompt from nvim to a coding-agent TUI running in another tmux pane.
--
-- Generic over agents: opencode, claude, codex, pi. They are all just terminal
-- programs that take a line of input and submit on Enter, so delivery is the
-- same for all of them (tmux load-buffer + paste-buffer + send-keys). The only
-- per-agent difference is how a file reference is written, captured in AGENTS.
--
-- First principles:
--   1. Capture the visual range (or cursor line) as { path, sline, eline }.
--   2. Ask the user for a message in an input box.
--   3. Find the nearest agent for THIS project, searching in order:
--        a. other panes in the current window   (precedence: pane)
--        b. other windows in the current session (fallback: window)
--        c. panes in other sessions
--      ...and if none exists, spawn opencode in a new pane.
--   4. Format the reference for the chosen agent, then paste "<ref> <message>"
--      into its pane and press Enter. No HTTP, no port parsing on the common
--      path -- we just type into the terminal that is the agent.
--
-- Set vim.g.opencode_tmux_trace = true to log each step to /tmp/oc_tmux_trace.log.

local M = {}

local HEALTH_POLL_MS = 150
local HEALTH_MAX_ATTEMPTS = 200 -- ~30s budget for a cold spawn

local TRACE_FILE = "/tmp/oc_tmux_trace.log"
local function trace(step, extra)
    if not vim.g.opencode_tmux_trace then
        return
    end
    pcall(function()
        local parts = { step }
        if extra ~= nil then
            table.insert(parts, type(extra) == "table" and vim.inspect(extra):gsub("%s+", " ") or tostring(extra))
        end
        local fh = io.open(TRACE_FILE, "a")
        if fh then
            fh:write(table.concat(parts, " | ") .. "\n")
            fh:close()
        end
    end)
end

local function tmux(args)
    local result = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
    if result.code ~= 0 then
        error((result.stderr ~= "" and result.stderr or "tmux command failed"), 0)
    end
    return vim.trim(result.stdout)
end

local function notify(msg, level)
    vim.schedule(function()
        vim.notify(tostring(msg), level or vim.log.levels.INFO, { title = "opencode" })
    end)
end

-- ── project identity ────────────────────────────────────────────────────────

local function git_root(path)
    local result = vim.system({ "git", "-C", path, "rev-parse", "--show-toplevel" }, { text = true }):wait()
    if result.code ~= 0 then
        return nil
    end
    return vim.trim(result.stdout)
end

-- Two paths belong to the same project if they share a git root (or are equal).
local function same_project(a, b)
    if a == b then
        return true
    end
    local ra = git_root(a)
    return ra ~= nil and ra == git_root(b)
end

-- ── where am I ──────────────────────────────────────────────────────────────

-- The project is anchored on the EDITED FILE's directory, not nvim's cwd: the
-- two can differ (global cwd, :tcd, files opened from elsewhere) and the file is
-- what the prompt is about, so it must decide which opencode we target.
local function project_anchor()
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" then
        return vim.fn.fnamemodify(name, ":p:h")
    end
    return vim.fn.getcwd()
end

local function origin()
    local pane = vim.env.TMUX_PANE
    local out = tmux({ "display-message", "-t", pane, "-p", "#{session_name}\t#{window_index}\t#{pane_index}" })
    local session, window, index = out:match("^([^\t]*)\t(%d+)\t(%d+)$")
    return {
        pane_id = pane,
        session = session,
        window = tonumber(window),
        index = tonumber(index),
        project_dir = project_anchor(),
    }
end

-- ── agent registry ──────────────────────────────────────────────────────────

-- Make `path` relative to `base` (the agent pane's cwd) when it lives under it;
-- used for `@`-style mentions which resolve against the agent's working dir.
local function rel_to(path, base)
    if base and base ~= "" then
        local prefix = base:gsub("/+$", "") .. "/"
        if path:sub(1, #prefix) == prefix then
            return path:sub(#prefix + 1)
        end
    end
    return path
end

-- `<abspath>:L<start>-L<end>` -- opencode renders this as a context chip; codex
-- and pi have no special mention syntax, so they just read the bare path.
local function ref_path_lines(sel, _base)
    if not sel.eline or sel.eline == sel.sline then
        return string.format("%s:L%d", sel.path, sel.sline)
    end
    return string.format("%s:L%d-L%d", sel.path, sel.sline, sel.eline)
end

-- `@<relpath> (lines x-y)` -- Claude Code resolves the `@relpath` token (a valid
-- path) as a real file mention; the parenthetical carries the range as a hint.
local function ref_at_mention(sel, base)
    local rel = rel_to(sel.path, base)
    if not sel.eline or sel.eline == sel.sline then
        return string.format("@%s (line %d)", rel, sel.sline)
    end
    return string.format("@%s (lines %d-%d)", rel, sel.sline, sel.eline)
end

-- Matched against `pane_current_command`. Order is the tie-break priority when
-- two agents are equally near. Each `ref` is easy to tweak per your taste.
local AGENTS = {
    { cmd = "opencode", ref = ref_path_lines },
    { cmd = "claude", ref = ref_at_mention },
    { cmd = "codex", ref = ref_path_lines },
    { cmd = "pi", ref = ref_path_lines },
}

local function agent_for_command(cmd)
    for priority, agent in ipairs(AGENTS) do
        if agent.cmd == cmd then
            return agent, priority
        end
    end
    return nil
end

-- ── finding agent panes ─────────────────────────────────────────────────────

local function list_agent_panes()
    local out = tmux({
        "list-panes",
        "-a",
        "-F",
        "#{pane_id}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}",
    })
    local panes = {}
    for line in out:gmatch("[^\r\n]+") do
        local id, session, window, index, cmd, path =
            line:match("^(%S+)\t([^\t]*)\t(%d+)\t(%d+)\t([^\t]*)\t(.*)$")
        local agent, priority = agent_for_command(cmd)
        if agent then
            table.insert(panes, {
                pane_id = id,
                session = session,
                window = tonumber(window),
                index = tonumber(index),
                path = path,
                agent = agent,
                priority = priority,
            })
        end
    end
    return panes
end

-- Proximity tier: lower is closer. 1 = same window, 2 = same session, 3 = other.
local function tier(pane, from)
    if pane.session == from.session and pane.window == from.window then
        return 1
    end
    if pane.session == from.session then
        return 2
    end
    return 3
end

-- Find the nearest agent pane in the SAME project as `from`, searching
-- pane -> window -> session. Proximity wins; when two agents are equally near,
-- AGENTS order breaks the tie. Returns the pane table (with `.agent`) or nil.
local function find_target(from)
    local candidates = {}
    for _, pane in ipairs(list_agent_panes()) do
        if pane.pane_id ~= from.pane_id and same_project(pane.path, from.project_dir) then
            table.insert(candidates, pane)
        end
    end
    table.sort(candidates, function(l, r)
        local lt, rt = tier(l, from), tier(r, from)
        if lt ~= rt then
            return lt < rt
        end
        if l.window ~= r.window then
            return math.abs(l.window - from.window) < math.abs(r.window - from.window)
        end
        if l.index ~= r.index then
            return math.abs(l.index - from.index) < math.abs(r.index - from.index)
        end
        return l.priority < r.priority
    end)
    local pick = candidates[1]
    trace("find_target", { count = #candidates, pick = pick and { pane = pick.pane_id, agent = pick.agent.cmd } })
    return pick
end

-- ── spawning (fallback) ─────────────────────────────────────────────────────

-- The opencode process under a pane exposes its HTTP port in its args; we only
-- need it as a readiness signal for a freshly spawned instance.
local function pane_port(pane_id)
    local pid = tmux({ "display-message", "-p", "-t", pane_id, "#{pane_pid}" })
    for _, p in ipairs({ pid }) do
        local ps = vim.system({ "ps", "-p", p, "-o", "args=" }, { text = true }):wait()
        local port = ps.code == 0 and ps.stdout:match("opencode.*%-%-port%s+(%d+)")
        if port then
            return tonumber(port)
        end
    end
    local kids = vim.system({ "pgrep", "-a", "-P", pid }, { text = true }):wait()
    if kids.code == 0 then
        local port = kids.stdout:match("opencode.*%-%-port%s+(%d+)")
        if port then
            return tonumber(port)
        end
    end
    return nil
end

local function health_ok(port)
    local r = vim.system({
        "curl", "-sf", "--connect-timeout", "1", "--max-time", "2",
        "http://127.0.0.1:" .. port .. "/global/health",
    }, { text = true }):wait()
    return r.code == 0
end

local function pane_shows(pane_id, needle)
    local cap = vim.system({ "tmux", "capture-pane", "-p", "-t", pane_id }, { text = true }):wait()
    return cap.code == 0 and cap.stdout:find(needle, 1, true) ~= nil
end

-- Spawn opencode focused (so its terminal-probe responses land in its own pane,
-- not nvim's), wait until its HTTP server answers, restore focus, then call
-- on_ready(pane_id). The HTTP server answers before the TUI is ready for input,
-- but send_to_pane verifies its paste landed and retries, so on_ready can fire
-- as soon as the process is alive. Synchronous waits run on a timer.
local function spawn_and_wait(from, on_ready, on_error)
    local pane_id = tmux({
        "split-window", "-h", "-t", from.pane_id, "-P", "-F", "#{pane_id}",
        "-c", from.project_dir, "oc", "--new",
    })
    trace("spawned", pane_id)

    local attempt = 0
    local function poll()
        attempt = attempt + 1
        local port = pane_port(pane_id)
        if port and health_ok(port) then
            pcall(tmux, { "select-pane", "-t", from.pane_id }) -- restore focus to nvim
            trace("spawn_health_ok", { pane_id = pane_id, port = port, attempt = attempt })
            on_ready(pane_id)
            return
        end
        if attempt >= HEALTH_MAX_ATTEMPTS then
            on_error("opencode spawned but never became ready")
            return
        end
        vim.defer_fn(poll, HEALTH_POLL_MS)
    end
    poll()
end

-- ── delivery ────────────────────────────────────────────────────────────────

-- Paste `text` into the opencode pane and submit it.
--
-- Two things make this tricky and both are handled by verify-and-retry rather
-- than fixed sleeps:
--   * A freshly spawned opencode answers HTTP before its TUI reads stdin, so an
--     early paste is dropped.
--   * A fresh opencode also wipes its input box ONCE a couple seconds in, which
--     erases a paste that landed just before it.
-- So: paste, confirm the text shows AND still shows after a settle window (i.e.
-- it survived the wipe), only then press Enter. If the paste was dropped or
-- wiped, the box is empty again, so re-pasting is clean (no accumulation). The
-- payload is a single line, so Enter submits without a stray newline.
local SEND_MAX_ATTEMPTS = 15
local SEND_SETTLE_MS = 450
local function send_to_pane(pane_id, text, on_done)
    -- Verify against the TAIL: the payload now leads with the file reference
    -- (a path that may already be on screen in an existing session), whereas the
    -- end of the text -- the user's message -- is distinctive. Short enough to
    -- not span an input-box line wrap.
    local needle = text:sub(-14)
    local attempt = 0
    local function try()
        attempt = attempt + 1
        vim.system({ "tmux", "load-buffer", "-b", "oc_nvim", "-" }, { stdin = text }):wait()
        pcall(tmux, { "paste-buffer", "-d", "-b", "oc_nvim", "-t", pane_id })
        vim.defer_fn(function()
            if not pane_shows(pane_id, needle) then
                -- Paste never landed (TUI not reading yet) or was wiped.
                if attempt >= SEND_MAX_ATTEMPTS then
                    trace("send_failed", { pane_id = pane_id, attempt = attempt })
                    if on_done then on_done(false) end
                    return
                end
                vim.defer_fn(try, SEND_SETTLE_MS)
                return
            end
            -- Landed; make sure it sticks (survives the one-shot input wipe).
            vim.defer_fn(function()
                if pane_shows(pane_id, needle) then
                    pcall(tmux, { "send-keys", "-t", pane_id, "Enter" })
                    trace("sent", { pane_id = pane_id, attempt = attempt, len = #text })
                    if on_done then on_done(true) end
                elseif attempt >= SEND_MAX_ATTEMPTS then
                    trace("send_failed", { pane_id = pane_id, attempt = attempt })
                    if on_done then on_done(false) end
                else
                    vim.defer_fn(try, SEND_SETTLE_MS)
                end
            end, SEND_SETTLE_MS)
        end, SEND_SETTLE_MS)
    end
    try()
end

-- Build "<ref> <message>" for a given agent, or just the message if no buffer
-- selection was captured.
local function compose(agent, sel, message, base)
    if not sel then
        return message
    end
    return agent.ref(sel, base) .. " " .. message
end

local function deliver(from, sel, message)
    local target = find_target(from)
    if target then
        notify("→ " .. target.agent.cmd .. " (" .. target.session .. ":" .. target.window .. "." .. target.index .. ")")
        send_to_pane(target.pane_id, compose(target.agent, sel, message, target.path))
        return
    end
    -- Nothing found: spawn opencode (the agent with a clean --new wrapper).
    notify("no agent in this project — spawning opencode…")
    local opencode = agent_for_command("opencode")
    spawn_and_wait(from, function(pane_id)
        send_to_pane(pane_id, compose(opencode, sel, message, from.project_dir))
    end, function(err)
        notify(err, vim.log.levels.ERROR)
    end)
end

-- ── selection capture ───────────────────────────────────────────────────────

-- Capture the visual range (or cursor line) as { path, sline, eline }. In visual
-- mode `line("v")` is the selection anchor and `line(".")` the cursor; in normal
-- mode the single cursor line. Per-agent formatting happens later, at delivery,
-- once we know which agent we are talking to.
local function capture_selection()
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then
        return nil
    end
    local sline, eline
    if vim.fn.mode():match("^[vV\22]") then
        sline, eline = vim.fn.line("v"), vim.fn.line(".")
    else
        sline = vim.fn.line(".")
        eline = sline
    end
    if sline > eline then
        sline, eline = eline, sline
    end
    return { path = vim.fn.fnamemodify(name, ":p"), sline = sline, eline = eline }
end

-- ── public API ──────────────────────────────────────────────────────────────

-- Capture the range NOW (before the input box steals focus), prompt for a
-- message, then deliver "<ref> <message>" to the nearest agent.
function M.ask()
    if not vim.env.TMUX then
        notify("not running inside tmux", vim.log.levels.ERROR)
        return
    end

    local sel = capture_selection()
    local from = origin()

    -- Leave visual mode so the input float opens cleanly.
    if vim.fn.mode():match("^[vV\22]") then
        vim.cmd("normal! \27")
    end

    vim.ui.input({ prompt = "Ask agent: " }, function(input)
        if input == nil or vim.trim(input) == "" then
            return
        end
        local message = vim.trim(input)
        trace("ask.submit", { message = message, sel = sel, from = from })
        -- Defer so the input float fully tears down before the tmux work.
        vim.defer_fn(function()
            deliver(from, sel, message)
        end, 50)
    end)
end

-- Back-compat alias used by the keymap.
M.ask_this = M.ask

-- Ensure an opencode exists for this project (used by opencode.nvim's server
-- start hook). Unlike M.ask this is opencode-specific: it ignores other agents
-- and spawns opencode if none is found.
function M.ensure_sync()
    if not vim.env.TMUX then
        return
    end
    local from = origin()
    for _, pane in ipairs(list_agent_panes()) do
        if pane.agent.cmd == "opencode" and pane.pane_id ~= from.pane_id and same_project(pane.path, from.project_dir) then
            return
        end
    end
    pcall(spawn_and_wait, from, function() end, function() end)
end

M.ensure = M.ensure_sync

-- Exposed for live testing from headless nvim.
M._find_target = find_target
M._origin = origin
M._deliver = deliver
M._capture_selection = capture_selection

return M
