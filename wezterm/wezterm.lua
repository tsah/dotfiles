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

local wezterm = require("wezterm")
-- local ss = require("smart_splits")
local act = wezterm.action

local config = {

    enable_wayland=false,
	font_size = 20,
	font = wezterm.font "CaskaydiaMono Nerd Font",
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

	-- keys
}
wezterm.on("user-var-changed", function(window, pane, name, value)
	-- local appearance = window:get_appearance()
	-- local is_dark = appearance:find("Dark")
	local overrides = window:get_config_overrides() or {}
	wezterm.log_info("name", name)
	wezterm.log_info("value", value)

	if name == "T_SESSION" then
		local session = value
		wezterm.log_info("is session", session)
		overrides.background = {
			w.set_tmux_session_wallpaper(value),
			{
				source = {
					Gradient = {
						colors = { "#000000" },
					},
				},
				width = "100%",
				height = "100%",
				opacity = 0.95,
			},
		}
	end

	if name == "ZEN_MODE" then
		local incremental = value:find("+")
		local number_value = tonumber(value)
		if incremental ~= nil then
			while number_value > 0 do
				window:perform_action(wezterm.action.IncreaseFontSize, pane)
				number_value = number_value - 1
			end
		elseif number_value < 0 then
			window:perform_action(wezterm.action.ResetFontSize, pane)
			overrides.font_size = nil
		else
			overrides.font_size = number_value
		end
	end
	if name == "DIFF_VIEW" then
		local incremental = value:find("+")
		local number_value = tonumber(value)
		if incremental ~= nil then
			while number_value > 0 do
				window:perform_action(wezterm.action.DecreaseFontSize, pane)
				number_value = number_value - 1
			end
			-- overrides.background = {
			-- 	w.set_nvim_wallpaper("Diffview.jpeg"),
			--
			-- 	{
			-- 		source = {
			-- 			Gradient = {
			-- 				colors = { "#000000" },
			-- 			},
			-- 		},
			-- 		width = "100%",
			-- 		height = "100%",
			-- 		opacity = 0.95,
			-- 	},
			-- }
		elseif number_value < 0 then
			window:perform_action(wezterm.action.ResetFontSize, pane)
			overrides.background = nil
			overrides.font_size = nil
		else
			overrides.font_size = number_value
		end
	end
	window:set_config_overrides(overrides)
end)

-- ss.apply_mappings(config.keys)

return config
