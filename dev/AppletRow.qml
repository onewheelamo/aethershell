import QtQuick
import "."
import Quickshell

// RANGÉE D'APPLETS d'un îlot — résolue de manière instantanée et réactive
// via Theme.appletsPourIle(ile) en JS pur, sans sous-processus Python.
Item {
    id: root
    property string ile: "haut:fin"
    readonly property var applets: root.ile !== "" ? Theme.appletsPourIle(root.ile) : []

    implicitWidth: ligne.implicitWidth
    implicitHeight: ligne.implicitHeight

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
