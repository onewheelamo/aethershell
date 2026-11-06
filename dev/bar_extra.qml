import QtQuick
import "."
import Quickshell
import Quickshell.Wayland

// BARRE SUPPLÉMENTAIRE — bas, gauche ou droite.
//
// Un seul composant pour trois emplacements : seule l'orientation change. La
// barre n'existe que si elle a été allumée **et** si elle porte au moins un
// applet : une barre vide ne doit pas laisser une bande morte sur un bord de
// l'écran.
//
// La capsule épouse son contenu plutôt que de traverser l'écran : une barre de
// 1900 px pour une seule icône se lit comme un bandeau vide. Le bas réserve sa
// place (`ExclusionMode.Auto`) pour que les fenêtres ne se glissent pas dessous ;
// les côtés flottent (`Ignore`) et se centrent verticalement, avec une surface à
// la taille du contenu — sinon une bande pleine hauteur intercepterait les clics
// sur tout le bord.
PanelWindow {
    id: root
    property string cote: "bas"          // "bas" | "cote-gauche" | "cote-droite"

    readonly property bool verticale: cote !== "bas"
    readonly property bool aGauche: cote === "cote-gauche"
    readonly property bool actif: cote === "bas" ? Theme.barBottomVisible
                                 : (cote === "cote-gauche" ? Theme.barLeftVisible
                                                           : Theme.barRightVisible)

    readonly property int ecart: Math.round(Theme.gutter)
    readonly property int rembourrage: Math.round(Theme.space3)

    // Une barre allumée s'affiche, même vide : sans ça, l'interrupteur du panneau
    // n'a aucun effet visible et on croit le réglage cassé. Vide, elle montre
    // comment la remplir.
    readonly property int nbApplets: verticale ? colonne.applets.length : ligne.applets.length
    visible: actif

    // Le bas épouse son contenu (une rangée). Les côtés ont une hauteur fixe :
    // une taille dérivée du contenu créait une boucle de dépendance (fenêtre →
    // marge de centrage → contenu), que QML casse en gelant le binding — la barre
    // restait figée à sa première mesure. Un tiers de hauteur libre en haut et en
    // bas, contenu centré : c'est un dock vertical, stable.
    readonly property real largeur: Math.round(verticale ? Theme.barHeight
                                                         : (nbApplets > 0
                                                            ? ligne.implicitWidth + 2 * rembourrage
                                                            : 230))
    readonly property real hauteur: Math.round(verticale
                                               ? screen.height * 0.6
                                               : Theme.barHeight)

    // Bas : collé au bord inférieur, centré horizontalement.
    // Côtés : tendus en hauteur, la marge verticale fait le centrage.
    anchors.top: verticale
    anchors.bottom: true
    anchors.left: verticale ? aGauche : true
    anchors.right: verticale && !aGauche

    margins.bottom: ecart
    margins.left: verticale ? (aGauche ? ecart : 0)
                            : Math.max(ecart, Math.round((screen.width - largeur) / 2))
    margins.right: verticale ? (aGauche ? 0 : ecart) : 0
    margins.top: verticale ? Math.round((screen.height - hauteur) / 2) : 0

    implicitWidth: largeur
    implicitHeight: verticale ? hauteur : Theme.barHeight

    color: "transparent"
    exclusionMode: verticale ? ExclusionMode.Ignore : ExclusionMode.Auto
    exclusiveZone: verticale ? 0 : implicitHeight + ecart
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "shell-bar-" + cote
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        radius: Theme.pillRadius
        color: Theme.barBg
        border.color: Theme.accent
        border.width: Theme.barBorder ? 1 : 0
    }

    // Barre vide : un rappel de la marche à suivre, pas une bande muette.
    Text {
        visible: root.nbApplets === 0
        anchors.centerIn: parent
        width: Math.max(60, parent.width - 2 * root.rembourrage)
        text: root.verticale
              ? "Vide"
              : "Aucun applet — choisir "
                + (root.cote === "bas" ? "↓" : (root.aGauche ? "←" : "→"))
                + " dans Quickshell → Applets"
        color: Qt.alpha(Theme.fg, 0.45)
        font.pixelSize: Math.max(9, Theme.textXs - 1)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    AppletRow {
        id: ligne
        ile: "bas"
        visible: !root.verticale && root.nbApplets > 0
        anchors.centerIn: parent
    }

    AppletColumn {
        id: colonne
        ile: root.cote
        visible: root.verticale && root.nbApplets > 0
        anchors.centerIn: parent
    }
}
