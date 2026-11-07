import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Calque de premier plan du fond d'écran — adaptation AetherShell de l'idée du
// plugin Noctalia `wallpaper_depth` (MIT) :
// https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth
//
// Le service `core/depth_mask.py` estime une carte de profondeur du fond courant
// (Depth Anything V2 Small, en local) et en tire un masque : blanc = devant,
// noir = derrière. Ce calque dessine ce masque **au-dessus des widgets de bureau
// et sous les fenêtres** (couche `bottom`) : les widgets apparaissent alors
// derrière les objets proches du fond — un widget posé sur la fenêtre d'un décor
// se lit à travers la vitre et disparaît derrière le cadre.
//
// Ce que ce n'est pas : un remplacement du fond. Le masque ne peint que le
// premier plan, tout le reste est transparent, donc le fond du démon reste la
// base. Un masque absent ou périmé ne casse rien : la surface ne s'affiche pas.
PanelWindow {
    id: fenetre

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    aboveWindows: false
    visible: Theme.depthMask && masque !== ""
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "shell-masque-profondeur"

    // Chemin du masque courant, et l'erreur éventuelle à ne pas cacher.
    property string masque: ""
    property string erreur: ""
    property string fondCourant: ""

    readonly property real seuil: Math.max(0, Math.min(100, Theme.depthMaskSeuil)) / 100
    readonly property real adouci: Math.max(0, Math.min(50, Theme.depthMaskAdouci)) / 100

    // Le fond courant décide de tout : masque, seuil et adoucissement.
    Process {
        id: sondeFond
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                const nouveau = m ? m[1] : ""
                if (nouveau !== fenetre.fondCourant) {
                    fenetre.fondCourant = nouveau
                    fenetre.masque = ""
                }
            }
        }
    }

    // awww ne prévient pas : on le redemande tant que le calque est actif.
    Timer {
        interval: 30000
        repeat: true
        running: Theme.depthMask
        onTriggered: if (!sondeFond.running) sondeFond.running = true
    }

    // Génération (ou relecture du cache) : le service rend le chemin du masque.
    Process {
        id: generateur
        // `command` est posée par relancer(), juste avant le lancement : liée ici,
        // elle pouvait partir avec un chemin de fond encore vide, qu'argparse
        // résolvait en « . » (le répertoire courant du shell).
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(String(text).trim())
                    if (d && d.ok && d.masque) {
                        fenetre.masque = d.masque
                        fenetre.erreur = ""
                    } else {
                        fenetre.erreur = String((d && d.error) || "masque indisponible")
                    }
                } catch (e) {
                    fenetre.erreur = "réponse illisible du générateur"
                }
            }
        }
    }

    // Déclencheurs : fond connu, option active, et chaque changement de seuil,
    // d'adoucissement ou de fond (le cache du service évite l'inférence).
    onFondCourantChanged: relancer()
    onSeuilChanged: relancer()
    onAdouciChanged: relancer()
    Component.onCompleted: relancer()

    // L'option s'allume après coup : sans cette connexion, la surface ne se
    // remplirait jamais (elle attend un masque que rien ne déclenche).
    Connections {
        target: Theme
        function onDepthMaskChanged() { fenetre.relancer() }
    }

    function relancer() {
        if (!Theme.depthMask || fenetre.fondCourant === "") return
        if (generateur.running) return
        generateur.command = ["python3", Quickshell.shellPath("core/depth_mask.py"),
                              "generate", "--wallpaper", fenetre.fondCourant,
                              "--threshold", String(fenetre.seuil),
                              "--feather", String(fenetre.adouci)]
        generateur.running = true
    }

    Image {
        anchors.fill: parent
        source: fenetre.masque !== "" ? "file://" + fenetre.masque : ""
        fillMode: Image.Stretch          // le masque est à la résolution du fond
        asynchronous: true
        cache: true
    }
}
