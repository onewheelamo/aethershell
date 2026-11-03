import QtQuick

// ────────────────────────────────────────────────────────────────────────────
// ICON.QML — jeu d'icônes unique et monochrome
// ────────────────────────────────────────────────────────────────────────────
// Material Design Icons (via Nerd Font) : même famille, même poids, même grille
// optique pour toute l'interface. Remplace les emoji, dont la couleur, la
// métrique et la ligne de base sont imposées par la fonte système.
//
//   Icon { glyph: "wifi"; size: Theme.iconSm }
//   Icon { glyph: "close"; color: Theme.error; opacityLevel: 1 }
//
// Le code de chaque glyphe vient de nerd-fonts/glyphnames.json (préfixe md-),
// vérifié présent dans 0xProto Nerd Font. Ne pas écrire d'emoji dans le shell.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string glyph: ""
    property real size: Theme.iconSm
    property color color: Theme.fg
    property real opacityLevel: 0.78

    implicitWidth: Math.ceil(size)
    implicitHeight: Math.ceil(size)

    Text {
        anchors.centerIn: parent
        text: root.glyphs[root.glyph] || ""
        font.family: Theme.fontIcon
        font.pixelSize: Math.round(root.size)
        color: root.color
        opacity: root.opacityLevel
        renderType: Text.NativeRendering
    }

    readonly property var glyphs: ({
        "cog": "\u{F0493}",
        "close": "\u{F0156}",
        "check": "\u{F012C}",
        "chevron-up": "\u{F0143}",
        "chevron-down": "\u{F0140}",
        "chevron-left": "\u{F0141}",
        "chevron-right": "\u{F0142}",
        "more": "\u{F01D8}",
        "plus": "\u{F0415}",
        "minus": "\u{F0374}",
        "search": "\u{F0349}",
        "monitor": "\u{F0379}",
        "laptop": "\u{F0322}",
        "television": "\u{F07F4}",
        "tablet": "\u{F04F6}",
        "phone": "\u{F011C}",
        "memory": "\u{F035B}",
        "battery": "\u{F0079}",
        "power": "\u{F0425}",
        "restart": "\u{F0709}",
        "sleep": "\u{F0904}",
        "lock": "\u{F033E}",
        "logout": "\u{F0343}",
        "download": "\u{F01DA}",
        "rocket": "\u{F14DE}",
        "wifi": "\u{F05A9}",
        "bluetooth": "\u{F00AF}",
        "volume": "\u{F057E}",
        "mute": "\u{F075F}",
        "brightness": "\u{F00DF}",
        "headphones": "\u{F02CB}",
        "keyboard": "\u{F030C}",
        "clock": "\u{F0150}",
        "calendar": "\u{F00ED}",
        "map-marker": "\u{F034E}",
        "weather-night": "\u{F0594}",
        "weather-cloud": "\u{F0595}",
        "sun": "\u{F05A8}",
        "play": "\u{F040A}",
        "pause": "\u{F03E4}",
        "next": "\u{F04AD}",
        "previous": "\u{F04AE}",
        "palette": "\u{F03D8}",
        "image": "\u{F02E9}",
        "bell": "\u{F009A}"
    })
}
