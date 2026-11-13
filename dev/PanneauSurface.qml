import QtQuick
import "."

// ══════════════════════════════════════════════════════════════════════
// SURFACE DE PANNEAU MORPHÉE (PanneauSurface.qml)
// ══════════════════════════════════════════════════════════════════════
// Décoration unifiée pour tous les panneaux dérivés de la barre :
// - Flou interne (FlouFond) + teinte Theme.barBg + opacité Theme.shellOpacity
// - Bordure Theme.accent / Theme.barBorder + arrondi Theme.pillRadius
// - Animation d'extension fluide depuis le bord de la barre porteuse
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property string ile: ""
    property bool actif: false
    property real rayon: Theme.pillRadius
    property color bordureCouleur: Theme.accent
    property int bordureLargeur: Theme.barBorder ? 1 : 0
    default property alias contenu: contentSlot.data

    readonly property string cote: String(ile || "").split(":")[0]

    property real animProg: 1.0
    onActifChanged: {
        if (actif) {
            animProg = 0.0
            openAnim.restart()
        }
    }

    NumberAnimation {
        id: openAnim
        target: root
        property: "animProg"
        from: 0.0
        to: 1.0
        duration: Theme.panelAnimDuration
        easing.type: Easing.OutCubic
    }

    Item {
        id: morphWrap
        anchors.fill: parent
        opacity: root.animProg
        scale: 0.94 + 0.06 * root.animProg
        transformOrigin: root.cote === "bas" ? Item.Bottom
            : root.cote === "cote-gauche" ? Item.Left
            : root.cote === "cote-droite" ? Item.Right
            : Item.Top
        transform: Translate {
            x: root.cote === "cote-gauche" ? -8 * (1.0 - root.animProg)
                : (root.cote === "cote-droite" ? 8 * (1.0 - root.animProg) : 0)
            y: root.cote === "bas" ? 8 * (1.0 - root.animProg)
                : ((root.cote === "cote-gauche" || root.cote === "cote-droite") ? 0 : -8 * (1.0 - root.animProg))
        }

        SurfaceFloutee {
            anchors.fill: parent
            rayon: root.rayon
            teinte: Theme.surfaceBg
            bordureCouleur: root.bordureCouleur
            bordureLargeur: root.bordureLargeur
            actif: root.actif
        }

        Item {
            id: contentSlot
            anchors.fill: parent
        }
    }
}
