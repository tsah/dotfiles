-- Send a prompt from nvim to an opencode TUI running in another tmux pane/window.
--
-- First principles:
--   1. Capture the visual range (or cursor line) as an opencode file reference
--      `<abspath>:L<start>-L<end>`.
--   2. Ask the user for a message in an input box.
--   3. Find the opencode session for THIS project by searching, in order:
--        a. other panes in the current window
--        b. other windows in the current session
--        c. panes in other sessions
--      ...and if none exists, spawn one in a new pane.
--   4. Deliver the text by pasting it into that pane and pressing Enter
--      (tmux load-buffer + paste-buffer + send-keys). No HTTP, no port parsing
--      on the common path -- we just type into the terminal that is opencode.
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

-- ── finding opencode panes ──────────────────────────────────────────────────

local function list_opencode_panes()
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
        if cmd == "opencode" then
            table.insert(panes, {
                pane_id = id,
                session = session,
                window = tonumber(window),
                index = tonumber(index),
                path = path,
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

-- Find the nearest opencode pane in the SAME project as `from`, searching
-- pane -> window -> session. Returns the pane table or nil.
local function find_target(from)
    local candidates = {}
    for _, pane in ipairs(list_opencode_panes()) do
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
        return math.abs(l.index - from.index) < math.abs(r.index - from.index)
    end)
    trace("find_target", { count = #candidates, pick = candidates[1] })
    return candidates[1]
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

local function deliver(from, text)
    local target = find_target(from)
    if target then
        notify("→ opencode (" .. target.session .. ":" .. target.window .. "." .. target.index .. ")")
        send_to_pane(target.pane_id, text)
        return
    end
    notify("no opencode in this project — spawning…")
    spawn_and_wait(from, function(pane_id)
        send_to_pane(pane_id, text)
    end, function(err)
        notify(err, vim.log.levels.ERROR)
    end)
end

-- ── selection → opencode file reference ─────────────────────────────────────

-- `<abspath>:L<start>-L<end>` is opencode's native reference syntax. In visual
-- mode `line("v")` is the selection anchor and `line(".")` the cursor; in normal
-- mode we reference the single cursor line.
local function selection_ref()
    local buf = vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" then
        return nil
    end
    local path = vim.fn.fnamemodify(name, ":p")

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

    if sline == eline then
        return string.format("%s:L%d", path, sline)
    end
    return string.format("%s:L%d-L%d", path, sline, eline)
end

-- ── public API ──────────────────────────────────────────────────────────────

-- Capture the range NOW (before the input box steals focus), prompt for a
-- message, then deliver "<message> <ref>" to opencode.
function M.ask()
    if not vim.env.TMUX then
        notify("not running inside tmux", vim.log.levels.ERROR)
        return
    end

    local ref = selection_ref()
    local from = origin()

    -- Leave visual mode so the input float opens cleanly.
    if vim.fn.mode():match("^[vV\22]") then
        vim.cmd("normal! \27")
    end

    vim.ui.input({ prompt = "Ask opencode: " }, function(input)
        if input == nil or vim.trim(input) == "" then
            return
        end
        local text = ref and (ref .. " " .. vim.trim(input)) or vim.trim(input)
        trace("ask.submit", { text = text, from = from })
        -- Defer so the input float fully tears down before the tmux/curl work.
        vim.defer_fn(function()
            deliver(from, text)
        end, 50)
    end)
end

-- Back-compat alias used by the keymap.
M.ask_this = M.ask

-- Ensure an opencode exists for this project (used by opencode.nvim's server
-- start hook). Spawns one in the current window if none is found.
function M.ensure_sync()
    if not vim.env.TMUX then
        return
    end
    local from = origin()
    if find_target(from) then
        return
    end
    pcall(spawn_and_wait, from, function() end, function() end)
end

M.ensure = M.ensure_sync

-- Exposed for live testing from headless nvim.
M._find_target = find_target
M._origin = origin
M._deliver = deliver
M._selection_ref = selection_ref

return M
