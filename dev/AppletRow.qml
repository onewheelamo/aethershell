import QtQuick
import "."
import Quickshell
import Quickshell.Io

// RANGÉE D'APPLETS d'un îlot. Elle demande au registre ce qui est allumé sur son
// côté (`bar_applets.py resoudre <îlot>`) et ne dessine que ça : un îlot sans
// applet n'a donc aucune largeur, aucun espace réservé.
//
// Elle réagit à l'écriture de `bar_applets.json`, donc cocher un applet dans le
// panneau l'affiche sans redémarrer le shell.
Item {
    id: root
    property string ile: "droite"
    property var applets: []

    implicitWidth: ligne.implicitWidth
    implicitHeight: ligne.implicitHeight

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

    Row {
        id: ligne
        spacing: Math.round(Theme.space3)

        Repeater {
            model: root.applets
            delegate: Applet {
                applet: modelData
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
