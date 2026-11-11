-- Opt out of Omarchy's per-monitor workspaces (default/hypr/monitor-workspaces.lua),
-- which gives every monitor its own block of ten and reshuffles workspaces on
-- every monitor plug/unplug. Omarchy has no switch for it, so this stands in
-- for that module before the defaults load: same o.workspaces API, plain global
-- Hyprland workspaces 1-10, and no monitor.added/removed handlers.
--
-- Must be required before default.hypr.omarchy. To get the stock behaviour
-- back, remove that require line from hyprland.lua.

require("default.hypr.helpers")

local M = { slots = 10 }

-- Keeps the keybindings menu able to replay these binds.
local function action(fn, expression)
  o.bind_expressions[fn] = expression
  return fn
end

function M.workspace_id(_, slot)
  return slot
end

function M.focus(slot)
  return action(function()
    hl.dispatch(hl.dsp.focus({ workspace = tostring(slot) }))
  end, "o.workspaces.focus(" .. slot .. ")")
end

function M.move_window(slot, follow)
  return action(function()
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(slot), follow = follow ~= false }))
  end, "o.workspaces.move_window(" .. slot .. (follow == false and ", false" or "") .. ")")
end

function M.move_to_monitor(direction)
  return action(function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
    end
  end, string.format("o.workspaces.move_to_monitor(%q)", direction))
end

function M.move_window_to_monitor(direction)
  return action(function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.window.move({ monitor = target.name }))
    end
  end, string.format("o.workspaces.move_window_to_monitor(%q)", direction))
end

function M.reconcile() end

o.workspaces = M
package.loaded["default.hypr.monitor-workspaces"] = M

return M
