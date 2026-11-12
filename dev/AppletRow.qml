import QtQuick
import "."
import Quickshell

// RANGÉE D'APPLETS d'un îlot — résolue de manière instantanée et réactive
// via Theme.appletsPourIle(ile) en JS pur, sans sous-processus Python.
Item {
    id: root
    property string ile: "haut:fin"
    property var exclude: []
    readonly property var applets: {
        if (root.ile === "") return []
        let list = Theme.appletsPourIle(root.ile)
        if (!root.exclude || root.exclude.length === 0) return list
        return list.filter(function(a) { return root.exclude.indexOf(a.id) === -1 })
    }

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
