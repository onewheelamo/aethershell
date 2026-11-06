import QtQuick
import "."
import Quickshell
import Quickshell.Io

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

    property bool batPresente: false
    property int batPourcent: 0
    property bool batCharge: false
    property bool briPresente: false
    property int briPourcent: 100
    property bool pret: false

    readonly property bool batterie: batPresente

    implicitWidth: rangee.implicitWidth
    implicitHeight: rangee.implicitHeight

    function lire() {
        if (lecture.running) return
        lecture.running = true
    }

    Component.onCompleted: { root.lire(); root.lireNuit() }

    // État du mode nuit, puis application de la plage horaire s'il y en a une :
    // `appliquer` ne fait rien tant que la plage est vide.
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
        command: ["python3", Quickshell.shellPath("core/nuit_service.py"), "appliquer"]
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
                        root.batCharge = (st === "Charging" || st === "Full")
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
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.nuitAllumee ? Theme.accent : Theme.fg
            opacityLevel: root.nuitAllumee ? 1 : (root.nuitPlage ? 0.75 : 0.5)
        }

        // Batterie : priorité sur la luminosité quand la machine en a une.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batterie
            glyph: root.batCharge ? "battery-charging" : "battery-70"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
            opacityLevel: root.pret ? 0.92 : 0.4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batterie
            text: root.pret && root.batterie ? root.batPourcent + " %" : ""
            color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }

        // Luminosité : seule information sur une tour, complémentaire sur un
        // portable — on la garde dans les deux cas, discrète.
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente
            glyph: "brightness"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: Theme.fg
            opacityLevel: root.pret ? 0.75 : 0.35
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente
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
            // alimentation, qui garde les curseurs de luminosité et de charge.
            if (mouse.x <= root.nuitLargeur) root.basculerNuit()
            else Theme.togglePopup("applet:alimentation")
        }
    }
}
