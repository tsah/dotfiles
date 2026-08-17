-- External 1080p display to the left of the laptop panel.

hl.env("GDK_SCALE", "1")

-- Current and previously used Dell P2419H displays.
hl.monitor({ output = "desc:Dell Inc. DELL P2419H 87V1Y02S3ALB", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.monitor({ output = "desc:Dell Inc. DELL P2419H BTW82Y2", mode = "1920x1080@60", position = "0x0", scale = 1 })

-- Alternate Samsung external display.
hl.monitor({ output = "desc:Samsung Electric Company LF27T35", mode = "1920x1080@60", position = "0x0", scale = 1 })

hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "1920x0", scale = 1 })
