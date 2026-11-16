import QtQuick
import ".."
import Quickshell

// STICKER / IMAGE — visuel PNG, SVG ou WebP posé sur le bureau.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property string imagePath: String((options && options.image) || "").trim()
    readonly property int baseSize: Math.round(140 * echelle)

    implicitWidth: baseSize
    implicitHeight: baseSize

    Image {
        anchors.fill: parent
        visible: root.imagePath !== ""
        source: root.imagePath !== ""
            ? (root.imagePath.indexOf("://") !== -1 ? root.imagePath : ("file://" + root.imagePath))
            : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Column {
        visible: root.imagePath === ""
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: "palette"
            size: Math.round(32 * root.echelle)
            color: Qt.alpha(Theme.accent, 0.75)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sticker (image)"
            color: Qt.alpha(Theme.fg, 0.6)
            font.family: Theme.fontUi
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
        }
    }
}
