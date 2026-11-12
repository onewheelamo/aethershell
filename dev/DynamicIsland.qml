import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// ════════════════════════════════════════════════════════════════════
// DYNAMIC ISLAND (DynamicIsland.qml)
// ════════════════════════════════════════════════════════════════════
// Îlot central dynamique style macOS / iOS / r/unixporn :
// - Compact au repos (Horloge + Bureau actif / Media indicator)
// - Morphing fluide et extension au survol de la souris
// - Révélation progressive des applets système, réseau, tray et batterie
// ════════════════════════════════════════════════════════════════════

Item {
    id: root

    property bool isHovered: islandMouseArea.containsMouse || extraMouseArea.containsMouse
    property bool isMediaActive: Theme.mediaPlaying && Theme.mediaTitle !== ""

    // Délai de rétractation (150 ms) pour une navigation fluide sans sursauts
    property bool expanded: isHovered
    onIsHoveredChanged: {
        if (isHovered) {
            retractTimer.stop()
            expanded = true
        } else {
            retractTimer.restart()
        }
    }

    Timer {
        id: retractTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (!root.isHovered) root.expanded = false
        }
    }

    implicitHeight: Theme.barHeight
    height: Theme.barHeight

    // Largeur dynamique animée selon l'état
    readonly property real compactWidth: Math.max(220, compactContentRow.implicitWidth + Theme.padH * 2)
    readonly property real expandedWidth: Math.max(520, fullContentRow.implicitWidth + Theme.padH * 2.5)

    width: expanded ? expandedWidth : compactWidth
    Behavior on width {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // Surface d'arrière-plan avec FlouFond et bordure réactive
    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: Theme.pillRadius
        color: "transparent"

        FlouFond {
            anchors.fill: parent
            rayon: Theme.pillRadius
            intensite: Theme.shellFlouInterne
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.pillRadius
            color: Theme.barBg
            opacity: root.expanded ? Math.min(1.0, Theme.shellOpacity + 0.12) : Theme.shellOpacity
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        border.color: Theme.accent
        border.width: Theme.barBorder ? 1 : 0

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }
    }

    // ────────────────────────────────────────────────────────────────────────
    // CONTENU COMPACT (AU REPOS)
    // ────────────────────────────────────────────────────────────────────────
    Item {
        id: compactContainer
        anchors.fill: parent
        opacity: root.expanded ? 0.0 : 1.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Row {
            id: compactContentRow
            anchors.centerIn: parent
            spacing: 12

            // Indicateur Workspace ou Icône Applet
            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Hyprland.focusedWorkspace ? ("WS " + Hyprland.focusedWorkspace.id) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Séparateur subtil
            Rectangle {
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Horloge compacte centrale
            Text {
                text: Qt.formatDateTime(Theme.now, "hh:mm")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.textSm
                font.weight: Font.Bold
                color: Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }

            // Indicateur Média compact (si actif)
            Row {
                visible: root.isMediaActive
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 1
                    height: 12
                    color: Theme.fg
                    opacity: 0.15
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "\uf001" // Note de musique
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // CONTENU ÉTENDU (AU SURVOL)
    // ────────────────────────────────────────────────────────────────────────
    Item {
        id: expandedContainer
        anchors.fill: parent
        opacity: root.expanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            id: fullContentRow
            anchors.fill: parent
            anchors.leftMargin: Theme.padH
            anchors.rightMargin: Theme.padH
            spacing: 12

            // Côté Gauche : Workspaces / Lanceur
            Item {
                Layout.preferredWidth: leftApplets.implicitWidth
                Layout.fillHeight: true
                AppletRow {
                    id: leftApplets
                    ile: "haut:debut"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Centre : Horloge + Date cliquable (Calendrier)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: Qt.formatDateTime(Theme.now, "hh:mm")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Qt.formatDateTime(Theme.now, "ddd d MMM")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.textXs
                        color: Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.activePopup = (Theme.activePopup === "calendar" ? "" : "calendar")
                }
            }

            // Côté Droit : Applets système, réseau, systray, batterie, etc.
            Item {
                Layout.preferredWidth: rightApplets.implicitWidth
                Layout.fillHeight: true
                AppletRow {
                    id: rightApplets
                    ile: "haut:fin"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Capteur de survol de la pilule
    MouseArea {
        id: islandMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Zone de détection légèrement élargie vers le bas pour éviter les décrochages accidentels
    MouseArea {
        id: extraMouseArea
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 10
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}