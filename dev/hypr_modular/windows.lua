-- ~/.config/hypr/windows.lua
-- Règles de fenêtres, Workspaces permanents & Exceptions d'opacité (1.0)

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

-- Workspaces permanents 1 à 5
hl.workspace_rule({ workspace = "1", persistent = true, default_name = "一" })
hl.workspace_rule({ workspace = "2", persistent = true, default_name = "二" })
hl.workspace_rule({ workspace = "3", persistent = true, default_name = "三" })
hl.workspace_rule({ workspace = "4", persistent = true, default_name = "四" })
hl.workspace_rule({ workspace = "5", persistent = true, default_name = "五" })

hl.window_rule({ name = "firefox", match = { class = "^(firefox|Firefox)$" }, workspace = "2" })
hl.window_rule({ name = "pavucontrol", float = true, center = true })

-- Exceptions d'opacité (1.0) et inhibition de mise en veille (Firefox, OnlyOffice, Vidéo)
-- API Lua : hl.window_rule({ match = {...}, effect }) — `opaque = true` force l'opacité
-- malgré la transparence globale (decoration.active_opacity / inactive_opacity).
hl.window_rule({ name = "idle-fullscreen", match = { class = ".*", fullscreen = true }, idle_inhibit = "fullscreen" })
hl.window_rule({ name = "idle-firefox", match = { class = "(?i)firefox" }, idle_inhibit = "focus" })

hl.window_rule({ name = "opaque-firefox", match = { class = "(?i)^(firefox|Firefox)$" }, opaque = true })
hl.window_rule({ name = "opaque-zen", match = { class = "(?i)zen" }, opaque = true })
hl.window_rule({ name = "opaque-onlyoffice", match = { class = "(?i).*onlyoffice.*" }, opaque = true })
hl.window_rule({ name = "opaque-video", match = { class = "(?i)(mpv|vlc|totem|celluloid|haruna)" }, opaque = true })
