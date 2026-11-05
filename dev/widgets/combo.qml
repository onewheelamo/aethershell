import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// COMBO — horloge, date et météo dans une seule carte.
//
// Même source de données que widgets/meteo.qml (core/weather_service.py, cache
// partagé de dix minutes, donc aucun appel réseau en double si la météo seule
// est aussi posée quelque part).
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

    property var meteo: ({})
    property bool loaded: false

    readonly property bool ok: loaded && meteo && meteo.ok === true
    readonly property bool withSeconds: {
        const s = options ? options.seconds : undefined
        return s === true || s === "true" || s === 1 || s === "1"
    }
    readonly property string cityOption: (options && options.city) ? String(options.city) : ""

    // Deux tables plutôt que Qt.formatDate à trois arguments : cette surcharge
    // n'existe pas dans ce Qt et laisse le texte vide (voir widgets/date.qml).
    readonly property var jours: ["dimanche", "lundi", "mardi", "mercredi",
                                  "jeudi", "vendredi", "samedi"]
    readonly property var mois: ["janvier", "février", "mars", "avril", "mai",
                                 "juin", "juillet", "août", "septembre",
                                 "octobre", "novembre", "décembre"]

    readonly property string libelleDate: {
        const d = clock.date
        if (!d || isNaN(d.getTime()))
            return ""
        return jours[d.getDay()] + " " + d.getDate() + " " + mois[d.getMonth()]
    }

    implicitWidth: stack.implicitWidth
    implicitHeight: stack.implicitHeight

    function refresh(force) {
        const args = ["python3", Quickshell.shellPath("core/weather_service.py")]
        if (root.cityOption !== "")
            args.push("--city", root.cityOption)
        if (force)
            args.push("--force")
        proc.command = args
        proc.running = true
    }

    Component.onCompleted: refresh(false)

    SystemClock {
        id: clock
        precision: root.withSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Timer {
        interval: 600000
        repeat: true
        running: true
        onTriggered: root.refresh(false)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.meteo = JSON.parse(text.trim())
                } catch (e) {
                    root.meteo = { ok: false, error: "réponse illisible" }
                }
                root.loaded = true
            }
        }
    }

    Column {
        id: stack
        spacing: Theme.space1

        // Heure
        Row {
            spacing: Theme.space2

            Text {
                id: hhmm
                text: Qt.formatTime(clock.date, "HH:mm")
                color: Theme.fg
                font.pixelSize: Math.round(Theme.widgetClock * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
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

        // Date
        Text {
            text: root.libelleDate
            color: Qt.alpha(Theme.fg, 0.92)
            font.pixelSize: Math.round(Theme.widgetComboDate * root.echelle)
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        // Météo
        Row {
            spacing: Theme.space2
            topPadding: Theme.space1

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: (root.ok && root.meteo.icon === "sun") ? "sun" : "cloud"
                size: Math.round(Theme.widgetWeatherIcon * root.echelle)
                color: Theme.accent
                opacityLevel: root.ok ? 1.0 : 0.45
            }

            Text {
                id: tempText
                text: root.ok ? Math.round(root.meteo.temp) + "°" : "—"
                color: Theme.fg
                font.pixelSize: Math.round(Theme.widgetComboWeather * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: root.ok ? (root.meteo.label + " · " + root.meteo.city)
                              : (root.loaded ? "météo indisponible" : "…")
                color: Qt.alpha(Theme.fg, 0.78)
                font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                anchors.baseline: tempText.baseline
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }
    }
}
