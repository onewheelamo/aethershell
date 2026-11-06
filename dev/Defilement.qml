import QtQuick
import "."

// TEXTE BORNÉ ET DÉFILANT — la valeur d'un applet, sans allonger la barre.
//
// Un applet n'a pas de largeur fixe : un titre de morceau de quatre-vingts
// caractères pousserait l'îlot entier, et donc tout ce qui le suit dans la
// barre. On borne donc la largeur, on découpe ce qui dépasse, et on fait glisser
// le texte d'un bord à l'autre avec une pause à chaque extrémité. Aller-retour
// plutôt que boucle sans fin : le début du titre reste l'état de repos, et le
// retour ne fait pas de saut visible.
//
// Quand la valeur tient dans la largeur, ce composant se comporte exactement
// comme un `Text` : même largeur implicite, aucune animation, aucun clip.
Item {
    id: racine

    property string texte: ""
    property color couleur: Theme.fg
    property int taillePolice: 12
    property int largeurMax: 200
    // Lent et peu fréquent : le texte doit se laisser lire, pas attirer l'œil.
    property int vitesse: 26          // px/s
    property int pause: 1400          // ms à chaque extrémité

    readonly property real largeurTexte: txt.implicitWidth
    readonly property bool defile: largeurTexte > width + 0.5
    readonly property int distance: Math.max(0, Math.ceil(largeurTexte - width))

    implicitWidth: Math.min(largeurTexte, largeurMax)
    implicitHeight: txt.implicitHeight
    clip: true

    Text {
        id: txt
        x: 0
        text: racine.texte
        color: racine.couleur
        font.pixelSize: racine.taillePolice
        font.features: { "tnum": 1 }
        y: Math.round((racine.height - implicitHeight) / 2)
    }

    SequentialAnimation {
        id: glisse
        running: racine.defile
        loops: Animation.Infinite

        PauseAnimation { duration: racine.pause }
        NumberAnimation {
            target: txt
            property: "x"
            to: -racine.distance
            duration: Math.max(250, Math.round(racine.distance / racine.vitesse * 1000))
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: racine.pause }
        NumberAnimation {
            target: txt
            property: "x"
            to: 0
            duration: Math.max(250, Math.round(racine.distance / racine.vitesse * 1000))
            easing.type: Easing.InOutSine
        }
    }

    // Une nouvelle valeur se lit depuis son début : on repart de zéro, sinon le
    // titre suivant hérite de la position du précédent, au milieu du mot.
    onTexteChanged: {
        txt.x = 0
        if (racine.defile) glisse.restart()
    }
    // Plus rien ne déborde (valeur plus courte, place plus large) : on remet le
    // texte en place plutôt que de le laisser figé à mi-course.
    onDefileChanged: if (!racine.defile) txt.x = 0
}
