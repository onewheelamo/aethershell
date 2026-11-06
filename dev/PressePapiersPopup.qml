import QtQuick
import Quickshell
import Quickshell.Io

// POPUP PRESSE-PAPIERS — les dernières copies, cliquables.
//
// `cliphist` garde l'historique ; ce panneau se contente de le lire, de le
// tronquer pour l'affichage, et de remettre une entrée dans le presse-papiers au
// clic. Le bouton « vider » efface l'historique (pas le presse-papiers courant).
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }

    property var entrees: []
    property bool charge: false
    property string statut: ""

    function charger() {
        liste.running = false
        liste.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    Process {
        id: liste
        command: ["python3", Quickshell.shellPath("core/presse_papiers_applet.py"), "liste", "12"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.entrees = Array.isArray(d.entrees) ? d.entrees : []
                } catch (e) {
                    root.entrees = []
                }
                root.charge = true
            }
        }
    }

    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: root.charger()
        }
    }

    function copier(id) {
        statut = "copié"
        action.command = ["python3", Quickshell.shellPath("core/presse_papiers_applet.py"),
                          "copier", String(id)]
        action.running = true
        // Le panneau se referme : on a ce qu'on voulait, il n'a plus à occuper l'écran.
        Theme.activePopup = ""
    }

    function vider() {
        action.command = ["python3", Quickshell.shellPath("core/presse_papiers_applet.py"), "vider"]
        action.running = true
    }

    implicitWidth: Math.round(320 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(6 * echelle)

        Text {
            text: "Presse-papiers"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
        }

        Text {
            visible: root.entrees.length === 0
            text: root.charge ? "historique vide" : "lecture…"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(Theme.textXs * echelle)
        }

        Repeater {
            model: root.entrees

            Rectangle {
                required property var modelData
                width: colonne.width
                height: Math.round(24 * echelle)
                radius: 5
                color: survol.containsMouse ? Qt.alpha(Theme.accent, 0.16) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    text: String(modelData.apercu || "")
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.textXs * 0.95 * echelle)
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: survol
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copier(modelData.id)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.round(24 * echelle)
            radius: Theme.globalRadius
            color: viderSouris.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.08)

            Text {
                anchors.centerIn: parent
                text: "Vider l'historique"
                color: viderSouris.containsMouse ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                font.pixelSize: Math.round(Theme.textXs * 0.9 * echelle)
                font.bold: true
            }

            MouseArea {
                id: viderSouris
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.vider()
            }
        }
    }
}
