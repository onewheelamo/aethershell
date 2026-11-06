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

-- Workspaces permanents 1 à 5 : assignés par hardware-<host>.lua à l'écran principal
-- (évite de réécraser la contrainte de moniteur définie par le profil matériel)

-- Firefox n'a pas de workspace assigné : il s'ouvre sur le bureau actif, comme
-- n'importe quelle fenêtre. Une règle `workspace = "2"` l'y envoyait à chaque
-- lancement, y compris quand on travaillait ailleurs.
hl.window_rule({ name = "pavucontrol", float = true, center = true })

-- Demande d'authentification polkit : flottante, centrée, et qui garde le
-- focus. Sans `stay_focused`, la fenêtre s'ouvre parfois derrière le
-- navigateur et l'authentification reste bloquée sans qu'on la voie.
hl.window_rule({ name = "polkit-prompt", match = { class = "(?i).*polkit.*" }, float = true, center = true, stay_focused = true })

-- Exceptions d'opacité (1.0) et inhibition de mise en veille (Firefox, OnlyOffice, Vidéo)
-- API Lua : hl.window_rule({ match = {...}, effect }) — `opaque = true` met
-- active/inactive/fullscreen_opacity à 1 pour la fenêtre, `opacity = "1.0 override"`
-- force l'alpha de façon absolue. Les deux, pour ne pas dépendre d'un seul mécanisme.
-- Deux pièges qui se cumulent, mesurés sur portable :
--   1. la classe est comparée en **match complet** (pas une recherche) : « firefox »
--      ne matche pas « org.mozilla.firefox », il faut `.*firefox.*` ;
--   2. Firefox natif Wayland se déclare `org.mozilla.firefox` alors qu'en XWayland
--      il se déclare `firefox` — une règle écrite sur une machine ne matchait rien
--      sur l'autre, et la fenêtre ne redevenait opaque qu'en plein écran
--      (decoration.fullscreen_opacity = 1).
hl.window_rule({ name = "idle-fullscreen", match = { class = ".*", fullscreen = true }, idle_inhibit = "fullscreen" })
hl.window_rule({ name = "idle-firefox", match = { class = "(?i).*firefox.*" }, idle_inhibit = "focus" })

hl.window_rule({ name = "opaque-firefox", match = { class = "(?i).*firefox.*" }, opaque = true, opacity = "1.0 override" })
hl.window_rule({ name = "opaque-zen", match = { class = "(?i).*zen.*" }, opaque = true, opacity = "1.0 override" })
hl.window_rule({ name = "opaque-onlyoffice", match = { class = "(?i).*onlyoffice.*" }, opaque = true, opacity = "1.0 override" })
hl.window_rule({ name = "opaque-video", match = { class = "(?i).*(mpv|vlc|totem|celluloid|haruna).*" }, opaque = true, opacity = "1.0 override" })
