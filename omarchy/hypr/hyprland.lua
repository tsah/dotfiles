-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Global workspaces instead of Omarchy's per-monitor blocks; must come first.
require("hypr.global-workspaces")

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
