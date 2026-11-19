import QtQuick
import "."

// Bouton d'état binaire uniforme (« ✓ Actif » / « ✕ Désactivé »).
Rectangle {
    id: btn

    property bool active: false
    property string onLabel: "✓ Actif"
    property string offLabel: "✕ Désactivé"
    property int pillWidth: 160

    signal toggled()

    width: pillWidth
    height: 26
    radius: Theme.globalRadius
    color: active
        ? Theme.accent
        : (ma.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.85) : Theme.surfaceVariant)
    border.color: Theme.accent
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: btn.active ? btn.onLabel : btn.offLabel
        color: btn.active ? Theme.bg : Theme.fg
        font.pixelSize: Theme.textXs
        font.bold: btn.active
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.toggled()
    }
}
