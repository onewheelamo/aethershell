import QtQuick
import "."
import Quickshell
import Quickshell.Wayland

// BARRE SUPPLÉMENTAIRE — bas, gauche ou droite.
//
// Un seul composant pour trois emplacements : seule l'orientation change. La
// barre n'existe que si elle a été allumée ; vide, elle affiche un rappel pour
// qu'on sache comment la remplir.
//
// La surface occupe **tout le bord** (largeur complète en bas, hauteur complète
// sur les côtés). Ce n'est pas un choix esthétique : Hyprland n'applique une zone
// exclusive que si la surface couvre le bord entier. Une capsule étroite flottante
// se contentait de recouvrir les fenêtres. La capsule dessinée, elle, garde ses
// coins arrondis et ses marges.
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

    // Tout le bord, sans exception : c'est la condition pour que la zone
    // exclusive soit appliquée et que les fenêtres se rangent à côté.
    anchors.top: verticale
    anchors.bottom: true
    anchors.left: verticale ? aGauche : true
    anchors.right: verticale ? !aGauche : true

    margins.top: verticale ? ecart : 0
    margins.bottom: ecart
    margins.left: ecart
    margins.right: ecart

    implicitWidth: verticale ? Theme.barHeight : 0
    implicitHeight: Theme.barHeight

    color: "transparent"
    // `Auto` ne réserve rien pour une surface ancrée à deux bords : Hyprland la
    // voit comme un panneau flottant. `Normal` dit explicitement « je réserve ma
    // bande ». La zone est constante, jamais dérivée d'une taille encore nulle.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: visible ? Theme.barHeight + ecart : 0
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
