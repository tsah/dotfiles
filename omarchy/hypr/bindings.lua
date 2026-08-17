-- Personal keybindings migrated from the pre-Quattro Hyprland configuration.
-- Omarchy defaults load first, so every customized chord is unbound before use.

local function rebind(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

-- Terminals and launchers.
rebind("SUPER + ALT + RETURN", "Tmux", "uwsm-app -- xdg-terminal-exec --dir=\"$(omarchy-cmd-terminal-cwd)\" tmux new")
rebind("CTRL + ALT + T", "Terminal with tmux", "uwsm-app -- ghostty -e tmux new-session")
rebind("CTRL + ALT + RETURN", "Terminal without tmux", "uwsm-app -- ghostty")
rebind("CTRL + ALT + B", "Launch work browser", "uwsm-app -- /home/tsah/dotfiles/bin/browser-work")
rebind("CTRL + ALT + P", "Launch personal browser", "uwsm-app -- /home/tsah/dotfiles/bin/browser-personal")
rebind("CTRL + ALT + S", "Launch Slack", "~/dotfiles/omarchy/hypr/launch-slack-group")
rebind("CTRL + ALT + N", "Open nvim in Work vault", [[uwsm-app -- ghostty -e bash -c "cd ~/Dropbox/tsahs-vault/Work && nvim"]])
rebind("CTRL + ALT + D", "Lazydocker", "uwsm-app -- ghostty -e lazydocker")
rebind("SUPER + ALT + B", "Temporary browser", "uwsm-app -- chromium --temp-profile")
rebind("SUPER + U", "Bluetooth", "omarchy-shell shell toggle omarchy.bluetooth")
rebind("SUPER + I", "Network", "omarchy-shell shell toggle omarchy.network")
rebind("SUPER + ALT + ESCAPE", "Lock screen", "omarchy-system-lock")
rebind("SUPER + ALT + X", "Suspend", "systemctl suspend")
rebind("SUPER + E", "File manager", "uwsm-app -- nautilus --new-window")

-- Dedicated workspace navigation.
rebind("SUPER + T", "Go to terminal workspace", hl.dsp.focus({ workspace = "1" }))
rebind("SUPER + B", "Go to browser workspace", hl.dsp.focus({ workspace = "2" }))
rebind("SUPER + S", "Go to Slack workspace", hl.dsp.focus({ workspace = "3" }))
rebind("SUPER + P", "Go to personal workspace", hl.dsp.focus({ workspace = "4" }))
rebind("SUPER + N", "Go to notes workspace", hl.dsp.focus({ workspace = "5" }))

-- Window management.
rebind("SUPER + Q", "Close window", hl.dsp.window.close())
rebind("SUPER + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
rebind("SUPER + ALT + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
rebind("SUPER + ALT + Z", "Maximize tile", hl.dsp.window.pseudo())
rebind("SUPER + ALT + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
rebind("SUPER + ALT + D", "Dismiss notification", "omarchy-shell notifications dismissOne")
rebind("SUPER + CTRL + ALT + D", "Invoke notification", "omarchy-shell notifications invokeLast")
rebind("SUPER + ALT + R", "Reload Hyprland config", "hyprctl reload")
rebind("SUPER + ALT + M", "Move workspace to next monitor", "~/dotfiles/omarchy/hypr/move-workspace-to-next-monitor")
rebind("SUPER + ALT + SEMICOLON", "Toggle window split", hl.dsp.layout("togglesplit"))
rebind("SUPER + ALT + P", "Pseudo window", hl.dsp.window.pseudo())

-- Group controls on the home row.
rebind("SUPER + ALT + H", "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
rebind("SUPER + ALT + L", "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
rebind("SUPER + ALT + K", "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
rebind("SUPER + ALT + J", "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))
rebind("SUPER + CTRL + ALT + H", "Previous window in group", hl.dsp.group.prev())
rebind("SUPER + CTRL + ALT + L", "Next window in group", hl.dsp.group.next())
rebind("SUPER + SHIFT + G", "Group or ungroup workspace", "~/dotfiles/omarchy/hypr/toggle-group-workspace")

-- Scratchpad.
rebind("SUPER + W", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
rebind("SUPER + ALT + W", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

-- Focus and workspace movement.
rebind("SUPER + H", "Focus left or previous workspace", "~/dotfiles/omarchy/hypr/focus-left-or-workspace")
rebind("SUPER + L", "Focus right or next workspace", "~/dotfiles/omarchy/hypr/focus-right-or-workspace")
rebind("SUPER + K", "Focus up", hl.dsp.focus({ direction = "u" }))
rebind("SUPER + J", "Focus down", hl.dsp.focus({ direction = "d" }))
rebind("SUPER + SHIFT + H", "Previous workspace", hl.dsp.focus({ workspace = "-1" }))
rebind("SUPER + SHIFT + L", "Next workspace", hl.dsp.focus({ workspace = "+1" }))
rebind("SUPER + CTRL + K", "Move window up", hl.dsp.window.move({ direction = "u" }))
rebind("SUPER + CTRL + J", "Move window down", hl.dsp.window.move({ direction = "d" }))
rebind("SUPER + CTRL + SHIFT + H", "Move to previous workspace", hl.dsp.window.move({ workspace = "-1" }))
rebind("SUPER + CTRL + SHIFT + L", "Move to next workspace", hl.dsp.window.move({ workspace = "+1" }))

-- Send windows to dedicated workspaces.
rebind("SUPER + SHIFT + T", "Send to terminal workspace", hl.dsp.window.move({ workspace = "1" }))
rebind("SUPER + SHIFT + B", "Send to browser workspace", hl.dsp.window.move({ workspace = "2" }))
rebind("SUPER + SHIFT + S", "Send to Slack workspace", hl.dsp.window.move({ workspace = "3" }))
rebind("SUPER + SHIFT + P", "Send to personal workspace", hl.dsp.window.move({ workspace = "4" }))
rebind("SUPER + SHIFT + N", "Send to notes workspace", hl.dsp.window.move({ workspace = "5" }))
rebind("SUPER + SHIFT + E", "Send to empty workspace", "~/dotfiles/omarchy/hypr/send-window-to-empty-workspace")

-- Monitor operations.
rebind("SUPER + ALT + O", "Pop window out", "omarchy-hyprland-window-pop")
rebind("SUPER + CTRL + M", "Focus next monitor", hl.dsp.focus({ monitor = "+1" }))
rebind("SUPER + M", "Move window to next monitor", hl.dsp.window.move({ monitor = "+1" }))
rebind("SUPER + CTRL + ALT + M", "Toggle laptop display", "omarchy-hyprland-monitor-internal toggle", { locked = true })

-- Clipboard and screenshots.
rebind("SUPER + ALT + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
rebind("SUPER + CTRL + V", "Paste clipboard text", "~/dotfiles/bin/paste-clipboard-text")
rebind("SUPER + O", "Open clipboard item", [[sh -c 'clip=$(wl-paste -n); [ -n "$clip" ] && xdg-open "$clip"']])
rebind("PRINT", "Screenshot destination menu", "~/dotfiles/bin/omarchy-screenshot-share")

-- Resize windows.
rebind("SUPER + ALT + LEFT", "Resize left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
rebind("SUPER + ALT + RIGHT", "Resize right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
rebind("SUPER + ALT + DOWN", "Resize down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
rebind("SUPER + ALT + UP", "Resize up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))

-- Omarchy utilities moved away from conflicting defaults.
hl.unbind("SUPER + code:61")
rebind("SUPER + SLASH", "Show keybindings", "omarchy-menu-keybindings")
rebind("SUPER + BACKSLASH", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
rebind("SUPER + GRAVE", "Cycle monitor scaling", "~/dotfiles/omarchy/hypr/cycle-monitor-scaling")

-- Dictation and cloud agents.
rebind("SUPER + D", "Toggle dictation", "voxtype record toggle")
rebind("SUPER + ALT + A", "Launch cloud agent", "uwsm-app -- ghostty -e ~/dotfiles/bin/cloud-agent-launcher")
