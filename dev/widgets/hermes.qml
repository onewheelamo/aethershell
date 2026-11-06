import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// HERMES — l'état de l'agent en un coup d'œil.
//
// Même source que l'applet et le popup : le fichier d'état publié par Hermes
// (voir core/hermes_applet.py). Rien n'est interrogé par le réseau, et un état
// absent s'affiche « hors ligne » plutôt que de laisser croire au repos.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var etat: ({})
    property bool charge: false

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    // L'agent peut changer d'état à tout moment : dix secondes suffisent, et le
    // fichier est en RAM, donc le coût est nul.
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/hermes_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail || ({})).hermes || ({})
                } catch (e) {
                    root.etat = ({})
                }
                root.charge = true
            }
        }
    }

    readonly property color teinte: root.etat.etat === "erreur" ? Theme.error
                                     : root.etat.etat === "attente" ? Theme.warn
                                     : root.etat.etat === "en_cours" ? Theme.accent
                                     : Qt.alpha(Theme.fg, 0.55)

    implicitWidth: Math.round(246 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(5 * echelle)

        Row {
            width: parent.width
            spacing: Math.round(5 * echelle)

            Rectangle {
                width: Math.round(5 * echelle)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.teinte
            }

            Text {
                width: parent.width - Math.round(58 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: root.etat.etat === undefined ? "Hermes : aucun état"
                      : String(root.etat.libelle || root.etat.etat)
                color: Theme.fg
                font.pixelSize: Math.round(11 * echelle)
                elide: Text.ElideRight
            }

            Text {
                width: Math.round(48 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root.etat.jetons && root.etat.jetons.jour
                      ? String(root.etat.jetons.jour) : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(9.5 * echelle)
                font.features: { "tnum": 1 }
            }
        }

        Text {
            width: parent.width
            visible: Boolean(root.etat.tache)
            text: String(root.etat.tache || "")
            color: Qt.alpha(Theme.fg, 0.75)
            font.pixelSize: Math.round(10 * echelle)
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            visible: root.etat.etat !== undefined && root.etat.etat !== "hors_ligne"

            Text {
                width: parent.width - Math.round(48 * echelle)
                text: "en file"
                color: Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: Math.round(9.5 * echelle)
            }

            Text {
                width: Math.round(48 * echelle)
                horizontalAlignment: Text.AlignRight
                text: String(root.etat.file || 0)
                color: Qt.alpha(Theme.fg, 0.7)
                font.pixelSize: Math.round(9.5 * echelle)
                font.features: { "tnum": 1 }
            }
        }

        // Trois dernières exécutions, la plus récente en haut.
        Repeater {
            model: (root.etat.executions || []).slice(0, 3)

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                Rectangle {
                    width: Math.round(4 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: String(modelData.resultat) === "ok" ? Theme.accent : Theme.error
                }

                Text {
                    width: parent.width - Math.round(40 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.nom || "")
                    color: Qt.alpha(Theme.fg, 0.8)
                    font.pixelSize: Math.round(9.5 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(36 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: Number(modelData.duree_s || 0) + " s"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(9 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
