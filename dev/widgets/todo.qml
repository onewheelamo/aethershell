import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// TÂCHES — les cases à cocher des fichiers Markdown de l'utilisateur.
//
// Même source que l'applet et le popup : `core/todo_applet.py`. Le widget compte
// les items ouverts et montre les premiers ; une demande déposée par une coche
// passe en couleur d'accent, parce que c'est elle qui attend une action.
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
    readonly property var ouverts: {
        const l = (root.etat.items || []).filter(function (i) { return !i.fait || i.demande })
        return l.slice(0, 3)
    }

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        // Le widget voit **tous** les fichiers ; l'applet n'en montre qu'un.
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"), "etat",
                  "--options={\"fichier\": \"*\"}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail && d.detail.todo) ? d.detail.todo : d
                } catch (e) {
                    root.etat = ({})
                }
            }
        }
    }

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
                width: Math.round(10 * echelle)
                height: width
                radius: Math.round(2 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: (root.etat.demandes || []).length > 0
                              ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                Icon {
                    anchors.centerIn: parent
                    visible: (root.etat.demandes || []).length > 0
                    glyph: "check"
                    size: Math.round(7 * echelle)
                    color: Theme.accent
                }
            }

            Text {
                width: parent.width - Math.round(60 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: root.etat.ouverts !== undefined
                      ? root.etat.ouverts + (root.etat.ouverts > 1 ? " tâches" : " tâche")
                      : "tâches"
                color: Theme.fg
                font.pixelSize: Math.round(11 * echelle)
                elide: Text.ElideRight
            }

            Text {
                width: Math.round(52 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: (root.etat.demandes || []).length > 0
                      ? root.etat.demandes.length + " att." : ""
                color: Qt.alpha(Theme.accent, 0.9)
                font.pixelSize: Math.round(9 * echelle)
            }
        }

        Repeater {
            model: root.ouverts

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                Rectangle {
                    width: Math.round(4 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.demande ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                }

                // Plusieurs fichiers alimentent ce widget : la provenance évite de
                // confondre deux items homonymes. Masquée quand un seul fichier est
                // suivi — le nom n'apprendrait alors rien.
                Text {
                    width: Math.round(34 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (root.etat.fichiers || []).length > 1
                    text: String(modelData.nom_fichier || "")
                    color: Qt.alpha(Theme.fg, 0.35)
                    font.pixelSize: Math.round(8.5 * echelle)
                    elide: Text.ElideRight
                }

                // Plusieurs fichiers alimentent ce widget : la provenance est
                // dans le texte, sinon deux items homonymes deviennent ambigus.
                Text {
                    width: parent.width - Math.round(42 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.titre)
                    color: modelData.demande ? Qt.alpha(Theme.accent, 0.95)
                                             : Qt.alpha(Theme.fg, 0.75)
                    font.pixelSize: Math.round(9.5 * echelle)
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            visible: root.ouverts.length === 0
            text: root.etat.fichiers && root.etat.fichiers.length > 0
                  ? "aucune tâche ouverte" : "aucun fichier surveillé"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(9.5 * echelle)
        }
    }
}
