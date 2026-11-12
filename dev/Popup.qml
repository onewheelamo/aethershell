import QtQuick
import Quickshell

// POPUP — la fenêtre commune à tous les panneaux accrochés aux applets.
//
// Pourquoi ce fichier existe : les popups étaient construits deux fois, une fois
// dans `Applet.qml` pour les applets « service » (homelab, presse-papiers, quotas)
// et une fois dans chaque composant « qml » (notifications, volume, réseau,
// alimentation). Tout réglage transversal — position, marges, ajustement — devait
// donc être écrit deux fois, et un oubli ne se voyait qu'à l'œil.
//
// Ce que la mesure a appris, et qui justifie la forme ci-dessous :
//  - `anchor.rect.y` n'est PAS appliqué par Quickshell 0.3.2 sur ces fenêtres :
//    ancre forcée à 200 px, panneau immobile. La position réelle vient de l'item
//    d'ancrage, plus un écart fixe d'environ 14 px.
//  - le seul levier qui agit est `anchor.margins.top` : à 0 le panneau est 14 px
//    sous l'applet, à -12 il touche la barre.
// D'où `Theme.popupGap`, une valeur unique, au lieu de littéraux dispersés.
//
// Usage — le contenu reste dans le fichier de l'appelant :
//   Popup {
//       id: fenetre
//       ancre: root            // l'item auquel le popup s'accroche
//       ile: root.applet.ile   // « barre:place », donne l'orientation
//       alignement: "centre"   // gauche | centre | droite
//       visible: root.ouvert
//       implicitWidth: 324
//       implicitHeight: panneau.implicitHeight
//       Rectangle { anchors.fill: parent; ... }
//   }
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
}
