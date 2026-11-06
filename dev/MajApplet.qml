import QtQuick
import "."
import Quickshell
import Quickshell.Io

// APPLET MISES À JOUR — combien de paquets attendent, quelle que soit la distribution.
//
// Le gestionnaire est détecté au démarrage : `pacman` (Arch, avec `checkupdates`
// et `yay -Qua` pour AUR) ou `dnf` (Fedora). Rien n'est codé pour une seule
// distribution : la commande de comptage et celle de mise à jour suivent le
// gestionnaire trouvé, ce qui permet d'installer le même shell sur portable.
//
// Clic gauche : ouvrir la mise à jour dans le terminal par défaut ; clic droit :
// revérifier tout de suite.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    // "arch" | "dnf" — vide tant que la détection n'a pas répondu.
    property string gestionnaire: ""
    property string terminal: "ghostty"
    property int nombre: 0
    property bool pret: false

    // Sans gestionnaire connu, l'applet n'a rien à dire : il s'efface.
    readonly property bool disponible: gestionnaire !== ""
    visible: disponible

    implicitWidth: rangee.implicitWidth + Math.round(10 * echelle)
    implicitHeight: Math.max(20, Math.round(26 * echelle))

    function verifier() {
        if (verif.running) return
        verif.running = true
    }

    // Terminal par défaut : même table que les autres programmes (app_vars.json).
    FileView {
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                const t = String(d.Terminal || "").trim()
                if (t !== "") root.terminal = t
            } catch (e) { /* fichier en cours d'écriture */ }
        }
    }

    Component.onCompleted: detection.running = true

    Process {
        id: detection
        // Les deux ne cohabitent jamais : on garde celui qui répond.
        command: ["sh", "-c", "command -v pacman >/dev/null && echo arch; command -v dnf >/dev/null && echo dnf"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lignes = text.trim().split("\n").map(function (s) { return s.trim() })
                for (let i = 0; i < lignes.length; ++i) {
                    if (lignes[i] === "arch" || lignes[i] === "dnf") {
                        root.gestionnaire = lignes[i]
                        break
                    }
                }
                if (root.disponible) {
                    root.verifier()
                    delai.running = true
                }
            }
        }
    }

    Timer {
        id: delai
        interval: 300000     // 5 min : le comptage interroge le réseau
        repeat: true
        onTriggered: root.verifier()
    }

    // Une seule ligne de compte : la liste elle-même n'intéresse pas la barre.
    Process {
        id: verif
        command: ["sh", "-c", root.gestionnaire === "dnf"
                  // dnf sort 100 quand il y a des mises à jour ; la sortie liste
                  // « paquet.arch  version  dépôt ». On compte ces lignes-là, pas
                  // l'en-tête « Obsoleting Packages ».
                  ? "timeout 60 dnf -q check-update 2>/dev/null | grep -cE '^[A-Za-z0-9][A-Za-z0-9_.+-]*\\.'"
                  : "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^[[:space:]]*$' | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.nombre = isNaN(n) ? 0 : n
                root.pret = true
            }
        }
    }

    function lancerMaj() {
        if (root.gestionnaire === "dnf")
            Quickshell.execDetached([root.terminal, "-e", "sudo dnf upgrade --refresh"])
        else
            Quickshell.execDetached([root.terminal, "-e", "arch-update"])
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

            // Icône neutre : « arch » ne dirait rien sur Fedora.
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "download"
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
                else root.lancerMaj()
            }
        }
    }
}
