import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."

// ════════════════════════════════════════════════════════════════════════════
// MENU D'UN WIDGET DE BUREAU — clic milieu
// ════════════════════════════════════════════════════════════════════════════
// Affiche les actions rapides (retirer, bureaux d'affichage), l'apparence
// commune (style, flou/bordure, opacité, taille) et les options propres au
// type de widget sélectionné — sans doublons.
Item {
    id: racine

    property bool ouvert: false
    property var widget: ({})
    property real xEcran: 0
    property real yEcran: 0
    signal fermer()

    // Lecture réactive depuis Theme.widgets pour refléter immédiatement les changements.
    readonly property var widgetActuel: {
        const w = racine.widget || ({})
        const wid = String(w.id || "")
        const ws = Theme.widgets || []
        for (let i = 0; i < ws.length; ++i) {
            if (ws[i] && String(ws[i].id) === wid) return ws[i]
        }
        return w
    }
    readonly property string wid: String((widgetActuel || {}).id || "")
    readonly property string wtype: String((widgetActuel || {}).type || "")
    readonly property var wOptions: (widgetActuel && widgetActuel.options) ? widgetActuel.options : ({})

    readonly property string wStyle: String((widgetActuel && widgetActuel.style) || "glass")
    readonly property bool wBlur: widgetActuel ? (widgetActuel.blur !== false) : true
    readonly property bool wBorder: widgetActuel ? (widgetActuel.border !== false) : true
    readonly property real wOpacity: (widgetActuel && widgetActuel.opacity !== undefined)
        ? Number(widgetActuel.opacity) : 0.35
    readonly property int wTextScale: {
        const v = Number(wOptions.text_scale)
        return (v >= 60 && v <= 160) ? Math.round(v) : 100
    }
    readonly property bool wSeconds: {
        const v = wOptions.seconds
        return v === true || v === "true" || v === 1 || v === "1"
    }
    readonly property bool wIgnorerNav: {
        const v = wOptions.ignorer_navigateurs
        if (v === undefined || v === null || v === "") return true
        return !(v === false || v === "false" || v === 0 || v === "0")
    }
    readonly property bool wAfficherFaits: {
        const v = wOptions.afficher_faits
        return v === true || v === "true" || v === 1 || v === "1"
    }
    readonly property string wCity: wOptions.city ? String(wOptions.city) : ""
    readonly property string wImage: wOptions.image ? String(wOptions.image) : ""
    readonly property string wVizStyle: wOptions.viz_style ? String(wOptions.viz_style) : ""
    readonly property int wRefreshMin: {
        const v = Number(wOptions.refresh_min)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    readonly property bool aOptionSecondes: wtype === "horloge" || wtype === "combo"
    readonly property bool aOptionNav: wtype === "musique"
    readonly property bool aOptionViz: wtype === "visualiseur"
    readonly property bool aOptionFaits: wtype === "todo"
    readonly property bool aOptionVille: wtype === "meteo" || wtype === "combo"
    readonly property bool aOptionImage: wtype === "sticker"
    readonly property bool aOptionRefresh: wtype === "systeme" || wtype === "disques"
        || wtype === "homelab" || wtype === "hermes" || wtype === "usb"
        || wtype === "meteo" || wtype === "reseau" || wtype === "comptes"
    readonly property bool aOptionsPropres: aOptionSecondes || aOptionNav || aOptionViz
        || aOptionFaits || aOptionVille || aOptionImage || aOptionRefresh

    function libelleType(t) {
        const map = {
            "horloge": "Horloge", "date": "Date", "meteo": "Météo",
            "combo": "Aperçu du jour", "musique": "Musique",
            "visualiseur": "Visualiseur audio", "notes": "Notes rapides",
            "sticker": "Sticker / Image", "systeme": "Système",
            "reseau": "Réseau", "disques": "Disques", "homelab": "Homelab",
            "hermes": "Hermes", "usb": "Périphériques", "todo": "Tâches",
            "presse_papiers": "Presse-papiers", "deepseek": "DeepSeek",
            "antigravity": "Antigravity", "comptes": "Quotas IA"
        }
        return map[t] || t || "Widget"
    }

    // 0 = tous les bureaux. La liste va jusqu'à dix, comme les binds du shell.
    readonly property var bureaux: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    readonly property var choisis: {
        const w = racine.widgetActuel || ({})
        const brut = (w.workspaces && w.workspaces.length > 0)
            ? w.workspaces : [Number(w.workspace)]
        return brut.map(Number)
    }

    readonly property bool tous: choisis.indexOf(0) >= 0

    function estChoisi(n) {
        if (racine.tous) return n === 0
        return racine.choisis.indexOf(n) >= 0
    }

    function basculer(n) {
        let liste
        if (n === 0) {
            liste = [0]
        } else if (racine.tous) {
            liste = [n]
        } else {
            liste = racine.choisis.filter(x => x !== 0 && x !== n)
            if (racine.choisis.indexOf(n) < 0) liste.push(n)
            liste.sort((a, b) => a - b)
            if (liste.length === 0) liste = [0]
        }
        racine.ecrireBureaux(liste.join(","))
    }

    Process { id: ecrire }

    function ecrireBureaux(spec) {
        ecrire.command = [Quickshell.shellPath("core/as-core"), "config",
                          "widget_workspaces", racine.wid, spec]
        ecrire.running = true
    }

    function poserOption(cle, valeur) {
        if (racine.wid === "") return
        ecrire.command = [Quickshell.shellPath("core/as-core"), "config",
                          "widget_set", racine.wid, String(cle), String(valeur)]
        ecrire.running = true
    }

    function retirer() {
        ecrire.command = [Quickshell.shellPath("core/as-core"), "config",
                          "widget_remove", racine.wid]
        ecrire.running = true
        racine.fermer()
    }

    PanelWindow {
        id: fenetre
        visible: racine.ouvert
        color: "transparent"
        implicitWidth: 344
        implicitHeight: carte.implicitHeight

        readonly property int marge: 8
        readonly property int largeurEcran: fenetre.screen ? fenetre.screen.width : 1920
        readonly property int hauteurEcran: fenetre.screen ? fenetre.screen.height : 1080

        anchors { top: true; left: true }
        margins.top: Math.round(Math.max(marge, Math.min(racine.yEcran + 64,
                                                          hauteurEcran - implicitHeight - marge)))
        margins.left: Math.round(Math.max(marge, Math.min(racine.xEcran,
                                                          largeurEcran - implicitWidth - marge)))

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-menu-widget"
        WlrLayershell.keyboardFocus: (racine.aOptionVille || racine.aOptionImage)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: colonne.implicitHeight + 24
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: colonne
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    width: parent.width
                    text: racine.libelleType(racine.wtype) + (racine.wid !== "" ? (" · " + racine.wid) : "")
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Rectangle {
                    width: parent.width
                    height: 26
                    radius: Theme.globalRadius
                    color: retireMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.45)
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Retirer du bureau"
                        color: Theme.error
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        id: retireMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: racine.retirer()
                    }
                }

                Text {
                    width: parent.width
                    text: "Afficher sur :"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                    font.bold: true
                    font.letterSpacing: 0.5
                    font.capitalization: Font.AllUppercase
                }

                Flow {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: racine.bureaux

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: racine.estChoisi(modelData)
                            width: modelData === 0 ? 48 : 26
                            height: 22
                            radius: Theme.globalRadius
                            color: choisi ? Theme.accent : "transparent"
                            border.color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData === 0 ? "Tous" : String(modelData)
                                color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                font.bold: parent.choisi
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: racine.basculer(modelData)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Text {
                    width: parent.width
                    text: "Apparence & taille :"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                    font.bold: true
                    font.letterSpacing: 0.5
                    font.capitalization: Font.AllUppercase
                }

                // Style + Effets (Flou / Bordure)
                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: [
                            { code: "glass",       label: "Glass" },
                            { code: "transparent", label: "Transparent" }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: racine.wStyle === modelData.code
                            width: styleLbl.implicitWidth + 16
                            height: 22
                            radius: Theme.globalRadius
                            color: choisi ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                id: styleLbl
                                anchors.centerIn: parent
                                text: (choisi ? "✓ " : "") + modelData.label
                                color: choisi ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: choisi
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: racine.poserOption("style", modelData.code)
                            }
                        }
                    }

                    Repeater {
                        model: racine.wStyle === "transparent" ? [] : [
                            { key: "blur",   label: "Flou",    on: racine.wBlur },
                            { key: "border", label: "Bordure", on: racine.wBorder }
                        ]

                        Rectangle {
                            required property var modelData
                            width: effLbl.implicitWidth + 14
                            height: 22
                            radius: Theme.globalRadius
                            color: modelData.on ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                id: effLbl
                                anchors.centerIn: parent
                                text: (modelData.on ? "✓ " : "✕ ") + modelData.label
                                color: modelData.on ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: racine.poserOption(modelData.key, modelData.on ? "false" : "true")
                            }
                        }
                    }
                }

                // Opacité (si Glass) + Taille (%)
                Row {
                    width: parent.width
                    spacing: 12

                    Row {
                        visible: racine.wStyle !== "transparent"
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Opacité"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.text2xs
                        }
                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84
                            value: racine.wOpacity
                            minimumValue: 0.0
                            maximumValue: 1.0
                            stepSize: 0.05
                            decimals: 2
                            onValueModified: newVal => racine.poserOption("opacity", newVal)
                        }
                    }

                    Row {
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Taille"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.text2xs
                        }
                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 88
                            value: racine.wTextScale
                            minimumValue: 60
                            maximumValue: 160
                            stepSize: 5
                            suffix: " %"
                            onValueModified: newVal => racine.poserOption("text_scale", newVal)
                        }
                    }
                }

                // Options propres au type de widget (uniquement celles qui le concernent)
                Rectangle {
                    visible: racine.aOptionsPropres
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Text {
                    visible: racine.aOptionsPropres
                    width: parent.width
                    text: "Options du widget :"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                    font.bold: true
                    font.letterSpacing: 0.5
                    font.capitalization: Font.AllUppercase
                }

                // Toggles booléens spécifiques (sans doublons)
                Flow {
                    visible: racine.aOptionSecondes || racine.aOptionNav || racine.aOptionFaits
                    width: parent.width
                    spacing: 6

                    Rectangle {
                        visible: racine.aOptionSecondes
                        width: secLbl.implicitWidth + 16
                        height: 22
                        radius: Theme.globalRadius
                        color: racine.wSeconds ? Theme.accent : Theme.surfaceVariant
                        border.width: 1
                        border.color: Theme.accent
                        Text {
                            id: secLbl
                            anchors.centerIn: parent
                            text: (racine.wSeconds ? "✓ " : "✕ ") + "Secondes"
                            color: racine.wSeconds ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.poserOption("seconds", racine.wSeconds ? "false" : "true")
                        }
                    }

                    Rectangle {
                        visible: racine.aOptionNav
                        width: navLbl.implicitWidth + 16
                        height: 22
                        radius: Theme.globalRadius
                        color: racine.wIgnorerNav ? Theme.accent : Theme.surfaceVariant
                        border.width: 1
                        border.color: Theme.accent
                        Text {
                            id: navLbl
                            anchors.centerIn: parent
                            text: (racine.wIgnorerNav ? "✓ " : "✕ ") + "Ignorer navigateurs"
                            color: racine.wIgnorerNav ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.poserOption("ignorer_navigateurs", racine.wIgnorerNav ? "false" : "true")
                        }
                    }

                    Rectangle {
                        visible: racine.aOptionFaits
                        width: faitLbl.implicitWidth + 16
                        height: 22
                        radius: Theme.globalRadius
                        color: racine.wAfficherFaits ? Theme.accent : Theme.surfaceVariant
                        border.width: 1
                        border.color: Theme.accent
                        Text {
                            id: faitLbl
                            anchors.centerIn: parent
                            text: (racine.wAfficherFaits ? "✓ " : "✕ ") + "Tâches cochées"
                            color: racine.wAfficherFaits ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.poserOption("afficher_faits", racine.wAfficherFaits ? "false" : "true")
                        }
                    }
                }

                // Rendu spécifique du widget Visualiseur
                Flow {
                    visible: racine.aOptionViz
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: [
                            { code: "",        nom: "Défaut" },
                            { code: "onde",    nom: "Onde" },
                            { code: "ruban",   nom: "Ruban" },
                            { code: "liquide", nom: "Liquide" },
                            { code: "barres",  nom: "Barres" },
                            { code: "miroir",  nom: "Miroir" },
                            { code: "pics",    nom: "Crêtes" },
                            { code: "blocs",   nom: "LED" },
                            { code: "spectre", nom: "Spectre" }
                        ]

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: racine.wVizStyle === modelData.code
                            width: vizOptLbl.implicitWidth + 14
                            height: 22
                            radius: Theme.globalRadius
                            color: choisi ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent
                            Text {
                                id: vizOptLbl
                                anchors.centerIn: parent
                                text: (choisi ? "✓ " : "") + modelData.nom
                                color: choisi ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: choisi
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: racine.poserOption("viz_style", modelData.code)
                            }
                        }
                    }
                }

                // Rafraîchissement (widgets connectés)
                Row {
                    visible: racine.aOptionRefresh
                    width: parent.width
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Rafraîchir :"
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Theme.text2xs
                    }
                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        value: racine.wRefreshMin
                        minimumValue: 1
                        maximumValue: 120
                        stepSize: 1
                        suffix: " min"
                        onValueModified: newVal => racine.poserOption("refresh_min", newVal)
                    }
                }

                // Ville (météo / combo)
                Row {
                    visible: racine.aOptionVille
                    width: parent.width
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Ville :"
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Theme.text2xs
                    }
                    Rectangle {
                        width: parent.width - 88
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant
                        border.width: 1
                        border.color: cityInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                        TextInput {
                            id: cityInput
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            text: racine.wCity
                            color: Theme.fg
                            font.pixelSize: Theme.text2xs
                            clip: true
                            onAccepted: racine.poserOption("city", text.trim())
                        }
                    }
                    Rectangle {
                        width: 36
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "OK"
                            color: Theme.bg
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.poserOption("city", cityInput.text.trim())
                        }
                    }
                }

                // Image (sticker)
                Row {
                    visible: racine.aOptionImage
                    width: parent.width
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Image :"
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Theme.text2xs
                    }
                    Rectangle {
                        width: parent.width - 96
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant
                        border.width: 1
                        border.color: imgInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                        TextInput {
                            id: imgInput
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            text: racine.wImage
                            color: Theme.fg
                            font.pixelSize: Theme.text2xs
                            clip: true
                            onAccepted: racine.poserOption("image", text.trim())
                        }
                    }
                    Rectangle {
                        width: 36
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "OK"
                            color: Theme.bg
                            font.pixelSize: Theme.text2xs
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: racine.poserOption("image", imgInput.text.trim())
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: racine.ouvert
        windows: [fenetre]
        onCleared: racine.fermer()
    }
}
