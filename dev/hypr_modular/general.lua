-- ~/.config/hypr/general.lua
-- Look and Feel, Gaps, Borders, Opacity (0.85) & Animations

hl.config({
    general = {
        gaps_in  = 2,
        gaps_out = 8,
        border_size = 2,
        col = {
            active_border   = "rgba(b4befeee)",
            inactive_border = "rgba(45475aaa)",
        },
        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding         = 0,
        -- 2 = arc de cercle ; en dessous, Hyprland coupe le coin en droite
        -- (à 1, cela donne un chanfrein au lieu d'un arrondi).
        rounding_power   = 2,
        active_opacity   = 0.85,
        inactive_opacity = 0.85,
        shadow = {
            enabled      = false,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled   = true,            size      = 3,
            passes    = 3,
            vibrancy  = 0.1696,
            -- Les menus (popups GTK) héritent de l'opacité de la fenêtre mais
            -- n'ont aucun flou derrière eux par défaut : le texte du menu se
            -- superpose au contenu net de la fenêtre et devient illisible.
            popups    = true,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = { preserve_split = true },
    master = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },
    misc = { force_default_wallpaper = -1, disable_hyprland_logo = false },
})

-- Flou derrière les surfaces Quickshell (barre, OSD, panneau).
-- Sans ces règles, une surface layer-shell translucide laisse passer le texte
-- des fenêtres net : le flou Kawase ne s'applique qu'aux fenêtres par défaut.
-- ignore_alpha : sans lui, Hyprland floute toute la surface layer (fenêtre
-- plein largeur / plein écran) et pas seulement la capsule visible. Le seuil
-- doit rester sous l'alpha des surfaces du thème (globalOpacity 0.7-0.85).
--
-- Ce bloc est piloté depuis le panneau de configuration (section « Aspect
-- technique du bureau ») : config_manager.py réécrit les trois valeurs entre
-- les marqueurs BEGIN/END puis recharge Hyprland. Ne pas éditer les valeurs à
-- la main, elles seraient écrasées au prochain réglage.
-- BEGIN shell-blur
local shell_blur = {
    enabled = true,  -- flou derrière les surfaces du shell
    alpha   = 0.30,   -- sous ce seuil d'opacité, pas de flou (ignore_alpha)
    popups  = true,  -- flou derrière les popups ancrés (calendrier, wifi…)
}
if shell_blur.enabled then
    for _, ns in ipairs({ "shell-bar", "shell-bar-bas", "shell-bar-cote-gauche", "shell-bar-cote-droite", "shell-osd", "shell-config", "shell-onboarding", "shell-spotlight", "shell-spotlight-rest", "shell-cheatsheet", "shell-tray-menu", "shell-shotbar", "shell-menu-session", "shell-menu-widget", "shell-notif-history" }) do
        hl.layer_rule({
            match        = { namespace = ns },
            blur         = true,
            blur_popups  = shell_blur.popups,
            ignore_alpha = shell_blur.alpha,
        })
    end
end
-- END shell-blur

-- Courbes et animations
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, damping = 15.8273644 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })
