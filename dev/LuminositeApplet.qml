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

    Component.onCompleted: root.lire()

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
        onClicked: Theme.togglePopup("applet:alimentation")
    }
}
