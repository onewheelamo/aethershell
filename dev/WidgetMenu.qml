import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."

// ════════════════════════════════════════════════════════════════════════════
// MENU D'UN WIDGET DE BUREAU — clic milieu
// ════════════════════════════════════════════════════════════════════════════
// Deux choses seulement, parce qu'un widget de bureau n'a rien d'autre à régler
// ici : le retirer, et choisir sur quels bureaux il s'affiche. Le reste (taille,
// position, opacité, options propres) vit dans le panneau de configuration.
//
// C'est une fenêtre de couche, pas un `Popup.qml` : celui-ci s'ancre à un item de
// barre et se pose sous la barre, ce qui n'a aucun sens ici. La position vient
// des coordonnées du widget.
//
// Fermeture : attrapeur de focus de Hyprland, comme les menus d'applet — un clic
// ailleurs referme, sans fenêtre plein écran qui avalerait le clic.
Item {
    id: racine

    property bool ouvert: false
    property var widget: ({})
    property real xEcran: 0
    property real yEcran: 0
    signal fermer()

    // 0 = tous les bureaux. La liste va jusqu'à dix, comme les binds du shell.
    readonly property var bureaux: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    readonly property var choisis: {
        const w = racine.widget || ({})
        const brut = (w.workspaces && w.workspaces.length > 0)
            ? w.workspaces : [Number(w.workspace)]
        return brut.map(Number)
    }

    readonly property bool tous: choisis.indexOf(0) >= 0

    function estChoisi(n) {
        if (racine.tous) return n === 0
        return racine.choisis.indexOf(n) >= 0
    }

    // Coche ou décoche un bureau. « Tous » est exclusif : le choisir vide la
    // liste et ne garde que 0. Décocher le dernier bureau laisse tomber sur
    // « tous » plutôt que sur un widget invisible dont on ne saurait plus rien.
    function basculer(n) {
        let liste
        if (n === 0) {
            liste = [0]
        } else if (racine.tous) {
            liste = [n]
        } else {
            liste = racine.choisis.filter(x => x !== 0 && x !== n)
            if (racine.choisis.indexOf(n) < 0) liste.push(n)
            liste.sort((a, b) => a - b)
            if (liste.length === 0) liste = [0]
        }
        racine.ecrireBureaux(liste.join(","))
    }

    Process { id: ecrire }

    function ecrireBureaux(spec) {
        ecrire.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                          "widget_workspaces", String((racine.widget || {}).id || ""), spec]
        ecrire.running = true
    }

    function retirer() {
        ecrire.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                          "widget_remove", String((racine.widget || {}).id || "")]
        ecrire.running = true
        racine.fermer()
    }

    PanelWindow {
        id: fenetre
        visible: racine.ouvert
        color: "transparent"
        implicitWidth: 320
        implicitHeight: carte.implicitHeight

        readonly property int marge: 8
        readonly property int largeurEcran: fenetre.screen ? fenetre.screen.width : 1920
        readonly property int hauteurEcran: fenetre.screen ? fenetre.screen.height : 1080

        anchors { top: true; left: true }
        // Sous le widget, sans sortir de l'écran : le menu suit le clic, un
        // menu collé dans un coin obligerait à chercher où il est apparu.
        margins.top: Math.round(Math.max(marge, Math.min(racine.yEcran + 64,
                                                          hauteurEcran - implicitHeight - marge)))
        margins.left: Math.round(Math.max(marge, Math.min(racine.xEcran,
                                                          largeurEcran - implicitWidth - marge)))

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-menu-widget"

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: colonne.implicitHeight + 24
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: colonne
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    width: parent.width
                    text: String((racine.widget || {}).type || "widget")
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                // Retirer : geste destructif, donc en rouge et jamais coché par
                // défaut — une seule ligne, pas de confirmation en deux temps.
                Rectangle {
                    width: parent.width
                    height: 26
                    radius: Theme.globalRadius
                    color: retireMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.45)
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Retirer du bureau"
                        color: Theme.error
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        id: retireMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: racine.retirer()
                    }
                }

                Text {
                    width: parent.width
                    text: "Afficher sur :"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                    font.bold: true
                    font.letterSpacing: 0.5
                    font.capitalization: Font.AllUppercase
                }

                // Une pastille par bureau ; « Tous » d'abord, parce que c'est le
                // choix par défaut et le plus fréquent.
                Flow {
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: racine.bureaux

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: racine.estChoisi(modelData)
                            width: modelData === 0 ? 48 : 26
                            height: 22
                            radius: Theme.globalRadius
                            color: choisi ? Theme.accent : "transparent"
                            border.color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData === 0 ? "Tous" : String(modelData)
                                color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                font.bold: parent.choisi
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: racine.basculer(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: racine.ouvert
        windows: [fenetre]
        onCleared: racine.fermer()
    }
}
