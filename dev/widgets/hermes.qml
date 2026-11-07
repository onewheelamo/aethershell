import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// HERMES — l'agent en un coup d'œil.
//
// Même source que l'applet et le popup : `core/hermes_applet.py`, qui lit la base
// de Hermes en lecture seule. Rien n'est interrogé par le réseau, et une base
// illisible s'affiche « hors ligne » plutôt que de laisser croire au repos.
//
// Les sessions vivantes passent devant les sessions finies : sur une carte de
// trois lignes, ce qui tourne compte plus que ce qui a tourné.
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

    readonly property var lignes: {
        const l = root.etat.sessions || []
        const vivantes = l.filter(function (s) { return s.vivante })
        const autres = l.filter(function (s) { return !s.vivante })
        return vivantes.concat(autres).slice(0, 3)
    }

    function jeton(n) {
        n = Number(n) || 0
        if (n >= 1e6) return (n / 1e6).toFixed(1).replace(".", ",") + " M"
        if (n >= 1e3) return Math.round(n / 1e3) + " k"
        return String(n)
    }

    function duree(s) {
        s = Number(s) || 0
        if (s >= 3600) return Math.round(s / 3600) + " h"
        if (s >= 60) return Math.round(s / 60) + " min"
        return s + " s"
    }

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    // La base bouge à chaque tour de l'agent : dix secondes suffisent, et une
    // lecture en `mode=ro` ne coûte rien.
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
                      ? root.jeton(root.etat.jetons.jour) : ""
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

        // ── trois sessions : vivantes d'abord ───────────────────────────────
        Repeater {
            model: root.lignes

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                Rectangle {
                    width: Math.round(4 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.vivante ? Theme.accent
                           : String(modelData.etat) === "inactive"
                             ? Qt.alpha(Theme.fg, 0.22) : Qt.alpha(Theme.fg, 0.45)
                }

                Text {
                    width: Math.round(44 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.profil || "")
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.pixelSize: Math.round(8.5 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width - Math.round(100 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.titre || modelData.tache || "sans titre")
                    color: modelData.vivante ? Qt.alpha(Theme.fg, 0.85)
                                             : Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Math.round(9.5 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(42 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: modelData.vivante ? root.jeton(modelData.jetons)
                                            : root.duree(modelData.duree_s)
                    color: Qt.alpha(Theme.fg, modelData.vivante ? 0.6 : 0.4)
                    font.pixelSize: Math.round(9 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.lignes.length === 0
            text: root.etat.etat === "hors_ligne" ? "base illisible" : "aucune session"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(9.5 * echelle)
        }
    }
}
