local hyper = { "ctrl", "alt" }

hs.ipc.cliInstall()
hs.autoLaunch(true)

-- Maccy (clipboard history, Shift+Cmd+C) has no config file; starting it from
-- here keeps "launch at login" in dotfiles instead of its settings window.
if not hs.application.get("Maccy") then
  hs.execute("open -g -a Maccy")
end

-- LinearMouse reverses the mouse wheel (config: linearmouse/linearmouse.json).
if not hs.application.get("LinearMouse") then
  hs.execute("open -g -a LinearMouse")
end

local browser_app = "Google Chrome"
local browser_personal_profile = "Default"
local browser_work_profile = "Profile 1"
local terminal_app = "Herdr"
local slack_app = "Slack"
local whatsapp_app = "WhatsApp"
local screenshot_share_script = os.getenv("HOME") .. "/dotfiles/bin/macos-screenshot-share"
running_tasks = running_tasks or {}

local function shell_quote(value)
  return string.format("%q", value)
end

local function open_browser_profile(profile)
  hs.execute(
    "open -na "
      .. shell_quote(browser_app)
      .. " --args --profile-directory="
      .. shell_quote(profile),
    true
  )
end

local function wait_for_main_window(app_name, callback)
  local attempts = 0
  local timer

  timer = hs.timer.doEvery(0.1, function()
    attempts = attempts + 1

    local app = hs.application.get(app_name)
    local window = app and app:mainWindow()
    if window then
      timer:stop()
      callback(window)
      return
    end

    if attempts >= 50 then
      timer:stop()
      hs.alert.show("No window found: " .. app_name)
    end
  end)
end

local function launch_or_focus(app_name, callback)
  hs.application.launchOrFocus(app_name)
  wait_for_main_window(app_name, callback)
end

local function has_only_hyper(flags)
  return flags.ctrl
    and flags.alt
    and not flags.cmd
    and not flags.shift
    and not flags.fn
end

local function has_hyper_shift(flags)
  return flags.ctrl
    and flags.alt
    and flags.shift
    and not flags.cmd
    and not flags.fn
end

function start_screenshot_share()
  hs.alert.show("Screenshot selection")

  local task
  task = hs.task.new(screenshot_share_script, function(exit_code, stdout, stderr)
    running_tasks[task] = nil

    if exit_code ~= 0 then
      hs.alert.show("Screenshot upload failed")
      if stderr and stderr ~= "" then
        print(stderr)
      end
    end
  end)

  running_tasks[task] = true
  task:start()
end

-- ANSI key codes, so the bindings work whatever input source (Hebrew too)
-- is active when Hammerspoon loads; hs.keycodes.map follows the current layout.
local key = { b = 11, e = 14, f = 3, n = 45, o = 31, x = 7, r = 15, v = 9, h = 4, j = 38, k = 40, l = 37, m = 46, p = 35, s = 1, t = 17, u = 32, w = 13, ["1"] = 18, ["2"] = 19, ["3"] = 20, ["4"] = 21 }

local function focus_app(app_name)
  return function()
    launch_or_focus(app_name, function(window)
      window:focus()
    end)
  end
end

local function move_focused(unit)
  local window = hs.window.focusedWindow()
  if window then
    window:moveToUnit(unit)
  end
end

local function snap(unit)
  return function()
    move_focused(unit)
  end
end

local function add_desktop()
  local screen = hs.screen.mainScreen()
  local ok, err = hs.spaces.addSpaceToScreen(screen, false)
  if not ok then
    hs.alert.show("Could not add a desktop: " .. tostring(err))
    return
  end
  local count = #hs.spaces.spacesForScreen(screen)
  hs.alert.show("Desktop " .. count .. " added")
end

-- Notifications have no macOS shortcut; press the top one's own buttons over
-- Accessibility. Banners (AXNotificationCenterBanner) and alerts both match.
local function top_notification()
  local app = hs.application.get("com.apple.notificationcenterui")
  if not app then return nil end
  local function find(el, depth)
    if depth > 12 then return nil end
    local sub = el:attributeValue("AXSubrole") or ""
    if sub:match("^AXNotificationCenter") then return el end
    for _, child in ipairs(el:attributeValue("AXChildren") or {}) do
      local hit = find(child, depth + 1)
      if hit then return hit end
    end
  end
  for _, window in ipairs(hs.axuielement.applicationElement(app):attributeValue("AXWindows") or {}) do
    local hit = find(window, 0)
    if hit then return hit end
  end
end

local function notification_action(pattern)
  return function()
    local note = top_notification()
    if not note then
      hs.alert.show("No notification")
      return
    end
    for _, name in ipairs(note:actionNames() or {}) do
      local label = name .. " " .. tostring(note:actionDescription(name))
      if label:match(pattern) then
        note:performAction(name)
        return
      end
    end
    hs.alert.show("Notification has no matching button")
  end
end

local key_actions = {
  [key.n] = add_desktop,
  -- Notifications: X dismisses the top one, O opens it.
  [key.x] = notification_action("Close"),
  [key.o] = notification_action("AXPress"),
  -- Snapping: H left half, L right half, K (or F) maximize, J centered.
  [key.h] = snap(hs.layout.left50),
  [key.l] = snap(hs.layout.right50),
  [key.k] = snap(hs.layout.maximized),
  [key.f] = snap(hs.layout.maximized),
  [key.j] = snap({ x = 1 / 6, y = 1 / 8, w = 2 / 3, h = 3 / 4 }),
  -- Numbers match the Omarchy workspaces: 1 terminal, 2 browser, 3 Slack, 4 Grok Bot.
  [key["1"]] = focus_app(terminal_app),
  [key["2"]] = focus_app(browser_app),
  [key["3"]] = focus_app(slack_app),
  [key["4"]] = focus_app("Grok Bot"),
  [key.p] = function()
    open_browser_profile(browser_personal_profile)
  end,
  [key.w] = function()
    open_browser_profile(browser_work_profile)
  end,
  [key.b] = function()
    launch_or_focus(browser_app, function(window)
      window:focus()
    end)
  end,
  [key.t] = function()
    launch_or_focus(terminal_app, function(window)
      window:focus()
    end)
  end,
  [key.s] = function()
    launch_or_focus(slack_app, function(window)
      window:focus()
    end)
  end,
  [key.m] = function()
    launch_or_focus(whatsapp_app, function(window)
      window:focus()
    end)
  end,
  [key.u] = function()
    start_screenshot_share()
  end,
}

local shift_key_actions = {
  [key.s] = function()
    start_screenshot_share()
  end,
}

app_shortcuts_tap = hs.eventtap
  .new({ hs.eventtap.event.types.keyDown }, function(event)
    local flags = event:getFlags()
    local action

    if has_only_hyper(flags) then
      action = key_actions[event:getKeyCode()]
    elseif has_hyper_shift(flags) then
      action = shift_key_actions[event:getKeyCode()]
    end

    if not action then
      return false
    end

    action()
    return true
  end)
app_shortcuts_tap:start()

-- Snapping is on Ctrl+Option+HJKL; Herdr keeps Ctrl+Option+arrows for pane focus.
hs.window.animationDuration = 0

-- Natural scrolling is on system-wide (for the trackpad); LinearMouse reverses
-- the mouse wheel. See linearmouse/linearmouse.json.

hs.alert.show("Hammerspoon config loaded")
