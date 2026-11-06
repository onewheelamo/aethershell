-- ~/.config/hypr/hyprland.lua
-- Configuration principale Hyprland (modulaire, Arch et Fedora / Quickshell)

-- 1. Programmes par défaut (synchronisés avec core/app_vars.json)
require("programs")

-- 2. Identification et chargement du matériel (par famille de distribution)
--    Le nom de la machine ne sert à rien ici et n'a rien à faire dans un dépôt
--    partagé : ce qui distingue les deux configurations, c'est la distribution et
--    le matériel, pas le nom d'hôte.
local function detect_distro()
    local f = io.open("/etc/os-release", "r")
    if f then
        local ident = ""
        for ligne in f:lines() do
            local id = ligne:match("^ID=(.+)$")
            if id then ident = id:gsub('"', ""):lower() break end
        end
        f:close()
        if ident == "fedora" or ident == "nobara" or ident == "bazzite" then
            return "fedora"
        end
        if ident ~= "" then
            return "arch"
        end
    end
    return nil
end

local distro = detect_distro()
local config_dir = os.getenv("HOME") .. "/.config/hypr/"
local hw_file = distro and (config_dir .. "hardware-" .. distro .. ".lua") or nil

local f = hw_file and io.open(hw_file, "r") or nil
if f then
    f:close()
    dofile(hw_file)
else
    print("Avertissement : configuration matérielle introuvable (" .. tostring(hw_file) .. ")")
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
end

-- 3. Modules de configuration
require("exec")
require("general")
require("colors")
require("input")
require("windows")
require("binds")
