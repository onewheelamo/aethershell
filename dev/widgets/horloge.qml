import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Hyprland

// ────────────────────────────────────────────────────────────────────────────
// WIDGETS DE BUREAU — un composant par type, chargé par un Loader depuis
// main.qml. Chaque widget est une surface layer `Bottom` (namespace
// `shell-widget`) : elle vit DERRIÈRE les fenêtres, ne prend jamais le clavier
// et ne doit mesurer QUE son contenu — une surface layer consomme les clics sur
// toute son étendue, même transparente.
//
// Taille : toujours implicite (implicitWidth/Height), jamais `width`/`height`
// littéraux ; les tailles de texte viennent de Theme (widgetClock, widgetDate…).
// ────────────────────────────────────────────────────────────────────────────

// HORLOGE — heure seule, option secondes.
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

    // widget_set écrit les options en chaîne ("true") : tester les deux formes,
    // sinon l'option ne s'active jamais depuis la CLI ou le panneau.
    readonly property bool withSeconds: {
        const s = options ? options.seconds : undefined
        return s === true || s === "true" || s === 1 || s === "1"
    }

    implicitWidth: clockRow.implicitWidth
    implicitHeight: clockRow.implicitHeight

    SystemClock {
        id: clock
        precision: root.withSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Row {
        id: clockRow
        spacing: Theme.space2

        Text {
            id: hhmm
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Theme.fg
            font.pixelSize: Math.round(Theme.widgetClock * root.echelle)
            font.weight: Font.Light
            font.features: { "tnum": 1 }
            // Lisible sur un wallpaper clair sans ajouter de carte.
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        Text {
            visible: root.withSeconds
            text: Qt.formatTime(clock.date, "ss")
            color: Theme.accent
            font.pixelSize: Math.round(Theme.widgetClockSm * root.echelle)
            font.weight: Font.Light
            font.features: { "tnum": 1 }
            anchors.baseline: hhmm.baseline
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }
    }
}
