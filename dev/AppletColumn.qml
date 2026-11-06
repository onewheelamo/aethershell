import QtQuick
import "."
import Quickshell
import Quickshell.Io

// RANGÉE VERTICALE D'APPLETS — la même mécanique que `AppletRow`, pour les
// barres de côté. Un applet n'a pas de forme propre : ici ils s'empilent, et
// chacun garde son icône et sa valeur sur une ligne.
Item {
    id: root
    property string ile: "cote-gauche"
    property var applets: []

    implicitWidth: colonne.implicitWidth
    implicitHeight: colonne.implicitHeight

    FileView {
        path: Quickshell.shellPath("core/bar_applets.json")
        watchChanges: true
        onFileChanged: root.resoudre()
        onTextChanged: root.resoudre()
    }

    Process {
        id: requete
        command: ["python3", Quickshell.shellPath("core/bar_applets.py"),
                  "resoudre", root.ile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text.trim())
                    root.applets = Array.isArray(liste) ? liste : []
                } catch (e) {
                    root.applets = []
                }
            }
        }
    }

    function resoudre() {
        requete.running = false
        requete.running = true
    }

    Component.onCompleted: root.resoudre()

    Column {
        id: colonne
        spacing: Math.round(Theme.space3)

        Repeater {
            model: root.applets
            delegate: Applet {
                applet: modelData
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
