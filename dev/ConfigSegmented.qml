import QtQuick
import "."

Rectangle {
    id: root
    property var choices: []        // [{ code, label }]
    property string currentCode: ""
    property int itemHeight: 22
    signal selected(string code)

    width: segRow.implicitWidth + 6
    height: itemHeight + 6
    radius: Math.max(5, Math.round(Theme.globalRadius * 0.5))
    color: Theme.bg
    border.color: Theme.surfaceVariant
    border.width: 1

    Row {
        id: segRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.choices
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.currentCode === String(modelData.code)
                width: segLbl.implicitWidth + 12
                height: root.itemHeight
                radius: Math.max(4, Math.round(Theme.globalRadius * 0.4))
                color: active ? Theme.accent : (segMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.6) : "transparent")

                Text {
                    id: segLbl
                    anchors.centerIn: parent
                    text: modelData.label
                    color: active ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
                    font.pixelSize: Theme.text2xs
                    font.bold: active
                }

                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(String(modelData.code))
                }
            }
        }
    }
}
