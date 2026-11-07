import QtQuick
import "."
import Quickshell
import Quickshell.Wayland

// BARRE SUPPLÉMENTAIRE — bas, gauche ou droite, chacune en trois places.
//
// Un seul composant pour trois emplacements : seule l'orientation change. Chaque
// barre a trois zones le long de son axe — début, milieu, fin — donc un applet
// peut aller à gauche, au centre ou à droite d'une barre du bas, en haut, au
// milieu ou en bas d'une barre latérale.
//
// La surface occupe **tout le bord** (largeur complète en bas, hauteur complète
// sur les côtés). Ce n'est pas un choix esthétique : Hyprland n'applique une zone
// exclusive que si la surface couvre le bord entier. Une capsule étroite flottante
// se contentait de recouvrir les fenêtres.
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
    readonly property int nbApplets: verticale
        ? colDebut.applets.length + colMilieu.applets.length + colFin.applets.length
        : debut.applets.length + milieu.applets.length + fin.applets.length

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

    implicitWidth: verticale ? Theme.barSideWidth : 0
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

    // ── fond ─────────────────────────────────────────────────────────────────
    // Marge interne des zones quand le fond est découpé : la même que celle qui
    // écarte les applets du bord de la barre, pour que la pilule « respire »
    // autour de son contenu.
    readonly property int pad: rembourrage
    readonly property bool decoupe: Theme.barGapsTransparent && nbApplets > 0

    // Géométrie des trois zones le long de l'axe de la barre, en coordonnées de
    // la barre : { pos, taille }. Une zone sans applet vaut 0 et n'est pas
    // peinte ; les zones des extrémités vont jusqu'au bord de l'écran, sinon la
    // barre ne toucherait plus son bord et l'œil verrait un liseré de vide.
    // Ces trois zones ne peignent que le fond : les rangées/colonnes restent les
    // mêmes objets ancrés qu'avant, et l'espace entre elles reste une région de
    // la barre (pour une animation de lecture média, comme la barre du haut).
    readonly property var zonesFond: {
        if (!decoupe) return []
        const a = verticale ? colDebut : debut
        const b = verticale ? colMilieu : milieu
        const c = verticale ? colFin : fin
        const total = verticale ? root.height : root.width
        const premiere = a.applets.length > 0
        const mediane = b.applets.length > 0
        const derniere = c.applets.length > 0
        const debutPos = verticale ? a.y : a.x
        const milieuPos = verticale ? b.y : b.x
        const finPos = verticale ? c.y : c.x
        const tailleA = verticale ? a.height : a.width
        const tailleB = verticale ? b.height : b.width
        const tailleC = verticale ? c.height : c.width
        return [
            { pos: 0, taille: premiere ? debutPos + tailleA + pad : 0 },
            { pos: Math.max(0, milieuPos - pad),
              taille: mediane ? tailleB + pad * 2 : 0 },
            { pos: derniere ? Math.max(0, finPos - pad) : 0,
              taille: derniere ? Math.max(0, total - Math.max(0, finPos - pad)) : 0 }
        ]
    }

    // Espaces entre les zones peintes : ce sont eux qui reçoivent le
    // visualiseur audio. Même axe que les zones, même forme { pos, taille } ;
    // un espace trop étroit (< 10 px) ne porte rien.
    readonly property var trousFond: {
        const z = zonesFond
        if (z.length !== 3) return []
        const t = []
        const premier = z[0].pos + z[0].taille
        if (z[1].pos - premier > 10) t.push({ pos: premier, taille: z[1].pos - premier })
        const second = z[1].pos + z[1].taille
        if (z[2].pos - second > 10) t.push({ pos: second, taille: z[2].pos - second })
        return t
    }

    // Fond continu : mode normal, ou barre vide (l'invite « Vide » a besoin
    // d'une surface, sinon elle flotte sur le bureau).
    Rectangle {
        visible: !root.decoupe
        anchors.fill: parent
        radius: Theme.pillRadius
        color: Theme.barBg
        border.color: Theme.accent
        border.width: Theme.barBorder ? 1 : 0
    }

    Repeater {
        model: root.zonesFond

        delegate: Rectangle {
            readonly property bool horizontal: !root.verticale
            x: horizontal ? modelData.pos : 0
            y: horizontal ? 0 : modelData.pos
            width: horizontal ? modelData.taille : root.width
            height: horizontal ? root.height : modelData.taille
            radius: Theme.pillRadius
            color: Theme.barBg
            border.color: Theme.accent
            border.width: Theme.barBorder ? 1 : 0
        }
    }

    // Visualiseur audio : un par espace vide, comme sur la barre du haut.
    //
    // Sur une barre de côté, le dessin est pivoté : les barres de spectre
    // deviennent horizontales et poussent depuis le bord extérieur de l'écran
    // vers l'intérieur (donc de gauche à droite sur la barre de gauche). Les
    // dimensions sont échangées avant rotation pour que le tracé remplisse
    // exactement la zone, et le conteneur découpe : rien ne déborde de la barre.
    Repeater {
        model: root.trousFond

        delegate: Item {
            readonly property bool aPlat: !root.verticale
            x: aPlat ? modelData.pos : 0
            y: aPlat ? 0 : modelData.pos
            width: aPlat ? modelData.taille : root.width
            height: aPlat ? root.height : modelData.taille
            clip: true

            Visualiseur {
                barre: root.cote
                width: root.verticale ? parent.height : parent.width
                height: root.verticale ? parent.width : parent.height
                anchors.centerIn: parent
                rotation: root.verticale ? (root.aGauche ? 90 : -90) : 0
                transformOrigin: Item.Center
            }
        }
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

    // ── trois zones ──────────────────────────────────────────────────────────
    // Rangées pour la barre du bas : calées à gauche, au centre, à droite.
    AppletRow {
        id: debut
        ile: root.verticale ? "" : root.cote + ":debut"
        visible: !root.verticale
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.rembourrage
    }

    AppletRow {
        id: milieu
        ile: root.verticale ? "" : root.cote + ":milieu"
        visible: !root.verticale
        anchors.centerIn: parent
    }

    AppletRow {
        id: fin
        ile: root.verticale ? "" : root.cote + ":fin"
        visible: !root.verticale
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.rembourrage
    }

    // Colonnes pour les barres de côté : calées en haut, au milieu, en bas.
    AppletColumn {
        id: colDebut
        ile: root.verticale ? root.cote + ":debut" : ""
        visible: root.verticale
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.rembourrage
    }

    AppletColumn {
        id: colMilieu
        ile: root.verticale ? root.cote + ":milieu" : ""
        visible: root.verticale
        anchors.centerIn: parent
    }

    AppletColumn {
        id: colFin
        ile: root.verticale ? root.cote + ":fin" : ""
        visible: root.verticale
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.rembourrage
    }
}
