import QtQuick
import Quickshell

// Fenêtre PopupWindow commune aux panneaux d'applets.
// Note Quickshell 0.3.2 : `anchor.rect.y` étant ignoré ici, le décalage vertical
// passe par `anchor.margins.top` (`Theme.popupGap`).
PopupWindow {
    id: fenetre

    // L'item d'ancrage : c'est lui qui décide de la position horizontale.
    property Item ancre: null
    // « barre:place » : côté haut/bas/gauche/droite et place debut/milieu/fin.
    property string ile: ""
    // Alignement horizontal sous l'item d'ancrage.
    property string alignement: "gauche"
    // Ajustement vertical propre à un panneau. Le placement par défaut convient
    // aux applets à texte ; la cloche et le wifi, dont l'item est plus court,
    // se posent quelques pixels trop haut et le rattrapent ici.
    property int ecart: 0
    property color bordureCouleur: Theme.accent
    property int bordureLargeur: Theme.barBorder ? 1 : 0
    default property alias contenu: surfaceMorph.contenu

    color: "transparent"

    anchor.item: ancre
    anchor.edges: Theme.ancrePopupEdges(ile)
    anchor.gravity: Theme.ancrePopupGravity(ile)
    anchor.rect.x: Theme.ancrePopupX(ile, ancre, implicitWidth, alignement)
    anchor.rect.y: Theme.ancrePopupY(ile, ancre, implicitHeight)

    // Marges directionnelles : l'écart personnalisé (ecart) s'applique sur le bord
    // adjacent à la barre porteuse (haut si barre du haut, bas si barre du bas,
    // gauche si barre gauche, droite si barre droite).
    anchor.margins.top: (String(ile || "").split(":")[0] === "haut") ? ecart : 14
    anchor.margins.bottom: (String(ile || "").split(":")[0] === "bas") ? ecart : 14
    anchor.margins.left: (String(ile || "").split(":")[0] === "cote-gauche") ? ecart : 14
    anchor.margins.right: (String(ile || "").split(":")[0] === "cote-droite") ? ecart : 14
    anchor.adjustment: PopupAdjustment.All

    PanneauSurface {
        id: surfaceMorph
        anchors.fill: parent
        ile: fenetre.ile
        actif: fenetre.visible
        bordureCouleur: fenetre.bordureCouleur
        bordureLargeur: fenetre.bordureLargeur
    }
}
