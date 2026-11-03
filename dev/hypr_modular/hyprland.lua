-- ~/.config/hypr/hyprland.lua
-- Configuration principale Hyprland (Modulaire - Station & Portable / Quickshell)

-- 1. Programmes par défaut (synchronisés avec core/app_vars.json)
require("programs")

-- 2. Identification et chargement du matériel (station / portable)
local function detect_hostname()
    local f_host = io.open("/etc/hostname", "r")
    if f_host then
        local h = f_host:read("*a")
        f_host:close()
        if h and h ~= "" then
            return h:gsub("%s+", ""):lower()
        end
    end
    local handle = io.popen("uname -n 2>/dev/null || hostname 2>/dev/null")
    if handle then
        local h = handle:read("*a")
        handle:close()
        if h and h ~= "" then
            return h:gsub("%s+", ""):lower()
        end
    end
    return "station"
end

local host = detect_hostname()
local config_dir = os.getenv("HOME") .. "/.config/hypr/"
local hw_file = config_dir .. "hardware-" .. host .. ".lua"

local f = io.open(hw_file, "r")
if f then
    f:close()
    dofile(hw_file)
else
    print("Avertissement : Fichier matériel introuvable pour " .. host .. " (" .. hw_file .. ")")
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
end

-- 3. Modules de configuration
require("exec")
require("general")
require("colors")
require("input")
require("windows")
require("binds")
