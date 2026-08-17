-- Personal keyboard, pointer, and application-specific input settings.

hl.config({
  input = {
    kb_layout = "us,il",
    kb_options = "compose:caps,grp:ctrl_space_toggle",
    repeat_rate = 40,
    repeat_delay = 200,
    numlock_by_default = true,
    scroll_factor = 0.5,
    touchpad = {
      natural_scroll = true,
      scroll_factor = 0.4,
    },
  },
})

hl.device({
  name = "logitech-mx-master-3s",
  scroll_factor = 0.3,
})

-- App-specific touchpad scroll speeds.
o.window("(kitty|foot)", { scroll_touchpad = 1.5 })
o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })
