import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET LUMINOSITÉ — réglage de luminosité (slider) et mode nuit.
// La batterie vit désormais dans son propre applet (« batterie », BatterieApplet.qml).
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    // Mode nuit : filtre chaud.
    property bool nuitAllumee: false
    property int nuitTemperature: 4000
    property bool nuitPlage: false
    property string nuitDe: ""
    property string nuitA: ""
    readonly property real nuitLargeur: Math.max(14, Math.round(16 * echelle))

    property string hote: ""
    property bool briPresente: false
    property int briPourcent: 100
    property bool pret: false

    readonly property bool ouvert: Theme.activePopup === "applet:luminosite"

    implicitWidth: rangee.implicitWidth
    implicitHeight: rangee.implicitHeight

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

    function reglerLuminosite(pct) {
        root.briPourcent = Math.max(1, Math.min(100, Math.round(pct)))
        actionEnergie.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                                 "brightness", String(root.briPourcent)]
        actionEnergie.running = true
    }

    Component.onCompleted: {
        root.synchroniserSystemInfo()
        root.lireNuit()
    }

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

    function synchroniserSystemInfo() {
        const d = Theme.systemInfo || ({})
        if (!Theme.systemInfoPret && Object.keys(d).length === 0) return
        if (d.hostname) root.hote = String(d.hostname)
        root.briPresente = Boolean(d.has_backlight)
        if (typeof d.brightness === "number") root.briPourcent = d.brightness
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
            glyph: "weather-night"
            size: root.tailleIcone
            color: root.nuitAllumee ? Theme.accent : Theme.fg
            opacityLevel: root.nuitAllumee ? 1 : (root.nuitPlage ? 0.75 : 0.5)
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente && !root.verticale
            glyph: "brightness"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: Theme.fg
            opacityLevel: root.pret ? 0.85 : 0.4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.briPresente && !root.verticale
            text: root.pret && root.briPresente ? root.briPourcent + " %" : ""
            color: Qt.alpha(Theme.fg, 0.9)
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.x <= root.nuitLargeur) root.basculerNuit()
            else Theme.togglePopup("applet:luminosite")
        }
        onWheel: wheel => {
            if (!root.briPresente) return
            const pas = wheel.angleDelta.y > 0 ? 5 : -5
            root.reglerLuminosite(root.briPourcent + pas)
        }
    }

    // ── panneau de luminosité (slider) & mode nuit ──────────────────────────
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
                        text: "Luminosité"
                        color: Theme.fg
                        font.pixelSize: Theme.textMd
                        font.bold: true
                        font.letterSpacing: 0.4
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.briPresente ? (root.briPourcent + " %") : root.hote
                        color: root.briPresente ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textSm
                        font.bold: root.briPresente
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Text {
                    width: parent.width
                    visible: !root.briPresente
                    text: "Aucun rétroéclairage matériel détecté sur cette machine."
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    spacing: 10
                    visible: root.briPresente

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "brightness"
                        size: Theme.iconSm
                        color: Theme.accent
                    }

                    Item {
                        id: sliderContainer
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.iconSm - 10
                        height: 24

                        Rectangle {
                            id: pisteBri
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 10
                            radius: Theme.globalRadius
                            color: Theme.surfaceVariant

                            Rectangle {
                                width: Math.max(0, Math.min(1, root.briPourcent / 100)) * parent.width
                                height: parent.height
                                radius: Theme.globalRadius
                                color: Theme.accent
                            }
                        }

                        Rectangle {
                            id: curseurBri
                            width: 16
                            height: 16
                            radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(sliderContainer.width - width,
                                (root.briPourcent / 100) * sliderContainer.width - width / 2))
                            color: Theme.fg
                            border.width: 2
                            border.color: Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function appliquer(mx) {
                                root.reglerLuminosite(Math.max(0, Math.min(1, mx / sliderContainer.width)) * 100)
                            }
                            onPressed: mouse => appliquer(mouse.x)
                            onPositionChanged: mouse => { if (pressed) appliquer(mouse.x) }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 24

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "weather-night"
                            size: Theme.iconSm
                            color: root.nuitAllumee ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Mode nuit (" + root.nuitTemperature + " K)"
                            color: Qt.alpha(Theme.fg, 0.9)
                            font.pixelSize: Theme.textXs
                        }
                    }

                    Rectangle {
                        width: 56
                        height: 22
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: root.nuitAllumee ? Theme.accent : Theme.bg
                        border.color: root.nuitAllumee ? Theme.accent : Theme.accentMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.nuitAllumee ? "Actif" : "Off"
                            color: root.nuitAllumee ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.basculerNuit()
                        }
                    }
                }
            }
        }
    }

    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) { root.lire(); root.lireNuit(); delaiGrab.restart() }
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
