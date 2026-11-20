import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Apparence » du panneau de configuration (libellé du rail ; il s'appelait
// « TAB 0: BUREAU » dans le panneau d'avant le découpage), sorti de config_panel.qml
// (9 000 lignes à un seul endroit : chaque édition scriptée y risquait de dupliquer
// un bloc). Le panneau le charge par URL et ne l'instancie qu'à l'ouverture de
// l'onglet (`active: currentTab === 0`).
//
// Deux propriétés viennent du panneau, sous les noms qu'elles avaient déjà dans le
// corps — les 109 `root.` n'ont donc pas bougé : `root` (propriétés et fonctions du
// panneau) et `mainFlickable` (largeur du contenu qui défile).
Column {
    id: bloc
    property var root
    property var mainFlickable

    // Plusieurs onglets restent montés depuis qu'on ne les décharge plus en
    // quittant : sans ce masque, ils s'empilaient les uns sur les autres
    // (le `visible:` du panneau avait été retiré à la découpe).
    visible: root ? root.currentTab === 0 : false
    width: mainFlickable ? mainFlickable.width : 0
    // Respiration entre les tiroirs de cet onglet : les autres la posent (10 px
    // entre deux sections), celui-ci laissait ses quatre bandeaux se toucher.
    spacing: 10

    readonly property var sections: ({
        "esthetique_theme": secTheme,
        "esthetique_fonds": secFonds,
        "esthetique_icones": secIcones,
        "esthetique_aspect": secAspect,
        "quickshell_barre": secBarre
    })

    readonly property var cibles: ({
        "secTheme": secTheme,
        "matugenRow": matugenRow,
        "wallpaperDirRow": wallpaperDirRow,
        "masqueProfondeurRow": masqueProfondeurRow,
        "secIcones": secIcones,
        "gapsRow": gapsRow,
        "borderRow": borderRow,
        "roundingWinRow": roundingWinRow,
        "resizeRow": resizeRow,
        "winOpacityRow": winOpacityRow,
        "shellOpacityRow": shellOpacityRow,
        "blurRow": blurRow,
        "shellBlurRow": shellBlurRow,
        "secBarre": secBarre
    })

    // 1+2. Thème & Fond d'écran (jeux de couleurs, wallpaper, matugen, palette hex custom)
// 1. Thème & Palette : jeux de couleurs, schéma et contraste Matugen,
// clé de couleur personnalisée.
CollapsibleSection {
    id: secTheme
    objectName: "secTheme"
    title: "Thème & palette"
    summary: String(Theme.paletteEtiquettes[Theme.activeTheme] || Theme.activeTheme)
    icon: "palette"
    expanded: root.sectionOpen("esthetique_theme", false)
    onToggled: expanded => {
        root.setPanelSection("esthetique_theme", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("esthetique_theme")
    }
    Text {
        text: "Jeux de couleurs & Fond d'écran"
        color: Theme.accent
        font.pixelSize: Theme.textLg
        font.bold: true
        width: parent.width
    }
Column {
    width: parent.width
    spacing: 8

    Row {
        width: parent.width
        spacing: 10

        Text {
anchors.verticalCenter: parent.verticalCenter
text: "Palettes disponibles :"
color: Theme.fg
font.pixelSize: Theme.textSm
        }

        Item {
width: Math.max(0, parent.width - 150 - btnInstallTheme.width - parent.spacing * 2)
height: 1
        }

        // Bouton « Installer un thème » (.colors / archive)
        Rectangle {
id: btnInstallTheme
anchors.verticalCenter: parent.verticalCenter
width: rowInstallTheme.implicitWidth + 20
height: 28
radius: Theme.globalRadius
color: root.themeInstallBusy
       ? Qt.alpha(Theme.accent, 0.25)
       : (maInstallTheme.containsMouse ? Theme.accentMuted : Theme.accent)

Row {
    id: rowInstallTheme
    anchors.centerIn: parent
    spacing: 6

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        glyph: "download"
        size: Math.round(Theme.iconSm * 0.8)
        color: Theme.bg
        opacityLevel: 1
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.themeInstallBusy ? "Installation..." : "Installer un thème"
        color: Theme.bg
        font.pixelSize: Theme.textXs
        font.bold: true
    }
}

MouseArea {
    id: maInstallTheme
    anchors.fill: parent
    hoverEnabled: true
    enabled: !root.themeInstallBusy
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
        root.ouvrirSelecteurFichier(
            "install_theme_colors",
            "Installer un thème (.colors)",
            "~/Téléchargements",
            ["colors"],
            "palette"
        )
    }
}
        }
    }

    // Message d'état de l'installation
    Text {
        visible: root.themeInstallStatus !== ""
        text: root.themeInstallStatus
        color: root.themeInstallStatus.indexOf("Échec") !== -1 ? Theme.error : Theme.accent
        font.pixelSize: Theme.textXs
        width: parent.width
        elide: Text.ElideRight
    }

Flow {
    width: parent.width
    spacing: 8
    // Les schémas KDE importés portent la liste à plus de soixante
    // entrées : en Flow elles passent à la ligne au lieu de sortir
    // du panneau.

    Repeater {
        // Les palettes viennent de style_vars.json ; les schémas de
        // couleurs KDE installés y sont importés au chargement du
        // panneau (`themes_scan.py --sync`), donc ils apparaissent ici.
        model: Theme.paletteNoms.length > 0 ? Theme.paletteNoms
                                : ["dynamic"]
        Rectangle {
required property string modelData
readonly property bool isCurrent: Theme.activeTheme === modelData
// « kde-gruvboxdark » se lit « Gruvboxdark » : le préfixe
// dit d'où vient le thème, pas ce qu'il est.
readonly property string libelle: Theme.paletteEtiquettes[modelData]
                                  || modelData.replace(/^kde-/, "")

width: 100
height: 32
radius: Theme.globalRadius
color: isCurrent ? Theme.accent : Theme.surfaceVariant
border.color: Theme.accent
border.width: isCurrent ? 1 : 0

Text {
    anchors.centerIn: parent
    width: parent.width - 12
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: parent.libelle
    font.capitalization: Font.Capitalize
    color: parent.isCurrent ? Theme.bg : Theme.fg
    font.pixelSize: Theme.textSm
    font.bold: parent.isCurrent
}

MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached([
        Quickshell.shellPath("core/as-core"), "theme-manager",
        parent.modelData
    ])
}
        }
    }
}
    }
Column {
    id: matugenRow   // ancre de recherche
    objectName: "matugenRow"
    width: parent.width
    spacing: 6

    Text {
        width: parent.width
        text: "Schéma Matugen :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Row {
        // Pastilles centrées sous leur libellé (elles tiennent sur une
        // seule ligne) : largeur implicite, pas width: parent.width.
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

    Repeater {
            model: [
                { id: "scheme-tonal-spot", label: "Doux" },
                { id: "scheme-vibrant", label: "Vif" },
                { id: "scheme-expressive", label: "Expressif" },
                { id: "scheme-neutral", label: "Neutre" },
                { id: "scheme-fruit-salad", label: "Fruité" },
                { id: "scheme-monochrome", label: "Mono" }
            ]
            Rectangle {
                required property var modelData
                readonly property bool active: root.matugenScheme === modelData.id
                width: 74; height: 24
                radius: Theme.globalRadius
                color: active ? Theme.accent : Theme.surfaceVariant
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: parent.active ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: parent.active
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.matugenScheme = parent.modelData.id
                        root.runConfigCmd(["style", "matugen_scheme", parent.modelData.id])
                        Quickshell.execDetached(["bash", Quickshell.shellPath("core/generate_colors.sh")])
                    }
                }
            }
        }
    }
}

Column {
    width: parent.width
    spacing: 6

    Text {
        width: parent.width
        text: "Contraste :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Row {
        // Pastilles centrées sous leur libellé (elles tiennent sur une
        // seule ligne) : largeur implicite, pas width: parent.width.
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

    Repeater {
            model: [
                // Les libellés décrivent la saturation : Pastel = moins saturé (+0.8),
                // Max = plus saturé (-0.8).
                { v: 0.8, label: "Pastel" },
                { v: 0.6, label: "Doux-" },
                { v: 0.3, label: "Standard" },
                { v: 0.0, label: "Foncé+" },
                { v: -0.4, label: "Contrasté" },
                { v: -0.8, label: "Max" }
            ]
            Rectangle {
                required property var modelData
                readonly property bool active: Math.abs(root.matugenContrast - modelData.v) < 0.05
                width: 62; height: 24
                radius: Theme.globalRadius
                color: active ? Theme.accent : Theme.surfaceVariant
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: parent.active ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: parent.active
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.matugenContrast = parent.modelData.v
                        root.runConfigCmd(["style", "matugen_contrast", String(parent.modelData.v)])
                        Quickshell.execDetached(["bash", Quickshell.shellPath("core/generate_colors.sh")])
                    }
                }
            }
        }
    }
}
Text {
    width: parent.width
    text: "Palette active — cliquer une pastille pour ajuster son hex"
    color: Theme.accent
    font.pixelSize: Theme.textMd
    font.bold: true
    elide: Text.ElideRight
}

Row {
    width: parent.width
    spacing: 8

    Repeater {
        model: [
{ key: "bg", label: "Fond", col: Theme.bg },
{ key: "surface", label: "Surface", col: Theme.surface },
{ key: "surface_variant", label: "Variante", col: Theme.surfaceVariant },
{ key: "fg", label: "Texte", col: Theme.fg },
{ key: "accent", label: "Accent", col: Theme.accent },
{ key: "accent_muted", label: "Second.", col: Theme.accentMuted },
{ key: "warn", label: "Alerte", col: Theme.warn },
{ key: "error", label: "Erreur", col: Theme.error }
        ]

        Column {
required property var modelData
spacing: 3
width: 56

Rectangle {
    width: 52
    height: 26
    radius: Theme.globalRadius
    color: parent.modelData.col
    border.color: root.selectedColorKey === parent.modelData.key ? Theme.fg : Theme.surfaceVariant
    border.width: root.selectedColorKey === parent.modelData.key ? 2 : 1

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.selectedColorKey = parent.parent.modelData.key
            hexInput.text = String(parent.parent.modelData.col)
        }
    }
}

Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: parent.modelData.label
    color: Qt.alpha(Theme.fg, 0.8)
    font.pixelSize: Theme.textXs
}
        }
    }

}

        Column {
spacing: 4

Text {
    text: "Clé : " + root.selectedColorKey
    color: Theme.accentMuted
    font.pixelSize: Theme.textXs
    font.bold: true
}

Row {
    spacing: 4
    Rectangle {
        width: 85
        height: 26
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: 1

        TextInput {
            id: hexInput
            anchors.fill: parent
            anchors.margins: 4
            verticalAlignment: TextInput.AlignVCenter
            text: "#b4befe"
            color: Theme.fg
            font.pixelSize: Theme.textXs
            onAccepted: root.runConfigCmd(["style", root.selectedColorKey, hexInput.text])
        }
    }

    Rectangle {
        width: 36
        height: 26
        radius: Theme.globalRadius
        color: Theme.accent
        Text {
            anchors.centerIn: parent
            text: "OK"
            color: Theme.bg
            font.pixelSize: Theme.textXs
            font.bold: true
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runConfigCmd(["style", root.selectedColorKey, hexInput.text])
        }
    }
}
        }
}

// 2. Fond d'écran : choix du fond, dossier, parallaxe et masque de
// profondeur. Réglages de fichiers, distincts de la palette.
CollapsibleSection {
    id: secFonds
    objectName: "secFonds"
    title: "Fond d'écran"
    summary: root.resumeChemin(root.wallpaperDir)
    icon: "image"
    expanded: root.sectionOpen("esthetique_fonds", false)
    // Éléments espacés de 8 px : boutons, chemins et libellés se touchaient. Les
    // espaces manuels (6, 10 et 2 px) ont été retirés — sinon ils s'ajouteraient.
    espacementContenu: 8
    onToggled: expanded => {
        root.setPanelSection("esthetique_fonds", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("esthetique_fonds")
    }
    Row {
    width: parent.width
    spacing: 8

    Rectangle {
        width: 135
        height: 32
        radius: Theme.globalRadius
        color: wpPickMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
        border.color: Theme.accentMuted
        border.width: 1

        Text {
anchors.centerIn: parent
text: "Fonds d'écran"
color: wpPickMa.containsMouse ? Theme.bg : Theme.fg
font.pixelSize: Theme.textXs
font.bold: true
        }

        MouseArea {
id: wpPickMa
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: {
    Theme.configPanelVisible = false
    Quickshell.execDetached([
        "quickshell",
        "-n",
        "-p",
        Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"
    ])
}
        }
    }

}

// Wallpaper Directory Path
Row {
    id: wallpaperDirRow   // ancre de recherche
    objectName: "wallpaperDirRow"
    spacing: 8
    width: parent.width

    Text {
        width: 145
        anchors.verticalCenter: parent.verticalCenter
        text: "Wallpapers"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        font.bold: true
    }

    Rectangle {
        width: parent.width - 145 - 85 - 70 - 3 * 8
        height: 28
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: wpDirInput.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1
        clip: true

        TextInput {
id: wpDirInput
anchors.fill: parent
anchors.margins: 6
verticalAlignment: TextInput.AlignVCenter
text: Theme.wallpaperDir || root.wallpaperDir
color: Theme.fg
font.pixelSize: Theme.textXs
onAccepted: {
    if (wpDirInput.text.trim() !== "") {
        root.runConfigCmd(["style", "wallpaper_dir", wpDirInput.text.trim()])
    }
}
        }
    }

    // Sélecteur de dossier : le champ et son bouton écrivent le même
    // réglage, mais on ne tape pas un chemin absolu à la main.
    Rectangle {
        width: 70
        height: 28
        radius: Theme.globalRadius
        color: wpPickMa2.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
        border.color: Theme.accentMuted
        border.width: 1

        Row {
anchors.centerIn: parent
spacing: 4

Icon {
    anchors.verticalCenter: parent.verticalCenter
    glyph: "folder"
    size: Math.round(Theme.iconSm * 0.78)
    color: wpPickMa2.containsMouse ? Theme.bg : Theme.accent
    opacityLevel: 1
}

Text {
    anchors.verticalCenter: parent.verticalCenter
    text: "Choisir"
    color: wpPickMa2.containsMouse ? Theme.bg : Theme.fg
    font.pixelSize: Theme.textXs
}
        }

        MouseArea {
id: wpPickMa2
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: root.ouvrirSelecteur("wallpaper_dir", "Dossier des fonds d'écran", wpDirInput.text)
        }
    }

    Rectangle {
        width: 85
        height: 28
        radius: Theme.globalRadius
        color: wpDirSaveMa.containsMouse ? Theme.accentMuted : Theme.accent

        Text {
anchors.centerIn: parent
text: "Appliquer"
color: Theme.bg
font.pixelSize: Theme.textXs
font.bold: true
        }

        MouseArea {
id: wpDirSaveMa
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: {
    if (wpDirInput.text.trim() !== "") {
        root.runConfigCmd(["style", "wallpaper_dir", wpDirInput.text.trim()])
    }
}
        }
    }
}

Row {
    width: parent.width
    spacing: 8

    Text {
        width: 160
        anchors.verticalCenter: parent.verticalCenter
        text: "Fond en profondeur :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 160
        height: 26
        radius: Theme.globalRadius
        color: Theme.depthWallpaper ? Theme.accent : Theme.surfaceVariant
        border.color: Theme.accent
        border.width: 1

        Text {
anchors.centerIn: parent
text: Theme.depthWallpaper ? "✓ Actif" : "✕ Désactivé"
color: Theme.depthWallpaper ? Theme.bg : Theme.fg
font.pixelSize: Theme.textXs
        }

        MouseArea {
anchors.fill: parent
cursorShape: Qt.PointingHandCursor
onClicked: root.runConfigCmd([
    "style", "depth_wallpaper", Theme.depthWallpaper ? "false" : "true"
])
        }
    }
}

Row {
    id: wallpaperSlideRow
    objectName: "wallpaperSlideRow"
    width: parent.width
    spacing: 8
    opacity: Theme.depthWallpaper ? 0.5 : 1.0

    Text {
        width: 160
        anchors.verticalCenter: parent.verticalCenter
        text: "Glissement du fond :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 160
        height: 26
        radius: Theme.globalRadius
        color: Theme.wallpaperSlide ? Theme.accent : Theme.surfaceVariant
        border.color: Theme.accent
        border.width: 1

        Text {
anchors.centerIn: parent
text: Theme.wallpaperSlide ? "✓ Actif" : "✕ Désactivé"
color: Theme.wallpaperSlide ? Theme.bg : Theme.fg
font.pixelSize: Theme.textXs
        }

        MouseArea {
anchors.fill: parent
cursorShape: Qt.PointingHandCursor
onClicked: root.runConfigCmd([
    "style", "wallpaper_slide", Theme.wallpaperSlide ? "false" : "true"
])
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: Theme.depthWallpaper
        text: "(inactif si parallaxe active)"
        color: Qt.alpha(Theme.fg, 0.55)
        font.pixelSize: Theme.textXs
    }
}

// Le modèle de profondeur ne suit pas toujours l'intention : sur
// Fantasy-Landscape1 il range la rive de l'étang à 0,45 et les
// bosquets de gauche à 0,19, presque comme l'eau (0,14). Ce bouton
// ouvre la peinture du masque, qui fait alors foi sur le modèle.
Row {
    width: parent.width
    spacing: 8

    Text {
        width: 160
        anchors.verticalCenter: parent.verticalCenter
        text: "Masque du relief :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 160
        height: 26
        radius: Theme.globalRadius
        color: Theme.surfaceVariant
        border.color: Theme.accent
        border.width: 1

        Text {
anchors.centerIn: parent
text: "Peindre à la main…"
color: Theme.fg
font.pixelSize: Theme.textXs
        }

        MouseArea {
anchors.fill: parent
cursorShape: Qt.PointingHandCursor
onClicked: {
    Theme.masqueParallaxeVisible = true
    Theme.configPanelVisible = false
}
        }
    }
}

// Masque de premier plan (idée du plugin Noctalia wallpaper_depth) :
// une carte de profondeur du fond décide ce qui passe devant les
// widgets de bureau. Sur deux lignes : à cinq contrôles sur une
// seule, le dernier stepper sortait du panneau et se lisait tronqué.
Column {
    width: parent.width
    spacing: 6

    Row {
id: masqueProfondeurRow   // ancre de recherche
objectName: "masqueProfondeurRow"
width: parent.width
spacing: 8

Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Masque de profondeur :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
}

Rectangle {
anchors.verticalCenter: parent.verticalCenter
width: 160
height: 26
radius: Theme.globalRadius
color: Theme.depthMask ? Theme.accent : Theme.surfaceVariant
border.color: Theme.accent
border.width: 1

Text {
    anchors.centerIn: parent
    text: Theme.depthMask ? "✓ Actif" : "✕ Désactivé"
    color: Theme.depthMask ? Theme.bg : Theme.fg
    font.pixelSize: Theme.textXs
}

MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.runConfigCmd([
        "style", "depth_mask", Theme.depthMask ? "false" : "true"
    ])
}
}
    }

    // Rendu du masque : un calque plein écran (copie du fond) ou un
    // MultiEffect par widget, qui découpe la carte elle-même. Le
    // second est plus juste — rien ne se décale — mais rend chaque
    // widget hors écran à chaque changement.
    Row {
width: parent.width
spacing: 8

// Aligne « seuil » sous le libellé, pas sous le bouton.
Item { width: 160; height: 1 }
Text {
anchors.verticalCenter: parent.verticalCenter
text: "seuil"
color: Qt.alpha(Theme.fg, 0.6)
font.pixelSize: Theme.text2xs
}
Stepper {
anchors.verticalCenter: parent.verticalCenter
width: 84
value: Theme.depthMaskSeuil
minimumValue: 0
maximumValue: 100
stepSize: 5
onValueModified: newVal => root.runConfigCmd([
    "style", "depth_mask_seuil", String(newVal)
])
}
Text {
anchors.verticalCenter: parent.verticalCenter
text: "adouci"
color: Qt.alpha(Theme.fg, 0.6)
font.pixelSize: Theme.text2xs
}
Stepper {
anchors.verticalCenter: parent.verticalCenter
width: 84
value: Theme.depthMaskAdouci
minimumValue: 0
maximumValue: 50
stepSize: 1
onValueModified: newVal => root.runConfigCmd([
    "style", "depth_mask_adouci", String(newVal)
])
}
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
        opacity: 0.45
    }

    // Fond de l'écran de verrouillage (hyprlock) — couleur unie ou image sans screenshot DMA-BUF.
    Row {
        width: parent.width
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 160
            text: "Écran de verrouillage"
            color: Theme.fg
            font.pixelSize: Theme.textSm
            font.bold: true
        }

        ConfigSegmented {
            anchors.verticalCenter: parent.verticalCenter
            choices: [
                { code: "solid", label: "Couleur unie" },
                { code: "image", label: "Image" }
            ]
            currentCode: Theme.lockBgMode
            onSelected: function(code) { root.runConfigCmd(["style", "lock_bg_mode", code]) }
        }
    }

    // Choix de couleur unie pour hyprlock (palette $bg ou teinte personnalisée)
    Row {
        visible: Theme.lockBgMode !== "image"
        width: parent.width
        spacing: 8

        Item { width: 160; height: 1 }

        Rectangle {
            id: lockPalBtn
            readonly property bool actif: Theme.lockBgColor === ""
            width: lockPalLbl.implicitWidth + 16
            height: 26
            radius: Theme.globalRadius
            color: lockPalBtn.actif ? Theme.accent : (lockPalMa.containsMouse ? Theme.surfaceVariant : Theme.bg)
            border.color: lockPalBtn.actif ? Theme.accent : Theme.surfaceVariant
            border.width: 1

            Text {
                id: lockPalLbl
                anchors.centerIn: parent
                text: "Fond du thème"
                color: lockPalBtn.actif ? Theme.bg : Theme.fg
                font.pixelSize: Theme.textXs
                font.bold: lockPalBtn.actif
            }

            MouseArea {
                id: lockPalMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runConfigCmd(["style", "lock_bg_color", ""])
            }
        }

        Repeater {
            model: ["#0f1117", "#1e1e2e", "#111827", "#000000", Theme.surface]
            delegate: Rectangle {
                required property string modelData
                readonly property bool actif: Theme.lockBgColor.toLowerCase() === modelData.toLowerCase()
                width: 26
                height: 26
                radius: Theme.globalRadius
                color: modelData
                border.color: actif ? Theme.accent : Theme.surfaceVariant
                border.width: actif ? 2 : 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["style", "lock_bg_color", modelData])
                }
            }
        }
    }

    // Choix d'image pour hyprlock via SelecteurFichier.qml
    Row {
        visible: Theme.lockBgMode === "image"
        width: parent.width
        spacing: 8

        Item { width: 160; height: 1 }

        Rectangle {
            width: lockImgBtnLbl.implicitWidth + 20
            height: 28
            radius: Theme.globalRadius
            color: lockImgMa.containsMouse ? Theme.accent : Theme.bg
            border.color: Theme.accent
            border.width: 1

            Text {
                id: lockImgBtnLbl
                anchors.centerIn: parent
                text: "Choisir une image…"
                color: lockImgMa.containsMouse ? Theme.bg : Theme.accent
                font.pixelSize: Theme.textXs
                font.bold: true
            }

            MouseArea {
                id: lockImgMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.ouvrirSelecteurFichier(
                        "lock_bg_image",
                        "Fond de l'écran de verrouillage",
                        Theme.lockBgImage !== "" ? Theme.lockBgImage : (Theme.wallpaperDir || "~/Images"),
                        ["png", "jpg", "jpeg", "webp"],
                        "image"
                    )
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 160 - 150
            text: Theme.lockBgImage !== "" ? String(Theme.lockBgImage).split("/").pop() : "Aucune image sélectionnée"
            color: Theme.lockBgImage !== "" ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
            font.pixelSize: Theme.textXs
            elide: Text.ElideMiddle
        }
    }
}
}

// 3. Desktop Aspect: Gaps, Borders, Rounding, Opacity, Blur, Bar (catégorie technique)
CollapsibleSection {
    id: secAspect
    title: "Fenêtres Hyprland"
    summary: "Gaps " + root.gapsIn + "/" + root.gapsOut + " · " + (root.blurEnabled ? "flou actif" : "flou coupé")
    icon: "cog"
    expanded: root.sectionOpen("esthetique_aspect", false)
    onToggled: expanded => {
        root.setPanelSection("esthetique_aspect", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("esthetique_aspect")
    }

Grid {
    width: parent.width
    columns: 1
    columnSpacing: 14
    rowSpacing: 12

    // 1. Gaps In
    Row {
        id: gapsRow   // ancre de recherche
        objectName: "gapsRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Gaps internes (in) :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.gapsIn
minimumValue: 0
maximumValue: 30
stepSize: 1
suffix: " px"
onValueModified: newVal => {
    root.gapsIn = newVal
    root.runConfigCmd(["gaps", "gaps_in", String(newVal)])
}
        }
    }

    // 2. Gaps Out
    Row {
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Gaps externes (out) :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.gapsOut
minimumValue: 0
maximumValue: 40
stepSize: 1
suffix: " px"
onValueModified: newVal => {
    root.gapsOut = newVal
    root.runConfigCmd(["gaps", "gaps_out", String(newVal)])
}
        }
    }

    // 3. Bordures fenêtres
    Row {
        id: borderRow   // ancre de recherche
        objectName: "borderRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Bordures fenêtres :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.borderSize
minimumValue: 0
maximumValue: 10
stepSize: 1
suffix: " px"
onValueModified: newVal => {
    root.borderSize = newVal
    root.runConfigCmd(["gaps", "border_size", String(newVal)])
}
        }
    }

    // 4. Arrondis fenêtres (Hyprland)
    Row {
        id: roundingWinRow   // ancre de recherche
        objectName: "roundingWinRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Arrondis fenêtres :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.hyprRounding
minimumValue: 0
maximumValue: 35
stepSize: 1
suffix: " px"
onValueModified: newVal => {
    root.hyprRounding = newVal
    root.runConfigCmd(["style", "hypr_rounding", String(newVal)])
}
        }
    }

    // 4 bis. Forme des coins (decoration:rounding_power) : ce n'est pas
    // le rayon mais la courbe. 2 = arc de cercle ; en dessous le coin se
    // redresse jusqu'au chanfrein, au-dessus il s'arrondit en « squircle ».
    Row {
        id: roundingPowerRow   // ancre de recherche
        objectName: "roundingPowerRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Forme des coins :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        // Stepper comme les bordures : clic ou molette au dixième. Le
        // suffixe vit à côté plutôt que dans le compteur, où « coupe
        // droite » déborderait entre les deux boutons.
        // Deux valeurs utiles seulement : 1 coupe le coin en droite,
        // 2 trace un arc. Au-delà, Hyprland ne fait qu'arrondir la
        // transition vers le carré, ce qui ne se distingue pas à l'œil.
        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.hyprRoundingPower
minimumValue: 1
maximumValue: 2
stepSize: 1
onValueModified: newVal => {
    root.hyprRoundingPower = newVal
    root.runConfigCmd(["style", "hypr_rounding_power", String(newVal)])
}
        }

        Text {
anchors.verticalCenter: parent.verticalCenter
text: root.hyprRoundingPower < 2 ? "coupe droite" : "cercle"
color: Qt.alpha(Theme.fg, 0.55)
font.pixelSize: Theme.textXs
        }
    }

    // 7. Pas de redimensionnement clavier
    Row {
        id: resizeRow   // ancre de recherche
        objectName: "resizeRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Pas redimensionnement :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Slider {
anchors.verticalCenter: parent.verticalCenter
value: root.resizeStep
minimumValue: 5
maximumValue: 50
stepSize: 5
suffix: " px"
onValueModified: newVal => {
    root.resizeStep = newVal
    root.runConfigCmd(["style", "resize_step", String(newVal)])
}
        }
    }

}   // fin Grid aspect (gaps, arrondis, opacité, barre)

Grid {
    width: parent.width
    columns: 1
    columnSpacing: 14
    rowSpacing: 12

    // 8. Opacité des fenêtres (decoration.active_opacity)
    Row {
        id: winOpacityRow   // ancre de recherche
        objectName: "winOpacityRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Opacité fenêtres :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: Theme.globalOpacity
minimumValue: 0.30
maximumValue: 1.00
stepSize: 0.05
decimals: 2
textFormatter: v => Math.round(v * 100) + " %"
onValueModified: newVal => {
    root.runConfigCmd(["style", "global_opacity", String(newVal)])
}
        }
    }

    // 9. Taille du flou
    Row {
        id: blurRow   // ancre de recherche
        objectName: "blurRow"
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Taille du flou :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Slider {
anchors.verticalCenter: parent.verticalCenter
value: root.blurSize
minimumValue: 1
maximumValue: 20
stepSize: 1
suffix: " px"
onValueModified: newVal => {
    root.blurSize = newVal
    root.runConfigCmd(["style", "blur_size", String(newVal)])
}
        }
    }

    // 10. Passes du flou
    Row {
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Passes du flou :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        Stepper {
anchors.verticalCenter: parent.verticalCenter
value: root.blurPasses
minimumValue: 1
maximumValue: 8
stepSize: 1
onValueModified: newVal => {
    root.blurPasses = newVal
    root.runConfigCmd(["style", "blur_passes", String(newVal)])
}
        }
    }

    // 11. Flou des fenêtres (Actif / Désactivé)
    Row {
        width: parent.width
        spacing: 8

        Text {
width: 160
anchors.verticalCenter: parent.verticalCenter
text: "Flou Hyprland :"
color: Theme.fg
font.pixelSize: Theme.textSm
elide: Text.ElideRight
        }

        ConfigSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.blurEnabled
            onToggled: {
                root.blurEnabled = !root.blurEnabled
                root.runConfigCmd(["style", "blur_enabled", root.blurEnabled ? "true" : "false"])
            }
        }
    }



}   // fin Grid fenêtres

}   // end CollapsibleSection secAspect


// Surfaces dessinées par Quickshell : îlots, barre, panneau, popups.
CollapsibleSection {
    id: secBarre
    objectName: "secBarre"
    title: "Surfaces du shell"
    summary: "Opacité " + Math.round(Theme.shellOpacity * 100) + " % · Rayon " + Theme.globalRadius
    icon: "monitor"
    expanded: root.sectionOpen("quickshell_barre", false)
    onToggled: expanded => {
        root.setPanelSection("quickshell_barre", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_barre")
    }


    Grid {
        width: parent.width
        columns: 1
        columnSpacing: 14
        rowSpacing: 12

        // 12. Opacité des surfaces Quickshell (barre, OSD, panneau, popups)
        Row {
id: shellOpacityRow   // ancre de recherche
objectName: "shellOpacityRow"
width: parent.width
spacing: 8

Text {
    width: 160
    anchors.verticalCenter: parent.verticalCenter
    text: "Opacité surfaces :"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
}

Stepper {
    anchors.verticalCenter: parent.verticalCenter
    value: Theme.shellOpacity
    minimumValue: 0.20
    maximumValue: 1.00
    stepSize: 0.05
    decimals: 2
    textFormatter: v => Math.round(v * 100) + " %"
    onValueModified: newVal => {
        root.runConfigCmd(["style", "shell_opacity", String(newVal)])
    }
}
        }

        // 13. Flou des surfaces du shell (barre, OSD, panneau)
        Row {
id: shellBlurRow   // ancre de recherche
objectName: "shellBlurRow"
width: parent.width
spacing: 8

Text {
    width: 160
    anchors.verticalCenter: parent.verticalCenter
    text: "Flou Quickshell :"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
}

        ConfigSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.shellBlurEnabled
            onToggled: {
                root.shellBlurEnabled = !root.shellBlurEnabled
                root.runConfigCmd(["style", "shell_blur_enabled", root.shellBlurEnabled ? "true" : "false"])
            }
        }
        }

        // 14. Seuil de transparence (ignore_alpha)
        Row {
width: parent.width
spacing: 8

Text {
    width: 160
    anchors.verticalCenter: parent.verticalCenter
    text: "Seuil de flou :"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
}

Stepper {
    anchors.verticalCenter: parent.verticalCenter
    value: root.shellBlurAlpha
    minimumValue: 0.05
    maximumValue: 0.9
    stepSize: 0.05
    decimals: 2
    onValueModified: newVal => {
        root.shellBlurAlpha = newVal
        root.runConfigCmd(["style", "shell_blur_alpha", String(newVal)])
    }
}
        }

        // 14b. Bordure de la barre du haut (capsule fusionnée et îlots)

        // 14c. Espaces entre les îlots : transparents (et donc sans flou)
        // ou peints comme le reste de la capsule. En mode transparent,
        // les deux vides restent des régions de la barre, réservées à
        // une animation de lecture média.

        // 15. Flou derrière les popups ancrés (calendrier, wifi, volume…)
        Row {
width: parent.width
spacing: 8

Text {
    width: 160
    anchors.verticalCenter: parent.verticalCenter
    text: "Flou des popups :"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
}

        ConfigSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.shellBlurPopups
            onToggled: {
                root.shellBlurPopups = !root.shellBlurPopups
                root.runConfigCmd(["style", "shell_blur_popups", root.shellBlurPopups ? "true" : "false"])
            }
        }
        }
        // 16. Effet d'accordéon : un seul tiroir ouvert par onglet.
        Row {
width: parent.width
spacing: 8

Text {
    width: 160
    anchors.verticalCenter: parent.verticalCenter
    text: "Effet d'accordéon :"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
}

        ConfigSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: Theme.panelAccordion
            onToggled: root.runConfigCmd(["style", "panel_accordion", Theme.panelAccordion ? "false" : "true"])
        }

Text {
    anchors.verticalCenter: parent.verticalCenter
    text: "Actif : ouvrir un tiroir referme les autres du même onglet."
    color: Qt.alpha(Theme.fg, 0.5)
    font.pixelSize: Theme.text2xs
}
        }
    }   // fin Grid shell

    Text {
        width: parent.width
        topPadding: 8
        text: "Ces réglages ne concernent que les surfaces du shell (barre, OSD, panneau, popups). "
+ "L'opacité et le flou des fenêtres se règlent ici, section « Fenêtres Hyprland ». "
+ "La taille et les passes du flou restent communes aux deux, d'où un rendu plus ou moins diffus de part et d'autre. "
+ "Deux seuils, tous deux sur l'opacité des surfaces : sous 30 % ("
+ "le « seuil » ci-dessous) Hyprland cesse de flouter derrière elles, donc "
+ "fenêtres nettes sous une surface transparente ; au-delà de ~70 % le verre "
+ "interne ne change plus rien. Entre les deux, les deux flous se cumulent : "
+ "celui du compositeur (fenêtres comprises) et le verre interne (fond seul)."
        color: Theme.fg
        opacity: 0.6
        font.pixelSize: Theme.textXs
        wrapMode: Text.WordWrap
    }

}   // end CollapsibleSection secShell

// 3b. Thèmes & Packs d'icônes : sélection du thème actif + installation d'archives.
CollapsibleSection {
    id: secIcones
    objectName: "secIcones"
    title: "Thèmes & Packs d'icônes"
    summary: (root && root.iconesEtat && root.iconesEtat.actif)
        ? ("Actif : " + root.iconesEtat.actif)
        : "Sélection et installation de packs d'icônes"
    icon: "image"
    expanded: root ? root.sectionOpen("esthetique_icones", false) : false
    espacementContenu: 8
    onToggled: expanded => {
        if (!root) return
        root.setPanelSection("esthetique_icones", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("esthetique_icones")
        if (expanded && (!root.iconesEtat.themes || root.iconesEtat.themes.length === 0)) {
            root.rafraichirIcones()
        }
    }
    Component.onCompleted: {
        if (root && (!root.iconesEtat.themes || root.iconesEtat.themes.length === 0)) {
            root.rafraichirIcones()
        }
    }

    Row {
        width: parent.width
        spacing: 8

        Rectangle {
            width: 250
            height: 30
            radius: Theme.globalRadius
            color: icInstallMa.containsMouse ? Theme.accentMuted : Theme.accent

            Text {
                anchors.centerIn: parent
                text: "Installer un pack (.tar.gz / .tar.xz / .zip)…"
                color: Theme.bg
                font.pixelSize: Theme.textXs
                font.bold: true
            }

            MouseArea {
                id: icInstallMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root) root.ouvrirSelecteurFichier(
                    "icon_pack",
                    "Choisir une archive de pack d'icônes",
                    "~/Téléchargements",
                    ["tar.gz", "tgz", "tar.xz", "txz", "tar.bz2", "tar.zst", "tar", "zip"],
                    "folder"
                )
            }
        }

        Rectangle {
            width: 96
            height: 30
            radius: Theme.globalRadius
            color: icRefreshMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55)
            border.color: Theme.surfaceVariant
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Actualiser"
                color: Theme.fg
                font.pixelSize: Theme.textXs
            }

            MouseArea {
                id: icRefreshMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root) root.rafraichirIcones()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root && root.iconesMessage !== ""
            text: root ? root.iconesMessage : ""
            color: Theme.accent
            font.pixelSize: Theme.textXs
            elide: Text.ElideRight
            width: Math.max(80, parent.width - 362)
        }
    }

    Repeater {
        model: (root && root.iconesEtat && root.iconesEtat.themes) ? root.iconesEtat.themes : []

        delegate: Rectangle {
            required property var modelData
            readonly property bool estActif: root && root.iconesEtat && root.iconesEtat.actif === modelData.id
            width: parent ? parent.width : 0
            height: 46
            radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
            color: estActif ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.surfaceVariant, 0.35)
            border.color: estActif ? Theme.accent : Qt.alpha(Theme.fg, 0.08)
            border.width: 1

            Item {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10

                // Aperçu visuel (emplacement fixe de 4 icônes pour aligner les noms)
                Row {
                    id: previewRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 100
                    spacing: 4

                    Repeater {
                        model: modelData.apercu || []
                        Image {
                            required property string modelData
                            width: 22
                            height: 22
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 24
                            sourceSize.height: 24
                            source: "file://" + modelData
                        }
                    }
                }

                Column {
                    anchors.left: previewRow.right
                    anchors.leftMargin: 12
                    anchors.right: btnSupprimer.visible ? btnSupprimer.left : btnAppliquer.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: modelData.nom + (modelData.utilisateur ? " · perso" : "")
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        font.bold: estActif
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: modelData.id
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Theme.text2xs
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: btnSupprimer
                    visible: modelData.utilisateur === true && !estActif
                    anchors.right: btnAppliquer.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 78
                    height: 26
                    radius: Theme.globalRadius
                    color: Qt.alpha(Theme.error, 0.14)
                    border.color: Qt.alpha(Theme.error, 0.4)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Supprimer"
                        color: Theme.error
                        font.pixelSize: Theme.text2xs
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root) root.supprimerPackIcones(modelData.id)
                    }
                }

                ConfigToggle {
                    id: btnAppliquer
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    pillWidth: 88
                    active: estActif
                    onLabel: "✓ Actif"
                    offLabel: "Appliquer"
                    onToggled: if (root && !estActif) root.appliquerThemeIcones(modelData.id)
                }
            }
        }
    }
}

}
