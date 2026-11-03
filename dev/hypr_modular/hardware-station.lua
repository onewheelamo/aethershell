-- Matériel : Tour PC (Station — Arch Linux + NVIDIA RTX 4070)

-- Variables d'environnement Wayland / NVIDIA
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- Moniteur principal de la tour
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1 })

-- Assignation des Workspaces permanents 1 à 5 sur l'écran de la tour
hl.workspace_rule({ workspace = "1", monitor = "HDMI-A-1", default = true, persistent = true, default_name = "一" })
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1", persistent = true, default_name = "二" })
hl.workspace_rule({ workspace = "3", monitor = "HDMI-A-1", persistent = true, default_name = "三" })
hl.workspace_rule({ workspace = "4", monitor = "HDMI-A-1", persistent = true, default_name = "四" })
hl.workspace_rule({ workspace = "5", monitor = "HDMI-A-1", persistent = true, default_name = "五" })
