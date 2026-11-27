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
local slack_app = "Slack"
local whatsapp_app = "net.whatsapp.WhatsApp" -- bundle ID: the app name starts with an invisible mark
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

-- app_name is an app name or, when it contains a dot, a bundle ID (for apps
-- whose file name differs from their running name, like "Rex Beta.app" -> "Rex").
local function launch_or_focus(app_name, callback)
  if app_name:find("%.") then
    hs.application.launchOrFocusByBundleID(app_name)
  else
    hs.application.launchOrFocus(app_name)
  end
  wait_for_main_window(app_name, callback)
end

-- Option alone is the global modifier (Ctrl+Option before 2026-11-23).
local function has_only_opt(flags)
  return flags.alt
    and not flags.ctrl
    and not flags.cmd
    and not flags.shift
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
local key = { space = 49, q = 12, o = 31, x = 7, h = 4, j = 38, k = 40, l = 37, p = 35, u = 32, w = 13, ["1"] = 18, ["2"] = 19, ["3"] = 20, ["4"] = 21, ["5"] = 23 }

local function focus_app(app_name)
  return function()
    launch_or_focus(app_name, function(window)
      window:focus()
    end)
  end
end

-- Focus the frontmost window in a direction, like yabai's "focus west".
local function focus_dir(method)
  return function()
    local window = hs.window.focusedWindow()
    if window then
      window[method](window, nil, true)
    end
  end
end

hs.hints.showTitleThresh = 6

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

-- Bound on purpose to few keys: each Opt+key stops typing its character, and
-- Rex sends Option as Alt, so B/F/D/. stay free for readline word movement.
-- The keyboard firmware allow-lists these keys for same-hand Opt
-- (qmk_firmware: opt-keybinds.txt); keep the two in sync.
local key_actions = {
  -- Notifications: X dismisses the top one, O opens it.
  [key.x] = notification_action("Close"),
  [key.o] = notification_action("AXPress"),
  -- Focus by direction; Space shows a letter on each window to jump to.
  [key.h] = focus_dir("focusWindowWest"),
  [key.j] = focus_dir("focusWindowSouth"),
  [key.k] = focus_dir("focusWindowNorth"),
  [key.l] = focus_dir("focusWindowEast"),
  [key.space] = hs.hints.windowHints,
  -- 1 Rex, 2 browser, 3 Slack, 4 WhatsApp, 5 Grok Bot (Cmd+Opt+1-5 too).
  [key["1"]] = focus_app("com.superlogical.rex"),
  [key["2"]] = focus_app(browser_app),
  [key["3"]] = focus_app(slack_app),
  [key["4"]] = focus_app(whatsapp_app),
  [key["5"]] = focus_app("Grok Bot"),
  -- P / W open a new Chrome window in the personal / work profile.
  [key.p] = function()
    open_browser_profile(browser_personal_profile)
  end,
  [key.w] = function()
    open_browser_profile(browser_work_profile)
  end,
  -- Q: close the focused window (like its red button).
  [key.q] = function()
    local window = hs.window.focusedWindow()
    if window then
      window:close()
    end
  end,
  -- U: screenshot a selection and share it.
  [key.u] = start_screenshot_share,
}

-- Cmd+Option: snapping, on the same keys as focus.
local cmd_key_actions = {
  [key.h] = snap(hs.layout.left50),
  [key.l] = snap(hs.layout.right50),
  [key.k] = snap(hs.layout.maximized),
  [key.j] = snap({ x = 1 / 6, y = 1 / 8, w = 2 / 3, h = 3 / 4 }),
}

for _, k in ipairs({ "1", "2", "3", "4", "5" }) do
  cmd_key_actions[key[k]] = key_actions[key[k]]
end

-- While Spaceman (tiling window manager) runs, it owns Opt+1-9/0 (workspaces) and
-- Opt+H/J/K/L (focus); Hammerspoon passes them through and skips its snapping.
local spaceman_keys = {
  [key["1"]] = true, [key["2"]] = true, [key["3"]] = true, [key["4"]] = true, [key["5"]] = true,
  [key.h] = true, [key.j] = true, [key.k] = true, [key.l] = true,
}
local function spaceman_running()
  return hs.application.get("anomaly.spaceman") ~= nil
end

local function has_opt_cmd(flags)
  return flags.alt and flags.cmd and not flags.ctrl and not flags.shift and not flags.fn
end

app_shortcuts_tap = hs.eventtap
  .new({ hs.eventtap.event.types.keyDown }, function(event)
    local flags = event:getFlags()
    local action

    local code = event:getKeyCode()
    if has_only_opt(flags) then
      if spaceman_keys[code] and spaceman_running() then
        return false
      end
      action = key_actions[code]
    elseif has_opt_cmd(flags) then
      if code == key.h or code == key.j or code == key.k or code == key.l then
        if spaceman_running() then
          return false
        end
      end
      action = cmd_key_actions[code]
    end

    if not action then
      return false
    end

    action()
    return true
  end)
app_shortcuts_tap:start()

hs.window.animationDuration = 0

-- Natural scrolling is on system-wide (for the trackpad); LinearMouse reverses
-- the mouse wheel. See linearmouse/linearmouse.json.

hs.alert.show("Hammerspoon config loaded")
