-- Matériel : Lenovo Yoga 720-15IKB (portable)

-- Moniteurs (Laptop eDP-1 + TV externe DP-1 configurée en 60Hz)
hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = 1, bitdepth = 10 })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "1920x0", scale = 1 })

-- Workspaces assignés à l'écran principal (DP-1)
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, persistent = true, default_name = "一" })
hl.workspace_rule({ workspace = "2", monitor = "DP-1", persistent = true, default_name = "二" })
hl.workspace_rule({ workspace = "3", monitor = "DP-1", persistent = true, default_name = "三" })
hl.workspace_rule({ workspace = "4", monitor = "DP-1", persistent = true, default_name = "四" })
hl.workspace_rule({ workspace = "5", monitor = "DP-1", persistent = true, default_name = "五" })

--Touches de luminosité écran interne (Laptop uniquement) + OSD Quickshell
local osd = "$HOME/.config/quickshell/core/osd.sh"
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+ && " .. osd .. " brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%- && " .. osd .. " brightness"), { locked = true, repeating = true })

-- Gestion du mode dock (Lid Switch)
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("hyprctl eval 'hl.monitor({ output = \"eDP-1\", disabled = true })'"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl eval 'hl.monitor({ output = \"eDP-1\", disabled = false, mode = \"preferred\", position = \"auto\", scale = 1, transform = 0 })'"), { locked = true })

-- Bascule manuelle du Dock
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("~/.config/hypr/toggle_dock.sh"))

-- Mode tablette : daemon d'orientation (iio-sensor-proxy / monitor-sensor), Portable uniquement.
-- Lancé uniquement au démarrage de Hyprland (pas à chaque reload) et jamais en double.
hl.on("hyprland.start", function ()
    hl.exec_cmd("sh -c 'pgrep -f \"[t]ablet_mode_daemon.py\" >/dev/null || exec python3 \"$HOME/.config/quickshell/core/tablet_mode_daemon.py\" daemon' &")
end)
