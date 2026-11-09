import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET LUMINOSITÉ & BATTERIE — deux états matériels, un seul élément.
//
// Il ne fait qu'afficher : le réglage vit dans l'applet « alimentation », qui a
// déjà les curseurs de luminosité et la limite de charge. Un clic ici ouvre donc
// son panneau plutôt que d'en dupliquer un troisième.
//
// Sur une tour il n'y a pas de batterie : l'applet montre alors la luminosité.
// Sur un portable, la batterie passe devant — c'est elle qu'on surveille.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    // Barre de côté : une seule icône, agrandie, et pas de texte — une valeur
    // coupée au milieu se lit mal. Le nom de l'applet est au survol, le détail
    // dans le popup. `Applet.qml` pose la propriété si elle existe.
    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    // Mode nuit : filtre chaud. Sur la tour, c'est le seul contenu de l'applet
    // avec la luminosité ; sur le portable, il accompagne la batterie.
    property bool nuitAllumee: false
    property int nuitTemperature: 4000
    property bool nuitPlage: false
    property string nuitDe: ""
    property string nuitA: ""
    // Largeur réservée à l'icône : le clic y bascule le mode nuit au lieu
    // d'ouvrir le panneau alimentation (un seul MouseArea sur l'applet).
    readonly property real nuitLargeur: Math.max(14, Math.round(16 * echelle))

    property string hote: ""
    property bool batPresente: false
    property int batPourcent: 0
    property bool batCharge: false
    property string batEtat: ""
    property bool batLimite: false
    property bool briPresente: false
    property int briPourcent: 100
    property bool pret: false

    readonly property bool batterie: batPresente
    readonly property bool ouvert: Theme.activePopup === "applet:luminosite"
    readonly property bool vide: !batPresente && !briPresente

    readonly property string glypheBatterie: {
        if (!batPresente) return briPresente ? "brightness" : "battery-outline"
        if (batCharge) return "battery-charging"
        if (batPourcent <= 10) return "battery-10"
        if (batPourcent <= 25) return "battery-25"
        if (batPourcent <= 50) return "battery-50"
        if (batPourcent <= 70) return "battery-70"
        return "battery-full"
    }

    implicitWidth: rangee.implicitWidth
    implicitHeight: rangee.implicitHeight

    Process {
        running: true
        command: ["sh", "-c", "cat /proc/sys/kernel/hostname"]
        stdout: StdioCollector {
            onStreamFinished: root.hote = text.trim()
        }
    }

    function lire() {
        if (lecture.running) return
        lecture.running = true
    }

    Process {
        id: actionEnergie
        onExited: root.lire()
    }

    function reglerLuminosite(pct) {
        root.briPourcent = Math.max(1, Math.min(100, Math.round(pct)))
        actionEnergie.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                                 "brightness", String(root.briPourcent)]
        actionEnergie.running = true
    }

    function basculerLimite() {
        const cible = root.batLimite ? 100 : 80
        root.batLimite = !root.batLimite
        actionEnergie.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                                 "limit", String(cible)]
        actionEnergie.running = true
        Theme.activePopup = ""
    }

    Component.onCompleted: { root.lire(); root.lireNuit() }

    // État du mode nuit. La **plage horaire** ne s'applique plus d'ici : le
    // minuteur vit dans `main.qml`, qui est toujours monté, alors qu'un applet
    // peut être retiré des barres — l'automatisme disparaissait alors en
    // silence. Ici on ne fait que lire l'état pour l'afficher.
    Timer {
        id: relanceNuit
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.lireNuit()
    }

    function lireNuit() {
        if (nuitProc.running) return
        nuitProc.running = true
    }

    function majNuit(txt) {
        try {
            const d = JSON.parse(txt.trim())
            root.nuitAllumee = d.allume === true
            if (typeof d.temperature === "number") root.nuitTemperature = d.temperature
            root.nuitPlage = d.plage === true
            root.nuitDe = String(d.de || "")
            root.nuitA = String(d.a || "")
        } catch (e) { /* réponse partielle : on garde l'état précédent */ }
    }

    function basculerNuit() {
        nuitAction.command = ["python3", Quickshell.shellPath("core/nuit_service.py"), "basculer"]
        nuitAction.running = true
    }

    Process {
        id: nuitProc
        // Lecture seule : l'application de la plage vit dans `main.qml`.
        command: ["python3", Quickshell.shellPath("core/nuit_service.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: root.majNuit(text)
        }
    }

    Process {
        id: nuitAction
        stdout: StdioCollector {
            onStreamFinished: root.majNuit(text)
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.lire()
    }

    Process {
        id: lecture
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim()) || {}
                    root.batPresente = Boolean(d.has_battery)
                    if (d.battery) {
                        root.batPourcent = Number(d.battery.level || 0)
                        const st = String(d.battery.status || "")
                        root.batEtat = st
                        root.batCharge = (st === "Charging" || st === "Full")
                        root.batLimite = Boolean(d.battery.limit_80)
                    }
                    root.briPresente = Boolean(d.has_backlight)
                    if (typeof d.brightness === "number") root.briPourcent = d.brightness
                    root.pret = true
                } catch (e) { /* lecture illisible : on garde l'état précédent */ }
            }
        }
    }

    Row {
        id: rangee
        spacing: Math.max(4, Math.round(Theme.space2 * root.echelle))

        // Mode nuit : toujours en tête, c'est le geste du soir. Son clic est
        // traité par le MouseArea unique de l'applet, qui teste la zone.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.nuitPlage ? "weather-night" : "weather-night"
            size: root.tailleIcone
            color: root.nuitAllumee ? Theme.accent : Theme.fg
            opacityLevel: root.nuitAllumee ? 1 : (root.nuitPlage ? 0.75 : 0.5)
        }

        // Batterie et luminosité n'ont pas leur place dans une bande de côté :
        // il n'y resterait que des valeurs coupées. La lune seule y suffit,
        // le reste est dans le panneau alimentation.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batterie && !root.verticale
            glyph: root.batCharge ? "battery-charging" : "battery-70"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
            opacityLevel: root.pret ? 0.92 : 0.4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batterie && !root.verticale
            text: root.pret && root.batterie ? root.batPourcent + " %" : ""
            color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }

        // Luminosité : seule information sur une tour, complémentaire sur un
        // portable — on la garde dans les deux cas, discrète.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente && !root.verticale
            glyph: "brightness"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: Theme.fg
            opacityLevel: root.pret ? 0.75 : 0.35
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente && !root.verticale
            text: root.pret && root.briPresente ? root.briPourcent + " %" : ""
            color: Qt.alpha(Theme.fg, 0.85)
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            // Première zone = l'icône de mode nuit ; ailleurs, le panneau
            // d'énergie intégré à l'applet (indépendant de la présence ou non
            // de l'applet gestion-energie dans bar_applets.json).
            if (mouse.x <= root.nuitLargeur) root.basculerNuit()
            else Theme.togglePopup("applet:luminosite")
        }
    }

    // ── panneau d'énergie ───────────────────────────────────────────────────
    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "droite"
        id: menu
        implicitWidth: 340
        implicitHeight: carte.implicitHeight
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: colonne.implicitHeight + 32
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: colonne
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Item {
                    width: parent.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Énergie"
                        color: Theme.fg
                        font.pixelSize: Theme.textMd
                        font.bold: true
                        font.letterSpacing: 0.4
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hote
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Text {
                    width: parent.width
                    visible: root.vide
                    text: "Cette machine n'a ni batterie ni rétroéclairage : rien à régler ici."
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    spacing: 8
                    visible: root.batPresente

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.glypheBatterie
                        size: Theme.iconSm
                        color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Batterie"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.batPourcent + " %" + (root.batEtat !== "" ? " · " + root.batEtat : "")
                        color: root.batPourcent <= 15 ? Theme.warn : Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.textXs
                        font.features: { "tnum": 1 }
                    }
                }

                Item {
                    width: parent.width
                    height: 22
                    visible: root.batPresente

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Limiter la charge à 80 % (santé)"
                        color: Qt.alpha(Theme.fg, 0.9)
                        font.pixelSize: Theme.textXs
                    }

                    Rectangle {
                        width: 62
                        height: 20
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: root.batLimite ? Theme.success : Theme.bg
                        border.color: root.batLimite ? Theme.success : Theme.accentMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.batLimite ? "80 % ON" : "100 %"
                            color: root.batLimite ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.basculerLimite()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    visible: root.briPresente

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "brightness"
                        size: Theme.iconSm
                        color: Theme.accent
                    }

                    Rectangle {
                        id: pisteBri
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.iconSm - 8
                        height: 10
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: Math.max(0, Math.min(1, root.briPourcent / 100)) * parent.width
                            height: parent.height
                            radius: Theme.globalRadius
                            color: Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function appliquer(mx) {
                                root.reglerLuminosite(Math.max(0, Math.min(1, mx / pisteBri.width)) * 100)
                            }
                            onPressed: mouse => appliquer(mouse.x)
                            onPositionChanged: mouse => { if (pressed) appliquer(mouse.x) }
                        }
                    }
                }
            }
        }
    }

    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) { root.lire(); delaiGrab.restart() }
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.ouvert && root.pretGrab
        windows: Theme.fenetresGrab(menu, root)
        onCleared: if (Theme.activePopup === "applet:luminosite") Theme.activePopup = ""
    }
}
