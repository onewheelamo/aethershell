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
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

    readonly property bool withSeconds: !!(options && options.seconds === true)

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
            font.pixelSize: Theme.widgetClock
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
            font.pixelSize: Theme.widgetClockSm
            font.weight: Font.Light
            font.features: { "tnum": 1 }
            anchors.baseline: hhmm.baseline
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }
    }
}
