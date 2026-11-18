import QtQuick
import "."

Rectangle {
    id: root
    property bool checked: false
    signal toggled()

    width: 34
    height: 18
    radius: 9
    color: checked ? Theme.accent : Qt.alpha(Theme.fg, 0.22)
    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 2
        x: root.checked ? (parent.width - width - 2) : 2
        color: root.checked ? Theme.bg : Theme.fg
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
