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


hl.window_rule({ name = "pavucontrol", float = true, center = true })
hl.window_rule({
    name   = "floating-terminal",
    match  = { class = "^org\\.aether\\.floating-terminal$" },
    float  = true,
    center = true,
})

-- Fond animé Matrix (`as matrix`) : plein écran sans bordures, épinglé et sans
-- focus, dans la couche fenêtre normale (derrière les surfaces Quickshell).
hl.window_rule({
    name       = "matrix-wallpaper-bg",
    match      = { class = "^org\\.aether\\.matrix-bg$" },
    float      = true,
    move       = "0 0",
    size       = "100% 100%",
    pin        = true,
    border_size = 0,
    rounding   = 0,
    no_shadow  = true,
    no_anim    = true,
    no_focus   = true,
})

-- Écran de veille Matrix (`as matrix [délai] ss`) : plein écran total devant
-- toutes les surfaces, focus forcé pour quitter dès la première touche.
hl.window_rule({
    name         = "matrix-screensaver",
    match        = { class = "^org\\.aether\\.matrix-ss$" },
    float        = true,
    fullscreen   = true,
    stay_focused = true,
    pin          = true,
    border_size  = 0,
    rounding     = 0,
    no_anim      = true,
    idle_inhibit = "fullscreen",
})

-- Demande d'authentification polkit (KDE, Hypr, LXQt) : flottante, centrée,
-- épinglée et avec focus forcé.
hl.window_rule({
    name         = "polkit-prompt",
    match        = { class = "(?i).*(polkit|policykit).*" },
    float        = true,
    center       = true,
    stay_focused = true,
    pin          = true,
    dim_around   = true,
})

-- Aperçu du greeter SDDM : toujours sur le workspace dédié 99
-- pour ne jamais masquer ni immobiliser le workspace de travail courant.
hl.window_rule({
    name      = "greeter-preview-ws",
    match     = { class = "(?i).*sddm-greeter.*" },
    workspace = 99,
})

-- Exceptions d'opacité (1.0) et inhibition de mise en veille (Firefox, OnlyOffice, Vidéo)
-- API Lua : hl.window_rule({ match = {...}, effect }) — `opaque = true` met
-- active/inactive/fullscreen_opacity à 1 pour la fenêtre, `opacity = "1.0 override"`
-- force l'alpha de façon absolue. Les deux, pour ne pas dépendre d'un seul mécanisme.

hl.window_rule({ name = "idle-fullscreen", match = { class = ".*", fullscreen = true }, idle_inhibit = "fullscreen" })
hl.window_rule({ name = "idle-firefox", match = { class = "(?i).*firefox.*" }, idle_inhibit = "focus" })

hl.window_rule({ name = "opaque-firefox", match = { class = "(?i).*firefox.*" }, opaque = true, opacity = "1.0 override" })
hl.window_rule({ name = "opaque-zen", match = { class = "(?i).*zen.*" }, opaque = true, opacity = "1.0 override" })
hl.window_rule({ name = "opaque-onlyoffice", match = { class = "(?i).*onlyoffice.*" }, opaque = true, opacity = "1.0 override", no_blur = true, no_shadow = true })
hl.window_rule({ name = "opaque-video", match = { class = "(?i).*(mpv|vlc|totem|celluloid|haruna).*" }, opaque = true, opacity = "1.0 override" })
