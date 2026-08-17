-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Load package-managed defaults first, then personal overrides.
require("default.hypr.omarchy")
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.envs")
require("hypr.autostart")
require("default.hypr.toggles")

-- Zoom creates this XWayland helper when another participant annotates a share.
o.window(
  { class = "^zoom$", title = "^annotate_toolbar$" },
  {
    float = true,
    no_initial_focus = true,
    no_focus = true,
    no_anim = true,
  }
)

-- Keep dedicated workspaces on whichever external monitor is connected.
local external_monitor
for _, monitor in ipairs(hl.get_monitors()) do
  if monitor.name ~= "eDP-1" then
    external_monitor = monitor.name
    break
  end
end

if external_monitor then
  for workspace = 1, 5 do
    hl.workspace_rule({ workspace = tostring(workspace), monitor = external_monitor })
  end
end
