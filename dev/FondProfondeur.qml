import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Fond de bureau « en profondeur » : plusieurs calques du même fond d'écran,
// décalés différemment quand on change de bureau (parallaxe de quelques pixels),
// et de plus en plus nets du lointain au proche.
//
// Ce qui manque à l'idée d'origine, et qu'on ne peut pas coder : les images
// découpées avec alpha. Sans elles, les calques sont des bandes de la même
// image, masquées en dégradé — l'illusion tient au flou et au décalage, pas à
// une vraie découpe. Le jour où les assets existent, il suffit de remplacer les
// `source` des trois Image : chacun a son propre facteur de parallaxe.
//
// Autre limite de plateforme, à dire : « les îlots entre les calques » n'est pas
// réalisable. layer-shell n'offre que background < bottom < fenêtres < top <
// overlay ; un calque ne peut donc pas passer entre la barre et les fenêtres.
// Le calque proche reste derrière les fenêtres, la barre au-dessus de tout.
PanelWindow {
    id: fenetre

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    aboveWindows: false
    visible: Theme.depthWallpaper
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "shell-fond-profondeur"

    // Le bureau courant donne le pas de parallaxe : chaque changement décale les
    // calques d'un cran, sans animation continue (le fond ne bouge pas tout seul).
    readonly property int bureau: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1
    property string fond: ""

    Process {
        id: sonde
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) fenetre.fond = m[1]
            }
        }
    }

    // Deux calques seulement : le fond du démon (awww) reste la base nette, et
    // les bandes basses ajoutent la parallaxe. Un troisième calque plein écran
    // flouté recouvrait tout le bureau d'un voile mou — mesuré à l'écran, écarté.
    readonly property var calques: [
        { facteur: 7,  flou: 0.30, bande: 0.55, teinte: 0.05 },
        { facteur: 10, flou: 0.00, bande: 0.30, teinte: 0.00 }
    ]

    Repeater {
        model: fenetre.calques

        Item {
            id: calque
            required property var modelData
            required property int index

            // Décalage proportionnel au bureau : 1 -> 0, 5 -> 4 pas, etc.
            readonly property real decalage: (fenetre.bureau - 1) * modelData.facteur
            readonly property real hauteurBande: fenetre.height * modelData.bande

            anchors.left: parent.left
            anchors.right: parent.right
            y: fenetre.height - hauteurBande
            height: hauteurBande
            clip: true

            Image {
                id: imageCalque
                // Le calque est agrandi pour que le décalage ne découvre pas de vide.
                width: fenetre.width + 40
                height: fenetre.height + 40
                x: -20 - calque.decalage
                y: -calque.y - 20 + calque.decalage
                source: fenetre.fond !== "" ? "file://" + fenetre.fond : ""
                sourceSize.width: Math.max(320, Math.round(fenetre.width / 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
                layer.enabled: true
                // Parallaxe animée : un changement de bureau fait glisser le
                // calque de quelques pixels, pas d'un bond.
                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            }

            MultiEffect {
                anchors.fill: parent
                source: imageCalque
                blurEnabled: calque.modelData.flou > 0.01
                blur: calque.modelData.flou
                blurMax: 64
                saturation: 1.0 - calque.modelData.teinte
                visible: calque.modelData.flou > 0.01
            }

            // Sans flou (calque proche), l'image se dessine directement.
            Image {
                anchors.fill: parent
                visible: calque.modelData.flou <= 0.01
                source: fenetre.fond !== "" ? "file://" + fenetre.fond : ""
                sourceSize.width: Math.max(320, Math.round(fenetre.width / 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }

            // Dégradé de raccord avec le calque du dessous, pour éviter une
            // ligne franche entre deux bandes.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.min(120, calque.height * 0.4)
                visible: calque.modelData.bande < 1.0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.bg, 0.0) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.55) }
                }
            }

            // Parallaxe animée : un changement de bureau fait glisser le calque
            // de quelques pixels, pas d'un bond.
            Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }
    }
}
