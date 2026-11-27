-- "Rex Nvim": opens double-clicked text files in Neovim inside Rex.
-- The work is in bin/rex-open-file; macos/build-rex-nvim.sh builds this app and
-- makes it the default for text files.
on open theFiles
	set args to ""
	repeat with f in theFiles
		set args to args & " " & quoted form of (POSIX path of f)
	end repeat
	-- Activate first: the script then raises or opens the window to use.
	tell application id "com.superlogical.rex" to activate
	do shell script quoted form of (POSIX path of (path to home folder) & "dotfiles/bin/rex-open-file") & args
end open

on run
	tell application id "com.superlogical.rex" to activate
end run
