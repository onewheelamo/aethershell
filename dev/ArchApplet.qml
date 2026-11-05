import QtQuick
import "."
import Quickshell
import Quickshell.Io

// APPLET MISES À JOUR — combien de paquets attendent.
//
// Composant QML : il lance lui-même `checkupdates` / `yay -Qua` et ne dépend
// plus du minuteur de l'îlot. Clic gauche : ouvrir la mise à jour dans un
// terminal ; clic droit : revérifier tout de suite.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property int nombre: 0
    property bool pret: false
    // Sans `arch-update` installé, l'applet n'a rien à dire : il s'efface.
    property bool disponible: false

    visible: disponible

    implicitWidth: rangee.implicitWidth + Math.round(10 * echelle)
    implicitHeight: Math.max(20, Math.round(26 * echelle))

    function verifier() {
        if (verif.running) return
        verif.running = true
    }

    Component.onCompleted: presence.running = true

    Process {
        id: presence
        command: ["sh", "-c", "command -v arch-update >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.disponible = (text.trim() === "1")
                if (root.disponible) {
                    root.verifier()
                    delai.running = true
                }
            }
        }
    }

    Timer {
        id: delai
        interval: 300000     // 5 min : `checkupdates` interroge le réseau
        repeat: true
        onTriggered: root.verifier()
    }

    // Une seule ligne de compte : la liste elle-même n'intéresse pas la barre.
    Process {
        id: verif
        command: ["sh", "-c", "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^\\s*$' | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.nombre = isNaN(n) ? 0 : n
                root.pret = true
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.globalRadius
        color: souris.containsMouse ? Theme.surfaceVariant : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            id: rangee
            anchors.centerIn: parent
            spacing: Math.round(4 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "arch"
                size: Math.max(11, Math.round(Theme.iconSm * echelle))
                color: root.nombre > 0 ? Theme.warn : Theme.fg
                opacityLevel: root.nombre > 0 ? 1 : 0.6
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.nombre > 0
                text: String(root.nombre)
                color: Theme.accent
                font.pixelSize: Math.round(Theme.textXs * echelle)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) root.verifier()
                else Quickshell.execDetached(["kitty", "arch-update"])
            }
        }
    }
}
