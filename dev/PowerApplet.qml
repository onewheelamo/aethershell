import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET ALIMENTATION — le bouton d'extinction et ses cinq gestes.
//
// Composant QML : le menu n'a besoin d'aucun service, seulement de lancer des
// commandes. Il emporte son bouton, son menu et son attrapeur de clic ; l'îlot
// droit n'a plus à savoir qu'il existe.
//
// Luminosité et batterie le rejoindront : ce sont les trois réglages « matériels »
// de la machine, et les garder ensemble évite un troisième menu.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property string hote: ""
    readonly property bool ouvert: Theme.activePopup === "applet:alimentation"

    readonly property real cote: Math.max(18, Math.round(Theme.barHeight * 0.70 * echelle))

    implicitWidth: cote
    implicitHeight: cote

    Process {
        command: ["sh", "-c", "cat /proc/sys/kernel/hostname"]
        stdout: StdioCollector {
            onStreamFinished: root.hote = text.trim()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.min(Theme.globalRadius, Math.round(root.cote / 2))
        color: root.ouvert
            ? Theme.error
            : (souris.containsMouse ? Qt.alpha(Theme.error, 0.16) : "transparent")
        border.color: root.ouvert ? Theme.error : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }

        Icon {
            anchors.centerIn: parent
            glyph: "power"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.ouvert ? Theme.bg : (souris.containsMouse ? Theme.error : Theme.fg)
            opacityLevel: root.ouvert ? 1 : 0.85
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("applet:alimentation")
        }
    }

    // ── menu ────────────────────────────────────────────────────────────────
    PopupWindow {
        id: menu
        anchor.item: root
        anchor.rect.x: root.width - implicitWidth
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
        implicitWidth: 280
        // Hauteur dérivée du contenu : une valeur fixe coupait la dernière ligne.
        implicitHeight: carte.implicitHeight
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: colonne.implicitHeight + 28
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.error
            border.width: 1

            Column {
                id: colonne
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "power"
                        size: Theme.iconSm
                        color: Theme.error
                        opacityLevel: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Session & Alimentation"
                        color: Theme.error
                        font.pixelSize: Theme.textLg
                        font.bold: true
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Repeater {
                    model: [
                        { icon: "lock", title: "Verrouiller la session", sub: "Protéger l'écran actif", cmd: "hyprlock || loginctl lock-session", danger: false },
                        { icon: "logout", title: "Fermer la session", sub: "Quitter Hyprland", cmd: "hyprctl dispatch 'hl.dsp.exit()' || hyprctl dispatch exit", danger: false },
                        { icon: "sleep", title: "Mise en veille", sub: "Suspendre en mémoire", cmd: "systemctl suspend", danger: false },
                        { icon: "restart", title: "Redémarrer", sub: "Relancer la machine " + root.hote, cmd: "systemctl reboot", danger: true },
                        { icon: "power", title: "Extinction", sub: "Arrêter complètement le système", cmd: "systemctl poweroff", danger: true }
                    ]

                    Rectangle {
                        id: geste
                        required property var modelData
                        width: parent.width
                        height: 46
                        radius: Theme.globalRadius
                        color: gesteMa.containsMouse
                            ? (modelData.danger ? Qt.alpha(Theme.error, 0.25) : Theme.surfaceVariant)
                            : Qt.alpha(Theme.surfaceVariant, 0.45)
                        border.color: gesteMa.containsMouse
                            ? (modelData.danger ? Theme.error : Theme.accent)
                            : "transparent"
                        border.width: 1

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: geste.modelData.icon
                                size: Theme.iconMd
                                color: geste.modelData.danger ? Theme.error : Theme.fg
                                opacityLevel: 1
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: geste.modelData.title
                                    color: geste.modelData.danger ? Theme.error : Theme.fg
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }

                                Text {
                                    text: geste.modelData.sub
                                    color: Qt.alpha(Theme.fg, 0.65)
                                    font.pixelSize: Theme.textXs
                                }
                            }
                        }

                        MouseArea {
                            id: gesteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.activePopup = ""
                                Quickshell.execDetached(["sh", "-c", geste.modelData.cmd])
                            }
                        }
                    }
                }
            }
        }
    }

    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) delaiGrab.restart()
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.ouvert && root.pretGrab
        windows: [menu]
        onCleared: if (root.ouvert) Theme.activePopup = ""
    }
}
