import QtQuick
import "."
import Quickshell
import Quickshell.Io

// APPLET MISES À JOUR — combien de paquets attendent, quelle que soit la distribution.
//
// Le gestionnaire est détecté au démarrage : `pacman` (Arch, avec `checkupdates`
// et `yay -Qua` pour AUR) ou `dnf` (Fedora). Rien n'est codé pour une seule
// distribution : la commande de comptage et celle de mise à jour suivent le
// gestionnaire trouvé : le même applet sert sur Arch et sur Fedora.
//
// Clic gauche : ouvrir la mise à jour dans le terminal par défaut ; clic droit :
// revérifier tout de suite.
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

    // "arch" | "dnf" | "apt" — partagés via SystemServices pour éviter les appels concurrents.
    readonly property string gestionnaire: SystemServices.majGestionnaire
    property string terminal: "ghostty"
    readonly property int nombre: SystemServices.majNombre
    readonly property bool pret: SystemServices.majPret

    // Sans gestionnaire connu, l'applet n'a rien à dire : il s'efface.
    // Si `Theme.majSeulementSiDispo` est activé, on masque l'applet tant qu'il n'y a aucune MAJ.
    // Attention : `implicitWidth` doit dépendre de `doitAfficher` et non de `visible`,
    // car `Applet.qml` masque le parent (`efface_vide`) tant que `implicitWidth <= 0`,
    // ce qui maintiendrait `visible === false` en boucle fermée.
    readonly property bool disponible: gestionnaire !== ""
    readonly property bool masqueSansMaj: Theme.majSeulementSiDispo && (!pret || nombre <= 0)
    readonly property bool doitAfficher: disponible && !masqueSansMaj
    visible: doitAfficher

    implicitWidth: doitAfficher ? (rangee.implicitWidth + Math.round(10 * echelle)) : 0
    implicitHeight: Math.max(20, Math.round(26 * echelle))

    function verifier() {
        SystemServices.verifierMaj()
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

    Component.onCompleted: SystemServices.majActif = true

    function lancerMaj() {
        SystemServices.lancerMaj()
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
                size: root.tailleIcone
                color: root.nombre > 0 ? Theme.warn : Theme.fg
                opacityLevel: root.nombre > 0 ? 1 : 0.6
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.nombre > 0 && !root.verticale
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
