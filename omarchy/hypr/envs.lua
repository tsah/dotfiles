-- Personal environment variables.

hl.env("EDITOR", "nvim")
hl.env("VISUAL", "nvim")
hl.env("PATH", "/home/tsah/nvim-linux-x86_64/bin:" .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin"))
