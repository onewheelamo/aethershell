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
        // interface
        "cog": "\uf0493",
        "close": "\uf0156",
        "check": "\uf012c",
        "chevron-up": "\uf0143",
        "chevron-down": "\uf0140",
        "chevron-left": "\uf0141",
        "chevron-right": "\uf0142",
        "more": "\uf01d8",
        "plus": "\uf0415",
        "minus": "\uf0374",
        "search": "\uf0349",
        // système
        "monitor": "\uf0379",
        "laptop": "\uf0322",
        "television": "\uf07f4",
        "tablet": "\uf04f6",
        "phone": "\uf011c",
        "memory": "\uf035b",
        "battery": "\uf0079",
        "power": "\uf0425",
        "restart": "\uf0709",
        "sleep": "\uf0904",
        "lock": "\uf033e",
        "logout": "\uf0343",
        "download": "\uf01da",
        "rocket": "\uf14de",
        // réseau / audio
        "wifi": "\uf05a9",
        "bluetooth": "\uf00af",
        "volume": "\uf057e",
        "mute": "\uf075f",
        "brightness": "\uf00df",
        "headphones": "\uf02cb",
        "keyboard": "\uf030c",
        // temps / lieux / média
        "clock": "\uf0150",
        "calendar": "\uf00ed",
        "map-marker": "\uf034e",
        "weather-night": "\uf0594",
        "weather-cloud": "\uf0595",
        "sun": "\uf05a8",
        "play": "\uf040a",
        "pause": "\uf03e4",
        "next": "\uf04ad",
        "previous": "\uf04ae",
        // thème
        "palette": "\uf03d8",
        "image": "\uf02e9",
        "bell": "\uf009a"
    })
}
