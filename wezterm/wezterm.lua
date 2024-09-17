--
-- ██╗    ██╗███████╗███████╗████████╗███████╗██████╗ ███╗   ███╗
-- ██║    ██║██╔════╝╚══███╔╝╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
-- ██║ █╗ ██║█████╗    ███╔╝    ██║   █████╗  ██████╔╝██╔████╔██║
-- ██║███╗██║██╔══╝   ███╔╝     ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║
-- ╚███╔███╔╝███████╗███████╗   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
--  ╚══╝╚══╝ ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
-- A GPU-accelerated cross-platform terminal emulator
-- https://wezfurlong.org/wezterm/

local k = require("utils/keys")
local p = require('projects')
local wezterm = require("wezterm")
local ss = require("smart_splits")
local act = wezterm.action

local config = {

	font_size = 20,
	font = wezterm.font "Hack Nerd Font",
  front_end = 'WebGpu',
  color_scheme = 'Catppuccin Mocha',

	window_padding = {
		left = 30,
		right = 30,
		top = 20,
		bottom = 10,
	},

	-- general options
	adjust_window_size_when_changing_font_size = false,
	debug_key_events = false,
	enable_tab_bar = true,
	native_macos_fullscreen_mode = false,
	window_close_confirmation = "NeverPrompt",
	window_decorations = "RESIZE",

  -- tab bar
  use_fancy_tab_bar = true,
  window_frame = {
    font = wezterm.font { family = "Hack Nerd Font", weight = 'Bold'},
    font_size = 18.0,
  },

	-- keys
  leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 5000 },
	keys = {
    {
      key = 'p',
      mods = 'CMD',
      action = p.choose_project(),
    },
    {
      key = 'v',
      mods = 'LEADER',
      action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'h',
      mods = 'LEADER',
      action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'z',
      mods = 'CTRL',
      action = wezterm.action.TogglePaneZoomState
    },
    { key = 'LeftArrow', mods = 'SHIFT', action = act.ActivateTabRelative(-1) },
    { key = 'RightArrow', mods = 'SHIFT', action = act.ActivateTabRelative(1) },
	},
}

wezterm.on('update-status', function(window)
  -- Grab the utf8 character for the "powerline" left facing
  -- solid arrow.
  local SOLID_LEFT_ARROW = utf8.char(0xe0b2)

  -- Grab the current window's configuration, and from it the
  -- palette (this is the combination of your chosen colour scheme
  -- including any overrides).
  local color_scheme = window:effective_config().resolved_palette
  local bg = color_scheme.background
  local fg = color_scheme.foreground

  window:set_right_status(wezterm.format({
    -- First, we draw the arrow...
    { Background = { Color = 'none' } },
    { Foreground = { Color = bg } },
    { Text = SOLID_LEFT_ARROW },
    -- Then we draw our text
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = ' ' .. wezterm.hostname() .. ' ' },
  }))
end)

ss.apply_mappings(config.keys)

return config
