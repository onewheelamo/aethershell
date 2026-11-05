import QtQuick
import "."

// APPLET NOTIFICATIONS — la cloche et son compteur.
//
// Le centre de notifications (serveur, toasts, historique, actions) reste dans
// l'îlot droit : c'est un service, pas un élément de barre. L'applet n'est que
// le bouton — elle ouvre la même clé `notifications`, que le panneau écoute.
// Le compteur lui est passé par `Theme.notifCount`, pont posé par l'îlot qui
// possède la liste : un applet ne peut pas lire les identifiants d'un autre
// fichier.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    readonly property bool ouvert: Theme.activePopup === "notifications"
    readonly property int compte: Theme.notifCount

    implicitWidth: rangee.implicitWidth + Math.round(10 * echelle)
    implicitHeight: Math.max(22, Math.round(26 * echelle))

    Rectangle {
        anchors.fill: parent
        radius: Theme.globalRadius
        color: root.ouvert
            ? Theme.accent
            : (souris.containsMouse ? Theme.surfaceVariant : "transparent")

        Behavior on color { ColorAnimation { duration: 140 } }

        Row {
            id: rangee
            anchors.centerIn: parent
            spacing: Math.round(4 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.compte > 0 ? "bell" : "bell-off"
                size: Math.max(11, Math.round(Theme.iconSm * echelle))
                color: root.ouvert ? Theme.bg : (root.compte > 0 ? Theme.warn : Theme.fg)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.compte > 0
                text: String(root.compte)
                color: root.ouvert ? Theme.bg : Theme.warn
                font.pixelSize: Math.round(Theme.textXs * echelle)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("notifications")
        }
    }
}
