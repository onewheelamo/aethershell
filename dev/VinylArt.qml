import QtQuick
import QtQuick.Effects
import "."

// ══════════════════════════════════════════════════════════════════════
// ILLUSTRATION ALBUM FAÇON TOURNE-DISQUE (VinylArt.qml)
// ══════════════════════════════════════════════════════════════════════
// Disque vinyle circulaire avec rotation continue en lecture, sillons
// subtils et trou central. Utilisé par IslandTabControles et IslandTabMedia.
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property string artUrl: ""
    property bool playing: false
    property int iconSize: 28

    // Conteneur rotatif (image + fallback)
    Item {
        id: discContainer
        anchors.fill: parent

        FrameAnimation {
            running: root.playing && root.visible
            onTriggered: discContainer.rotation = (discContainer.rotation + frameTime * 40) % 360
        }

        // Masque circulaire hors-écran pour MultiEffect
        Rectangle {
            id: circleMask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }

        Image {
            id: artImg
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: false
            smooth: true
            asynchronous: true
        }

        MultiEffect {
            anchors.fill: parent
            source: artImg
            visible: root.artUrl !== "" && artImg.status === Image.Ready
            maskEnabled: true
            maskSource: circleMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // Fallback icône quand aucune pochette n'est fournie ou chargée
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: root.artUrl === "" || artImg.status !== Image.Ready
            color: Qt.alpha(Theme.accent, 0.16)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.35)

            Icon {
                anchors.centerIn: parent
                glyph: "music"
                size: root.iconSize
                color: Theme.accent
            }
        }

        // Sillons subtils de vinyle
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha("#ffffff", 0.10)
        }
    }

    // Bordure extérieure du disque
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: Qt.alpha(Theme.accent, root.playing ? 0.55 : 0.25)
    }

    // Moyeu central façon tourne-disque
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(14, Math.round(parent.width * 0.24))
        height: width
        radius: width / 2
        color: Theme.surfaceBg
        border.width: 2
        border.color: Qt.alpha(Theme.accent, 0.65)

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(5, Math.round(parent.width * 0.36))
            height: width
            radius: width / 2
            color: Theme.bg
        }
    }
}
