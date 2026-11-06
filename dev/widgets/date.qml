import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell

// DATE — jour de la semaine et date longue, en français.
//
// Le libellé est construit en JS avec deux tables : la surcharge
// `Qt.formatDate(d, "dddd d MMMM", Qt.locale("fr_FR"))` n'existe pas dans ce Qt
// — elle cherche un QLocale en 2e argument et lève « Could not convert argument
// 1 from dddd d MMMM to QLocale », ce qui laisse le widget vide (surface 1×1).
//
// La flèche **étend le widget** : la grille du mois apparaît dessous, dans la
// même surface. Pas de fenêtre à ancrer, donc rien à refermer au clic extérieur —
// la flèche suffit. La fenêtre du widget suit notre implicitHeight.
//
// Racine `Item` et non `Column` : un positionneur calcule lui-même sa taille
// implicite, la lui assigner est une erreur (« implicitHeight is read-only »).
Item {
    id: root

    property var options: ({})
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    // Étendu ou non : état local au widget, il vit tant que le shell tourne.
    property bool ouvert: false

    readonly property var jours: ["dimanche", "lundi", "mardi", "mercredi",
                                  "jeudi", "vendredi", "samedi"]
    readonly property var mois: ["janvier", "février", "mars", "avril", "mai",
                                 "juin", "juillet", "août", "septembre",
                                 "octobre", "novembre", "décembre"]

    readonly property string libelle: {
        const d = clock.date
        if (!d || isNaN(d.getTime()))
            return ""
        return jours[d.getDay()] + " " + d.getDate() + " " + mois[d.getMonth()]
    }

    // Largeur imposée au calendrier : celle de la ligne de date. Elle se calcule
    // sur le texte seul, donc pas de boucle largeur ↔ contenu comme lorsque la
    // grille se dimensionnait sur la colonne qui la contient.
    readonly property real largeurCalendrier: Math.max(ligne.width,
                                                       Math.round(196 * echelle))

    implicitWidth: colonne.implicitWidth
    implicitHeight: colonne.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Pas de `width: parent.width` ici : la fenêtre du widget prend notre largeur
    // implicite, qui vient de cette colonne — la lier au parent fermait la boucle
    // et la grille du calendrier s'effondrait (widget réduit à la ligne de date).
    Column {
        id: colonne
        spacing: 7

        // En-tête en Item et non en Row : le chevron doit pouvoir s'ancrer au
        // coin bas-droit de la ligne, or une rangée refuse les ancres de ses
        // enfants sur elle-même (et deux objets frères dans un Item, non).
        Item {
            id: ligne
            width: label.implicitWidth + 11
            height: label.implicitHeight

            Text {
                id: label
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.libelle
                color: Theme.fg
                opacity: 0.92
                font.pixelSize: Math.round(Theme.widgetDate * root.echelle)
                font.weight: Font.Normal
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            // Petit chevron d'ouverture, coin inférieur droit : discret tant
            // qu'on ne le cherche pas. Il pivote quand la grille est dépliée.
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: "›"
                color: fleche.containsMouse || root.ouvert
                    ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.max(12, Math.round(15 * root.echelle))
                rotation: root.ouvert ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 120 } }

                MouseArea {
                    id: fleche
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvert = !root.ouvert
                }
            }
        }

        CalendrierCompact {
            id: calendrier
            visible: root.ouvert
            width: root.largeurCalendrier
            echelle: root.echelle
        }
    }
}
