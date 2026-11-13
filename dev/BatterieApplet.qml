import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET BATTERIE — dédié à l'état de la batterie et à la limite de charge (portables).
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    property string hote: ""
    property bool batPresente: false
    property int batPourcent: 0
    property bool batCharge: false
    property string batEtat: ""
    property bool batLimite: false
    property int batPlafond: 80
    property bool pret: false

    readonly property bool ouvert: Theme.activePopup === "applet:batterie"

    readonly property string batEtatAffiche:
        (batLimite && batPourcent >= batPlafond - 1) ? "limite atteinte" : batEtat

    readonly property string glypheBatterie: {
        if (!batPresente) return "battery-outline"
        if (batCharge) return "battery-charging"
        if (batPourcent <= 10) return "battery-10"
        if (batPourcent <= 25) return "battery-25"
        if (batPourcent <= 50) return "battery-50"
        if (batPourcent <= 70) return "battery-70"
        return "battery-full"
    }

    visible: batPresente
    implicitWidth: batPresente ? rangee.implicitWidth : 0
    implicitHeight: batPresente ? rangee.implicitHeight : 0

    function lire() {
        Theme.rafraichirSystemInfo()
    }

    Process {
        id: actionEnergie
        property string sortie: ""
        stdout: StdioCollector {
            onStreamFinished: actionEnergie.sortie = text.trim()
        }
        onExited: code => {
            let motif = ""
            try {
                const d = JSON.parse(actionEnergie.sortie)
                if (d && d.error) motif = String(d.error)
            } catch (e) { /* pas de JSON : on garde le code de sortie */ }
            if (code !== 0 && motif !== "")
                Quickshell.execDetached(["notify-send", "-a", "AetherShell",
                                         "-u", "normal",
                                         "Réglage non appliqué", motif])
            actionEnergie.sortie = ""
            root.lire()
        }
    }

    function basculerLimite() {
        const cible = root.batLimite ? 100 : 80
        root.batLimite = !root.batLimite
        root.batPlafond = cible
        actionEnergie.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                                 "limit", String(cible)]
        actionEnergie.running = true
    }

    Component.onCompleted: root.synchroniserSystemInfo()

    function synchroniserSystemInfo() {
        const d = Theme.systemInfo || ({})
        if (!Theme.systemInfoPret && Object.keys(d).length === 0) return
        if (d.hostname) root.hote = String(d.hostname)
        root.batPresente = Boolean(d.has_battery)
        if (d.battery) {
            root.batPourcent = Number(d.battery.level || 0)
            const st = String(d.battery.status || "")
            root.batEtat = st
            root.batCharge = (st === "Charging" || st === "Full")
            root.batLimite = Boolean(d.battery.limit_80)
            root.batPlafond = Number(d.battery.limit_pct || 80)
        }
        root.pret = Theme.systemInfoPret
    }

    Connections {
        target: Theme
        function onSystemInfoChanged() {
            root.synchroniserSystemInfo()
        }
    }

    Row {
        id: rangee
        spacing: Math.max(4, Math.round(Theme.space2 * root.echelle))

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.glypheBatterie
            size: root.tailleIcone
            color: root.batPourcent <= 15 ? Theme.warn : (root.batCharge ? Theme.success : Theme.fg)
            opacityLevel: root.pret ? 0.92 : 0.4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.batPresente && !root.verticale
            text: root.pret ? root.batPourcent + " %" : ""
            color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Theme.togglePopup("applet:batterie")
    }

    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "droite"
        id: menu
        implicitWidth: 320
        implicitHeight: carte.implicitHeight
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: colonne.implicitHeight + 32
            color: "transparent"
            radius: Theme.pillRadius
            border.width: 0

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
                        text: "Batterie"
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

                Row {
                    width: parent.width
                    spacing: 8

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.glypheBatterie
                        size: Theme.iconSm
                        color: root.batPourcent <= 15 ? Theme.warn : (root.batCharge ? Theme.success : Theme.accent)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.batPourcent + " %" + (root.batEtatAffiche !== "" ? " · " + root.batEtatAffiche : "")
                        color: root.batPourcent <= 15 ? Theme.warn : Theme.fg
                        font.pixelSize: Theme.textSm
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: Math.max(0, Math.min(1, root.batPourcent / 100)) * parent.width
                        height: parent.height
                        radius: 3
                        color: root.batPourcent <= 15 ? Theme.warn : (root.batCharge ? Theme.success : Theme.accent)
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Limiter la charge à " + root.batPlafond + " % (santé)"
                        color: Qt.alpha(Theme.fg, 0.9)
                        font.pixelSize: Theme.textXs
                    }

                    Rectangle {
                        width: 66
                        height: 22
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
        onCleared: if (Theme.activePopup === "applet:batterie") Theme.activePopup = ""
    }
}
