import QtQuick
import Quickshell
import Quickshell.Io

// POPUP FLOTTE — l'état des autres machines.
//
// Lecture seule pour l'instant : on montre ce que la machine répond, jamais on
// n'agit. Le redémarrage distant viendra par le canal d'approbation, pas par une
// commande lancée depuis un clic.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property real corps: Theme.textXs * 1.15

    property var flotte: ({})
    property bool charge: false

    function charger() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    Timer {
        interval: 5000
        running: root.ouvert
        repeat: true
        onTriggered: root.charger()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/flotte_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.flotte = (d.detail || ({})).flotte || ({})
                } catch (e) {
                    root.flotte = ({})
                }
                root.charge = true
            }
        }
    }

    function machines() {
        const m = root.flotte.machines || {}
        const out = []
        for (const k in m) out.push(m[k])
        return out
    }

    implicitWidth: Math.round(324 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(6 * echelle)

        Text {
            text: "Flotte"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
        }

        // Cette machine d'abord : c'est la référence.
        Row {
            width: parent.width

            Text {
                width: parent.width - Math.round(96 * echelle)
                text: String((root.flotte.local || {}).nom || "cette machine")
                color: Theme.fg
                font.pixelSize: Math.round(root.corps * echelle)
                elide: Text.ElideRight
            }

            Text {
                width: Math.round(96 * echelle)
                horizontalAlignment: Text.AlignRight
                text: {
                    const l = root.flotte.local || {}
                    return (l.charge || "—") + "  ·  " + (l.ram_pct !== null && l.ram_pct !== undefined ? l.ram_pct + " %" : "—")
                }
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                font.features: { "tnum": 1 }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Repeater {
            model: root.machines()

            Row {
                required property var modelData
                width: colonne.width

                Rectangle {
                    width: Math.round(6 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: !modelData.joignable ? Theme.error
                           : (modelData.barre ? Theme.accent : Theme.warn)
                }

                Text {
                    width: parent.width - Math.round(96 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!modelData.joignable) return String(modelData.nom) + " — injoignable"
                        if (!modelData.barre) return String(modelData.nom) + " — barre arrêtée"
                        return String(modelData.nom)
                    }
                    color: modelData.joignable ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(root.corps * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(96 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: modelData.joignable
                          ? (modelData.charge || "—") + "  ·  " + (modelData.ram_pct !== null && modelData.ram_pct !== undefined ? modelData.ram_pct + " %" : "—")
                          : "—"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.machines().length === 0
            text: "Aucune machine distante déclarée dans core/flotte.json."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(root.corps * 0.85 * echelle)
            wrapMode: Text.WordWrap
        }
    }
}
