import QtQuick
import Quickshell
import Quickshell.Io

// POPUP MÉTÉO — ce que la barre ne peut pas dire : condition, ressenti, min/max,
// ville, et l'état « dernière valeur connue » quand le réseau est tombé.
//
// La source est `core/weather_service.py`, la même que l'applet et le widget :
// un seul service, un cache de dix minutes, et l'applet ne fait que choisir ce
// que la barre affiche. Le popup relit à l'ouverture et toutes les dix minutes.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    // Renseigné par Applet.qml quand le popup est chargé dans la barre.
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }

    readonly property var meteo: Theme.meteoData
    readonly property string statut: Theme.meteoStatut

    function rafraichir() {
        Theme.rafraichirMeteo(false)
    }

    onOuvertChanged: if (ouvert) rafraichir()
    Component.onCompleted: rafraichir()

    readonly property string glyphe: {
        const i = String(root.meteo.icon || "").toLowerCase()
        if (i === "sun" || i === "clear") return "sun"
        if (i === "moon" || i === "night") return "weather-night"
        if (i === "cloud" || i === "overcast") return "cloud"
        if (i === "fog" || i === "rain" || i === "drizzle" || i === "snow" || i === "storm")
            return "weather-cloud"
        return root.meteo.day === false ? "weather-night" : "cloud"
    }

    function deg(valeur) {
        const n = Number(valeur)
        return isFinite(n) ? Math.round(n) + "°" : "—"
    }

    function heure(secondes) {
        const n = Number(secondes)
        if (!isFinite(n) || n <= 0) return ""
        return new Date(n * 1000).toLocaleTimeString(Qt.locale(), "HH:mm")
    }

    implicitWidth: Math.round(250 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(9 * echelle)

        Row {
            width: parent.width
            spacing: Math.round(10 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.glyphe
                size: Math.round(30 * echelle)
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.statut !== "" ? "—" : root.deg(root.meteo.temp)
                color: Theme.fg
                font.pixelSize: Math.round(32 * echelle)
                font.bold: true
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Math.round(120 * echelle)
                spacing: 1

                Text {
                    width: parent.width
                    text: String(root.meteo.label || (root.statut !== "" ? "météo indisponible" : ""))
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.textSm * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: String(root.meteo.city || "")
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(Theme.textXs * echelle)
                    elide: Text.ElideRight
                }
            }
        }

        // Ressenti et extrêmes : ce qu'on cherche en ouvrant le popup.
        Text {
            visible: root.statut === "" && root.meteo.temp !== undefined
            text: "Ressenti " + root.deg(root.meteo.feels)
                  + "  ·  min " + root.deg(root.meteo.tmin)
                  + " / max " + root.deg(root.meteo.tmax)
            color: Qt.alpha(Theme.fg, 0.7)
            font.pixelSize: Math.round(Theme.textXs * echelle)
        }

        // Réseau tombé : le service sert la dernière valeur connue. Le dire vaut
        // mieux que de la présenter comme actuelle.
        Text {
            visible: root.statut === "" && root.meteo.cached === true
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Dernière valeur connue" + (root.heure(root.meteo.updated) !== ""
                  ? " (" + root.heure(root.meteo.updated) + ")" : "")
            color: Theme.accentMuted
            font.pixelSize: Math.round(Theme.textXs * echelle)
        }

        Text {
            visible: root.statut !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.statut
            color: Theme.error
            font.pixelSize: Math.round(Theme.textXs * echelle)
        }
    }
}
