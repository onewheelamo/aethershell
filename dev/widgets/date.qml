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
Item {
    id: root
    property var options: ({})

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte LLM partent
    // plus petit (85) parce qu'ils affichent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

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

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        text: root.libelle
        color: Theme.fg
        opacity: 0.92
        font.pixelSize: Math.round(Theme.widgetDate * root.echelle)
        font.weight: Font.Normal
        style: Text.Raised
        styleColor: Qt.alpha(Theme.bg, 0.55)
    }
}
