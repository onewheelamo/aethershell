-- ~/.config/hypr/keybindings.lua
local mainMod = "SUPER"

-- Système
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))

-- Applications
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(music_player))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser1))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(browser2))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(file_explorer))



-- Déplacement du focus (SUPER + Flèches)
hl.bind(mainMod .. " + Left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + Up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + Down", hl.dsp.focus({ direction = "down" }))

-- Redimensionnement des fenêtres (SUPER + SHIFT + Flèches)
hl.bind(mainMod .. " + SHIFT + Left", hl.dsp.window.resize({ x = -30, y = 0 }))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.resize({ x = 30, y = 0 }))
hl.bind(mainMod .. " + SHIFT + Up", hl.dsp.window.resize({ x = 0, y = -30 }))
hl.bind(mainMod .. " + SHIFT + Down", hl.dsp.window.resize({ x = 0, y = 30 }))

-- Gestion des Workspaces (Adaptation AZERTY avec objets hl.dsp)
-- Workspace 1 (ampersand)
hl.bind(mainMod .. " + ampersand", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + ampersand", hl.dsp.window.move({ workspace = 1, silent = true }))
hl.bind(mainMod .. " + ALT + ampersand", hl.dsp.window.move({ workspace = 1 }))

-- Workspace 2 (eacute)
hl.bind(mainMod .. " + eacute", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + eacute", hl.dsp.window.move({ workspace = 2, silent = true }))
hl.bind(mainMod .. " + ALT + eacute", hl.dsp.window.move({ workspace = 2 }))

-- Workspace 3 (quotedbl)
hl.bind(mainMod .. " + quotedbl", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + quotedbl", hl.dsp.window.move({ workspace = 3, silent = true }))
hl.bind(mainMod .. " + ALT + quotedbl", hl.dsp.window.move({ workspace = 3 }))

-- Workspace 4 (apostrophe)
hl.bind(mainMod .. " + apostrophe", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + apostrophe", hl.dsp.window.move({ workspace = 4, silent = true }))
hl.bind(mainMod .. " + ALT + apostrophe", hl.dsp.window.move({ workspace = 4 }))

-- Workspace 5 (leftparen)
hl.bind(mainMod .. " + parenleft", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + SHIFT + parenleft", hl.dsp.window.move({ workspace = 5, silent = true }))
hl.bind(mainMod .. " + ALT + parenleft", hl.dsp.window.move({ workspace = 5 }))

-- Noctalia IPC
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("noctalia msg wallpaper-picker"))

-- Workspaces 6-0 (FR Layout)
bind = $mainMod, minus, workspace, 6
bind = $mainMod, egrave, workspace, 7
bind = $mainMod, underscore, workspace, 8
bind = $mainMod, c_cedilla, workspace, 9
bind = $mainMod, agrave, workspace, 0

bind = $mainMod, H, exec, quickshell -f config_panel.qml
bind = $mainMod, K, exec, quickshell -f shortcuts_list.qml
