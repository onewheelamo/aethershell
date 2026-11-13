import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// PRESSE-PAPIERS — les dernières copies, cliquables.
//
// Même source que l'applet (cliphist). Un clic remet l'entrée dans le
// presse-papiers ; le compte en tête dit combien d'entrées l'historique contient.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var entrees: []
    property int total: 0
    property bool charge: false
    property string statut: ""

    function rafraichir() {
        liste.running = false
        liste.running = true
    }

    Component.onCompleted: root.rafraichir()

    // Veille événementielle sur la base cliphist (P2) : remplace le sondage 15 s.
    Timer {
        id: clipDebounce
        interval: 150
        repeat: false
        onTriggered: root.rafraichir()
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache")) + "/cliphist/db"
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: clipDebounce.restart()
    }

    Process {
        id: liste
        command: ["python3", Quickshell.shellPath("core/presse_papiers_applet.py"), "liste", "6"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.entrees = Array.isArray(d.entrees) ? d.entrees : []
                    // Le service rend le compte de tout l'historique ; à défaut,
                    // on retombe sur la page reçue plutôt que d'afficher 0.
                    const total = Number(d.total)
                    root.total = isFinite(total) ? total : root.entrees.length
                } catch (e) {
                    root.entrees = []
                    root.total = 0
                }
                root.charge = true
            }
        }
    }

    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                root.statut = "copié"
                root.rafraichir()
            }
        }
    }

    function copier(id) {
        action.command = ["python3", Quickshell.shellPath("core/presse_papiers_applet.py"),
                          "copier", String(id)]
        action.running = true
    }

    implicitWidth: Math.round(244 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(5 * echelle)

        Row {
            width: parent.width

            Text {
                width: parent.width - Math.round(40 * root.echelle)
                text: "presse-papiers"
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(10 * root.echelle)
            }

            Text {
                width: Math.round(40 * root.echelle)
                horizontalAlignment: Text.AlignRight
                text: String(root.total)
                color: Qt.alpha(Theme.accent, 0.9)
                font.pixelSize: Math.round(11 * root.echelle)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        Repeater {
            model: root.entrees

            Rectangle {
                required property var modelData
                width: colonne.width
                height: Math.round(20 * root.echelle)
                radius: 4
                color: survol.containsMouse ? Qt.alpha(Theme.accent, 0.16) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    text: String(modelData.apercu || "")
                    color: Theme.fg
                    font.pixelSize: Math.round(10 * root.echelle)
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

        Text {
            visible: root.charge && root.entrees.length === 0
            text: "historique vide"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(9.5 * root.echelle)
        }
    }
}
