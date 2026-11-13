import QtQuick
import "."

// ══════════════════════════════════════════════════════════════════════
// SURFACE FLOUTÉE UNIFIÉE (SurfaceFloutee.qml)
// ══════════════════════════════════════════════════════════════════════
// Source unique de rendu pour le panneau de configuration, le panneau
// étendu de l'îlot dynamique et tous les panneaux de barre (PanneauSurface).
// Le flou d'arrière-plan est assuré exclusivement par le compositeur Hyprland
// (règle `shell-blur`), ce qui floute les fenêtres derrière la surface sans
// jamais redessiner le fond d'écran nu.
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property real rayon: Theme.pillRadius
    property color teinte: Theme.surfaceBg
    property color bordureCouleur: Theme.accent
    property int bordureLargeur: Theme.barBorder ? 1 : 0
    property bool actif: true

    function rafraichir() {}

    Rectangle {
        anchors.fill: parent
        radius: root.rayon
        color: root.teinte
        border.color: root.bordureCouleur
        border.width: root.bordureLargeur
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }
}
