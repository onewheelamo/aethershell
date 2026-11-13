import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// MÉTÉO — relevé complet et prévisions à trois jours.
//
// Les données viennent de core/weather_service.py (Open-Meteo, sans clé), lancé
// par un Process : c'est le patron du reste du shell, un script Python qui rend
// une ligne de JSON. Rafraîchissement toutes les dix minutes ; en cas d'échec
// réseau le service rend la dernière valeur connue, marquée `cached`.
//
// Le widget porte autant d'information que le popup de l'applet — relevé du jour
// (ressenti, min/max, humidité, vent, pluie) — plus les trois jours suivants.
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

    property var meteoLocal: ({})
    property bool loadedLocal: false
    readonly property var meteo: root.cityOption === "" ? Theme.meteoData : meteoLocal
    readonly property bool loaded: root.cityOption === "" ? Theme.meteoLoaded : loadedLocal

    readonly property bool ok: loaded && meteo && meteo.ok === true
    // Ville propre au widget (`widget_set meteo-1 city Lyon`) ; sinon le service
    // retombe sur la localisation réglée dans le panneau, puis sur weather_city.
    readonly property string cityOption: (options && options.city) ? String(options.city) : ""

    // Aujourd'hui est déjà résumé au-dessus : on garde les cinq jours suivants.
    readonly property var previsions: {
        const p = (root.meteo && root.meteo.previsions) ? root.meteo.previsions : []
        return p.slice(1, 6)
    }

    implicitWidth: contentCol.implicitWidth
    implicitHeight: contentCol.implicitHeight

    function refresh(force) {
        if (root.cityOption === "") {
            Theme.rafraichirMeteo(force)
            return
        }
        const args = ["python3", Quickshell.shellPath("core/weather_service.py"),
                      "--city", root.cityOption]
        if (force)
            args.push("--force")
        proc.command = args
        proc.running = true
    }

    // « 2026-11-09 » → « lun. » ; sans date lisible, on rend la chaîne brute.
    function jourCourt(iso) {
        const d = new Date(String(iso || "") + "T12:00:00")
        if (isNaN(d.getTime())) return String(iso || "")
        return d.toLocaleDateString(Qt.locale("fr_FR"), "ddd")
    }

    function nombre(v, suffixe) {
        return (v === undefined || v === null) ? "—" : Math.round(Number(v)) + (suffixe || "")
    }

    Component.onCompleted: refresh(false)

    Timer {
        interval: 600000
        repeat: true
        running: root.cityOption !== ""
        onTriggered: root.refresh(false)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.meteoLocal = JSON.parse(text.trim())
                } catch (e) {
                    root.meteoLocal = { ok: false, error: "réponse illisible" }
                }
                root.loadedLocal = true
            }
        }
    }

    Column {
        id: contentCol
        spacing: Math.round(4 * root.echelle)

        // ── relevé du jour ────────────────────────────────────────────────
        Row {
            spacing: Theme.space3

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: (root.ok && root.meteo.icon === "sun") ? "sun" : "cloud"
                size: Math.round(Theme.widgetWeatherIcon * root.echelle)
                color: Theme.accent
                opacityLevel: root.ok ? 1.0 : 0.45
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: root.ok ? Math.round(root.meteo.temp) + "°" : "—"
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.widgetTemp * root.echelle)
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                    // Lisible sur un wallpaper clair sans ajouter de carte.
                    style: Text.Raised
                    styleColor: Qt.alpha(Theme.bg, 0.55)
                }

                Text {
                    text: root.ok
                          ? (root.meteo.label + " · " + root.meteo.city)
                          : (root.loaded ? "météo indisponible" : "…")
                    color: Qt.alpha(Theme.fg, 0.78)
                    font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                    style: Text.Raised
                    styleColor: Qt.alpha(Theme.bg, 0.55)
                }
            }
        }

        // ── détails du jour ───────────────────────────────────────────────
        Text {
            visible: root.ok
            text: root.ok
                  ? ("min " + root.nombre(root.meteo.tmin, "°")
                     + " · max " + root.nombre(root.meteo.tmax, "°")
                     + " · ressenti " + root.nombre(root.meteo.feels, "°")
                     + " · " + root.nombre(root.meteo.humidite, " %")
                     + " · vent " + root.nombre(root.meteo.vent, " km/h")
                     + (Number(root.meteo.pluie_mm) > 0
                        ? " · pluie " + root.nombre(root.meteo.pluie_mm, " mm") : "")
                     + (root.meteo.stale === true ? " · dernière valeur connue" : ""))
                  : ""
            color: Qt.alpha(Theme.fg, 0.62)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.92 * root.echelle)
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        // ── trois jours suivants ──────────────────────────────────────────
        Row {
            visible: root.ok && root.previsions.length > 0
            spacing: Math.round(10 * root.echelle)

            Repeater {
                model: root.previsions

                Column {
                    required property var modelData
                    // Largeur fixe : les trois lignes d'une colonne s'alignent
                    // verticalement et les colonnes se répartissent également.
                    width: Math.round(62 * root.echelle)
                    spacing: 0

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.jourCourt(modelData.date)
                        color: Qt.alpha(Theme.fg, 0.72)
                        font.pixelSize: Math.round(Theme.widgetLabel * 0.9 * root.echelle)
                        font.capitalization: Font.Capitalize
                        style: Text.Raised
                        styleColor: Qt.alpha(Theme.bg, 0.55)
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.nombre(modelData.tmin, "°") + " / " + root.nombre(modelData.tmax, "°")
                        color: Theme.fg
                        font.pixelSize: Math.round(Theme.widgetLabel * 0.95 * root.echelle)
                        font.features: { "tnum": 1 }
                        style: Text.Raised
                        styleColor: Qt.alpha(Theme.bg, 0.55)
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: modelData.pluie !== null && modelData.pluie !== undefined
                        text: root.nombre(modelData.pluie, " %")
                        color: Qt.alpha(Theme.accent, 0.85)
                        font.pixelSize: Math.round(Theme.widgetLabel * 0.82 * root.echelle)
                        font.features: { "tnum": 1 }
                        style: Text.Raised
                        styleColor: Qt.alpha(Theme.bg, 0.55)
                    }
                }
            }
        }
    }
}
