-- ~/.config/hypr/binds.lua
-- Raccourcis clavier (Disposition AZERTY par défaut + Quickshell / Rofi / Hyprquickpaper)

local mainMod = "SUPER"

--: Système & Fenêtres
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "fermer la fenêtre" })
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "terminal" })
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "fenêtre flottante" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "plein écran" })
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "maximiser" })

--: Applications
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(music_player), { description = "musique" })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser1), { description = "navigateur" })
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(browser2), { description = "navigateur secondaire" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(file_explorer), { description = "fichiers" })

--: Lanceur & panneau
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("quickshell ipc call shell toggleSpotlight"), { description = "lanceur" })
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("quickshell ipc call shell toggleConfig"), { description = "panneau de réglages" })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("quickshell -n -p ~/.config/quickshell/hyprquickpaper"), { description = "fond d'écran" })
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("quickshell ipc call shell toggleCheatsheet"), { description = "raccourcis" })

-- Sortie de l'aperçu plein écran du greeter (fenêtre de test SDDM). Le mode
-- test n'a aucun socket d'authentification et n'obéit pas à Qt.quit() : la
-- fenêtre est plein écran et avale le clavier, donc Échap est traité par le
-- compositeur. non_consuming : Échap continue d'atteindre la fenêtre focalisée,
-- l'utilisateur garde son Échap habituel dans les autres applications.
hl.bind("Escape", hl.dsp.exec_cmd("$HOME/.config/quickshell/core/greeter_preview.sh stop"),
        { non_consuming = true, description = "fermer l'aperçu du greeter" })

--: Capture
-- Sélection de zone ou de fenêtre, presse-papier et fichier.
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("$HOME/.config/quickshell/core/screenshot.sh"), { description = "capture d'écran" })

--: Focus
-- Déplacement du focus avec SUPER + Flèches.
hl.bind(mainMod .. " + Left",  hl.dsp.focus({ direction = "left" }), { description = "focus à gauche" })
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }), { description = "focus à droite" })
hl.bind(mainMod .. " + Up",    hl.dsp.focus({ direction = "up" }), { description = "focus en haut" })
hl.bind(mainMod .. " + Down",  hl.dsp.focus({ direction = "down" }), { description = "focus en bas" })

--: Fenêtres
-- Échange de la fenêtre active avec sa voisine (SUPER + CTRL + Flèches).
-- swap échange les positions sur le MÊME workspace (pas de changement de workspace).
hl.bind(mainMod .. " + CTRL + Left",  hl.dsp.window.swap({ direction = "l" }), { description = "échanger avec la gauche" })
hl.bind(mainMod .. " + CTRL + Right", hl.dsp.window.swap({ direction = "r" }), { description = "échanger avec la droite" })
hl.bind(mainMod .. " + CTRL + Up",    hl.dsp.window.swap({ direction = "u" }), { description = "échanger avec le haut" })
hl.bind(mainMod .. " + CTRL + Down",  hl.dsp.window.swap({ direction = "d" }), { description = "échanger avec le bas" })

--: Fenêtres
-- Redimensionnement (SUPER + SHIFT + Flèches).
-- relative = true est OBLIGATOIRE : sans lui, x/y sont interprétés comme une
-- taille absolue (d'où l'erreur « invalid size » à chaque appui).
-- Le pas est lu dans core/style_vars.json ("resize_step"), modifiable depuis
-- le panneau (Aspect technique). config_manager.py déclenche un `hyprctl reload`
-- après modification, ce qui réévalue ce fichier avec la nouvelle valeur.
local function read_resize_step()
    local p = os.getenv("HOME") .. "/.config/quickshell/core/style_vars.json"
    local f = io.open(p, "r")
    if not f then return 15 end
    local s = f:read("*a")
    f:close()
    local n = s and s:match('"resize_step"%s*:%s*(%d+)')
    local v = tonumber(n)
    if not v or v < 1 or v > 200 then return 15 end
    return v
end
local RESIZE_STEP = read_resize_step()

hl.bind(mainMod .. " + SHIFT + Left",  hl.dsp.window.resize({ x = -RESIZE_STEP, y = 0, relative = true }), { repeating = true }, { description = "rétrécir" })
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.resize({ x = RESIZE_STEP,  y = 0, relative = true }), { repeating = true }, { description = "élargir" })
hl.bind(mainMod .. " + SHIFT + Up",    hl.dsp.window.resize({ x = 0,   y = -RESIZE_STEP, relative = true }), { repeating = true }, { description = "baisser" })
hl.bind(mainMod .. " + SHIFT + Down",  hl.dsp.window.resize({ x = 0,   y = RESIZE_STEP, relative = true }), { repeating = true }, { description = "rehausser" })

--: Souris
-- Déplacement et redimensionnement à la souris, molette pour changer de workspace.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })


--: Média
-- Touches multimédia audio.
-- Chaque touche règle le volume puis affiche l'OSD Quickshell via core/osd.sh
local osd = "$HOME/.config/quickshell/core/osd.sh"
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ && " .. osd .. " volume"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && " .. osd .. " volume"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && " .. osd .. " volume"),        { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && " .. osd .. " mic"),         { locked = true, repeating = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),                                   { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"),                             { locked = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"),                             { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),                               { locked = true })

--: Workspaces
-- Workspaces permanents 1 à 5 (AZERTY).
-- Workspace 1 (& / 1)
hl.bind(mainMod .. " + ampersand",        hl.dsp.focus({ workspace = 1 }), { description = "workspace 1" })
hl.bind(mainMod .. " + CTRL + ampersand", hl.dsp.window.move({ workspace = 1, silent = true }))
hl.bind(mainMod .. " + ALT + ampersand",  hl.dsp.window.move({ workspace = 1 }))

-- Workspace 2 (é / 2)
hl.bind(mainMod .. " + eacute",        hl.dsp.focus({ workspace = 2 }), { description = "workspace 2" })
hl.bind(mainMod .. " + CTRL + eacute", hl.dsp.window.move({ workspace = 2, silent = true }))
hl.bind(mainMod .. " + ALT + eacute",  hl.dsp.window.move({ workspace = 2 }))

-- Workspace 3 (" / 3)
hl.bind(mainMod .. " + quotedbl",        hl.dsp.focus({ workspace = 3 }), { description = "workspace 3" })
hl.bind(mainMod .. " + CTRL + quotedbl", hl.dsp.window.move({ workspace = 3, silent = true }))
hl.bind(mainMod .. " + ALT + quotedbl",  hl.dsp.window.move({ workspace = 3 }))

-- Workspace 4 (' / 4)
hl.bind(mainMod .. " + apostrophe",        hl.dsp.focus({ workspace = 4 }), { description = "workspace 4" })
hl.bind(mainMod .. " + CTRL + apostrophe", hl.dsp.window.move({ workspace = 4, silent = true }))
hl.bind(mainMod .. " + ALT + apostrophe",  hl.dsp.window.move({ workspace = 4 }))

-- Workspace 5 (( / 5)
hl.bind(mainMod .. " + parenleft",        hl.dsp.focus({ workspace = 5 }), { description = "workspace 5" })
hl.bind(mainMod .. " + CTRL + parenleft", hl.dsp.window.move({ workspace = 5, silent = true }))
hl.bind(mainMod .. " + ALT + parenleft",  hl.dsp.window.move({ workspace = 5 }))

--: Workspaces
-- Workspaces dynamiques 6 à 10.
-- Workspace 6 (- / 6)
hl.bind(mainMod .. " + minus",        hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + CTRL + minus", hl.dsp.window.move({ workspace = 6, silent = true }))
hl.bind(mainMod .. " + ALT + minus",  hl.dsp.window.move({ workspace = 6 }))

-- Workspace 7 (è / 7)
hl.bind(mainMod .. " + egrave",        hl.dsp.focus({ workspace = 7 }))
hl.bind(mainMod .. " + CTRL + egrave", hl.dsp.window.move({ workspace = 7, silent = true }))
hl.bind(mainMod .. " + ALT + egrave",  hl.dsp.window.move({ workspace = 7 }))

-- Workspace 8 (_ / 8)
hl.bind(mainMod .. " + underscore",        hl.dsp.focus({ workspace = 8 }))
hl.bind(mainMod .. " + CTRL + underscore", hl.dsp.window.move({ workspace = 8, silent = true }))
hl.bind(mainMod .. " + ALT + underscore",  hl.dsp.window.move({ workspace = 8 }))

-- Workspace 9 (ç / 9)
hl.bind(mainMod .. " + ccedilla",        hl.dsp.focus({ workspace = 9 }))
hl.bind(mainMod .. " + CTRL + ccedilla", hl.dsp.window.move({ workspace = 9, silent = true }))
hl.bind(mainMod .. " + ALT + ccedilla",  hl.dsp.window.move({ workspace = 9 }))

-- Workspace 10 (à / 0)
hl.bind(mainMod .. " + agrave",        hl.dsp.focus({ workspace = 10 }))
hl.bind(mainMod .. " + CTRL + agrave", hl.dsp.window.move({ workspace = 10, silent = true }))
hl.bind(mainMod .. " + ALT + agrave",  hl.dsp.window.move({ workspace = 10 }))
