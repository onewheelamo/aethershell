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
// La flèche ouvre le calendrier Nextcloud sous le widget. Le panneau est le même
// fichier que celui de l'applet « calendrier » : une seule grille, un seul code
// réseau, deux points d'entrée.
Item {
    id: root
    property var options: ({})
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte LLM partent
    // plus petit (85) parce qu'ils affichent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

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

    // Clé d'ouverture propre à ce widget : deux widgets date sur deux bureaux ne
    // doivent pas s'ouvrir l'un l'autre.
    readonly property string cleOuverture: "widget-date:" + (widgetId || "0")
    readonly property bool calendrierOuvert: Theme.activePopup === cleOuverture

    implicitWidth: ligne.implicitWidth
    implicitHeight: ligne.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: ligne
        spacing: 6

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.libelle
            color: Theme.fg
            opacity: 0.92
            font.pixelSize: Math.round(Theme.widgetDate * root.echelle)
            font.weight: Font.Normal
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        // Triple rôle : dire qu'il y a quelque chose derrière, montrer l'état
        // (ouvert/fermé) et porter le clic.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: fleche.containsMouse || root.calendrierOuvert
                ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(Theme.widgetDate * root.echelle * 0.8)
            rotation: root.calendrierOuvert ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 120 } }

            MouseArea {
                id: fleche
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.activePopup = root.calendrierOuvert ? "" : root.cleOuverture
            }
        }
    }

    CalendrierPanneau {
        ancre: root
        ouvert: root.calendrierOuvert
        // Personne d'autre ne surveille ce panneau : il ferme lui-même au clic
        // à côté (l'îlot ne le fait que pour les siens).
        attrapeurPropre: true
    }
}
