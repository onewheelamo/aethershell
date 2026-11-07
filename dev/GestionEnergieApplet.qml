import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET GESTION DE L'ÉNERGIE — batterie, limite de charge, luminosité.
//
// Ce que l'applet « alimentation » portait en plus de ses cinq gestes de session
// vit ici, et seulement ici : niveau de batterie et état de charge, limite de
// charge à 80 % (santé de la cellule), curseur de luminosité. Deux sujets
// distincts, deux panneaux — un menu d'extinction n'a pas à dessiner une jauge
// de batterie, et une jauge n'a rien à faire dans un menu qu'on ouvre pour
// éteindre la machine.
//
// Sur une tour, rien de tout cela n'existe : le panneau le dit au lieu de
// s'ouvrir vide. Sur un portable, les deux blocs apparaissent.
//
// Les commandes restent `core/system_service.py` (info / brightness / limit) :
// une seule source pour le matériel, la même que celle de l'applet luminosité.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property string hote: ""
    readonly property bool ouvert: Theme.activePopup === "applet:gestion-energie"

    property bool batPresente: false
    property int batPourcent: 0
    property string batEtat: ""
    property bool batLimite: false
    property bool briPresente: false
    property int briPourcent: 100

    readonly property real cote: Math.max(18, Math.round(Theme.barHeight * 0.70 * echelle))

    readonly property bool vide: !batPresente && !briPresente

    // Icône du bouton : la batterie quand elle existe (et son état), sinon le
    // rétroéclairage, sinon le contour de batterie — une tour garde ainsi une
    // icône qui dit de quoi il s'agit au lieu d'un carré muet.
    readonly property string glyphe: {
        if (batPresente) {
            if (batEtat === "Charging" || batEtat === "Full") return "battery-charging"
            if (batPourcent <= 10) return "battery-10"
            if (batPourcent <= 25) return "battery-25"
            if (batPourcent <= 50) return "battery-50"
            if (batPourcent <= 70) return "battery-70"
            return "battery-full"
        }
        return briPresente ? "brightness" : "battery-outline"
    }

    implicitWidth: cote
    implicitHeight: cote

    Process {
        running: true
        command: ["sh", "-c", "cat /proc/sys/kernel/hostname"]
        stdout: StdioCollector {
            onStreamFinished: root.hote = text.trim()
        }
    }

    function relire() {
        if (infos.running) return
        infos.running = true
    }

    // `system_service.py info` donne batterie (niveau, état, limite 80 %) et
    // luminosité en une seule lecture : inutile d'ouvrir trois sources.
    Process {
        id: infos
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim()) || {}
                    root.batPresente = Boolean(d.has_battery)
                    if (d.battery) {
                        root.batPourcent = Number(d.battery.level || 0)
                        root.batEtat = String(d.battery.status || "")
                        root.batLimite = Boolean(d.battery.limit_80)
                    }
                    root.briPresente = Boolean(d.has_backlight)
                    if (typeof d.brightness === "number") root.briPourcent = d.brightness
                } catch (e) { /* lecture illisible : on garde l'état précédent */ }
            }
        }
    }

    Process {
        id: action
        onExited: root.relire()
    }

    function reglerLuminosite(pct) {
        root.briPourcent = Math.max(1, Math.min(100, Math.round(pct)))
        action.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                          "brightness", String(root.briPourcent)]
        action.running = true
    }

    function basculerLimite() {
        const cible = root.batLimite ? 100 : 80
        root.batLimite = !root.batLimite
        action.command = ["python3", Quickshell.shellPath("core/system_service.py"),
                          "limit", String(cible)]
        action.running = true
    }

    // ── bouton de barre ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Math.min(Theme.globalRadius, Math.round(root.cote / 2))
        color: root.ouvert
            ? Theme.accent
            : (souris.containsMouse ? Qt.alpha(Theme.accent, 0.16) : "transparent")
        border.color: root.ouvert ? Theme.accent : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }

        Icon {
            anchors.centerIn: parent
            glyph: root.glyphe
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.ouvert
                ? Theme.bg
                : (root.batPresente && root.batPourcent <= 15 ? Theme.warn : Theme.fg)
            opacityLevel: root.ouvert ? 1 : 0.85
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("applet:gestion-energie")
        }
    }

    // ── panneau ─────────────────────────────────────────────────────────────
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

                // En-tête : titre à gauche, machine à droite — même dessin que le
                // panneau « Session », pour que les deux panneaux se lisent pareil.
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

                // Tour : ni batterie ni rétroéclairage. Le dire vaut mieux que
                // d'ouvrir une carte vide sans explication.
                Text {
                    width: parent.width
                    visible: root.vide
                    text: "Cette machine n'a ni batterie ni rétroéclairage : rien à régler ici."
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                // ── batterie ────────────────────────────────────────────────
                Row {
                    width: parent.width
                    spacing: 8
                    visible: root.batPresente

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.glyphe
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

                // Limite de charge (80 %) : la même commande que l'ancien panneau.
                // `Item` et non `Row` : l'interrupteur est ancré à droite.
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

                // ── luminosité ──────────────────────────────────────────────
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
        if (root.ouvert) { root.relire(); delaiGrab.restart() }
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
        onCleared: if (Theme.activePopup === "applet:gestion-energie") Theme.activePopup = ""
    }
}
