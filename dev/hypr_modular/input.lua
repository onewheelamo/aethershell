-- ~/.config/hypr/input.lua
-- Clavier AZERTY (fr), Touchpad & Gestes

hl.config({
    input = {
        kb_layout          = "fr",
        numlock_by_default = true,
        follow_mouse       = 2,
        sensitivity        = 0,
        touchpad           = { natural_scroll = true },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })
