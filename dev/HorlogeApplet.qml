import QtQuick
import "."
import Quickshell

// APPLET HORLOGE — l'heure, et le calendrier qu'elle ouvre.
//
// Composant QML : il n'y a rien à interroger, juste le temps qui passe. L'heure
// porte son propre minuteur et son propre clic ; l'îlot central ne garde que la
// rangée d'applets.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    property string heure: Qt.formatTime(clock.date, "HH:mm")

    implicitWidth: texte.implicitWidth
    implicitHeight: texte.implicitHeight

    Text {
        id: texte
        text: root.heure
        color: Theme.fg
        font.pixelSize: Math.round(Theme.textLg * root.echelle)
        font.bold: true
        font.features: { "tnum": 1 }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("calendar")
        }
    }
}
