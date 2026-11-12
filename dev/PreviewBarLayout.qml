import QtQuick
import QtQuick.Layouts
import "."

// ════════════════════════════════════════════════════════════════════
// MINI PRÉVISUALISATION ANIMÉE D'AGENCEMENT DE BARRE
// (PreviewBarLayout.qml)
// ════════════════════════════════════════════════════════════════════

Item {
    id: root

    property string styleMode: "classic" // "classic" ou "island"
    property bool activeSelection: false

    implicitWidth: 260
    implicitHeight: 90

    Rectangle {
        id: previewBox
        anchors.fill: parent
        radius: Theme.btnRadius
        color: root.activeSelection ? Qt.alpha(Theme.accent, 0.14) : Theme.surface
        border.color: root.activeSelection ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
        border.width: root.activeSelection ? 2 : 1

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        // Représentation d'un écran / bureau
        Rectangle {
            id: mockScreen
            anchors.fill: parent
            anchors.margins: 10
            radius: 6
            color: "#12141a"
            clip: true

            // Faux fond d'écran légèrement texturé
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1a1d26" }
                    GradientStop { position: 1.0; color: "#0d0e13" }
                }
            }

            // ── VUE CLASSIQUE (3 îlots)
            Item {
                id: classicGroup
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 6
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: 14
                visible: root.styleMode === "classic"

                // Îlot gauche
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 12
                    radius: 6
                    color: Qt.alpha(Theme.accent, 0.35)
                    border.color: Theme.accent
                    border.width: 1
                }

                // Îlot centre
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    height: 12
                    radius: 6
                    color: Qt.alpha(Theme.accent, 0.35)
                    border.color: Theme.accent
                    border.width: 1
                }

                // Îlot droit
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 12
                    radius: 6
                    color: Qt.alpha(Theme.accent, 0.35)
                    border.color: Theme.accent
                    border.width: 1
                }
            }

            // ── VUE ÎLOT DYNAMIQUE (pilule morphing animée)
            Item {
                id: islandGroup
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 6
                height: 14
                visible: root.styleMode === "island"

                Rectangle {
                    id: animPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    height: 13
                    radius: 6.5
                    color: Qt.alpha(Theme.accent, 0.45)
                    border.color: Theme.accent
                    border.width: 1

                    // Animation cyclique simulant l'extension au survol / média
                    SequentialAnimation on width {
                        loops: Animation.Infinite
                        running: root.styleMode === "island"

                        NumberAnimation { to: 42; duration: 1400; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 800 }
                        NumberAnimation { to: 120; duration: 400; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 1600 }
                        NumberAnimation { to: 42; duration: 400; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 600 }
                    }

                    // Mini point d'accent à l'intérieur
                    Rectangle {
                        width: 4
                        height: 4
                        radius: 2
                        color: Theme.accent
                        anchors.left: parent.left
                        anchors.leftMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Fausse fenêtre d'application en dessous
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.top: parent.top
                anchors.margins: 6
                anchors.topMargin: 26
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.04)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
            }
        }
    }
}