-- ~/.config/hypr/exec.lua
-- Autostart & Variables d'environnement (Compatible Arch Linux & Fedora)
--
-- L'autostart est géré depuis le panneau de configuration :
--   core/autostart.json (dev) -> autostart_cmds.txt (généré, lu ci-dessous)
-- Ne pas éditer autostart_cmds.txt à la main.
--
-- NOTE: on utilise un timer one-shot plutôt que hl.on("hyprland.start") :
-- sur Hyprland 0.57.0 l'événement hyprland.start n'est pas émis de façon
-- fiable, alors que hl.timer fonctionne. Le timer ne se déclenche qu'une
-- fois au chargement du fichier (donc au démarrage de session), pas au
-- hyprctl reload (qui re-exécute le fichier mais le timer est déjà passé).

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

local function get_marker_path()
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default"
    local run_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    return run_dir .. "/hypr_autostart_" .. sig
end

local function run_autostart_file()
    -- Ne s'exécute qu'une seule fois par session Hyprland.
    -- Évite de relancer l'autostart (et de dupliquer quickshell) lors des
    -- rechargements de configuration déclenchés par Matugen / colors.lua.
    local marker = get_marker_path()
    local mf = io.open(marker, "r")
    if mf then
        mf:close()
        return
    end

    local wf = io.open(marker, "w")
    if wf then
        wf:write(tostring(os.time()))
        wf:close()
    end

    local path = os.getenv("HOME") .. "/.config/hypr/autostart_cmds.txt"
    local f = io.open(path, "r")
    if not f then
        return
    end
    for line in f:lines() do
        local cmd = line:match("^%s*(.-)%s*$")
        if cmd ~= "" and cmd:sub(1, 1) ~= "#" then
            hl.exec_cmd(cmd)
        end
    end
    f:close()
end

-- Timer one-shot de 1s : laisse le compositor finir de démarrer,
-- puis exécute l'autostart une seule fois.
local t = hl.timer(function()
    run_autostart_file()
end, { timeout = 1000, type = "oneshot" })
t:set_enabled(true)
