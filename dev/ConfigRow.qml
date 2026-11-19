import QtQuick
import "."

// Ligne de réglage standardisée : libellé à gauche (largeur fixe, sous-titre
// optionnel), contrôle à droite. Évite les largeurs et espacements ad hoc.
Item {
    id: rowRoot

    property string label: ""
    property string hint: ""
    property int labelWidth: 200
    property bool dimmed: false
    default property alias control: slot.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(28, Math.max(labelCol.implicitHeight, slot.implicitHeight))
    opacity: dimmed ? 0.55 : 1.0

    Row {
        anchors.fill: parent
        spacing: 12

        Column {
            id: labelCol
            width: rowRoot.labelWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: rowRoot.label
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: rowRoot.hint !== ""
                text: rowRoot.hint
                color: Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: Theme.text2xs
                elide: Text.ElideRight
            }
        }

        Row {
            id: slot
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
        }
    }
}
