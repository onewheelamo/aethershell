import QtQuick
import "."
import Quickshell

// RANGÉE VERTICALE D'APPLETS — résolue de manière instantanée et réactive
// via Theme.appletsPourIle(ile) en JS pur, sans sous-processus Python.
Item {
    id: root
    property string ile: "cote-gauche:milieu"
    readonly property var applets: root.ile !== "" ? Theme.appletsPourIle(root.ile) : []

    implicitWidth: colonne.implicitWidth
    implicitHeight: colonne.implicitHeight

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
