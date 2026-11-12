import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "."

// ══════════════════════════════════════════════════════════════════════
// DYNAMIC ISLAND (DynamicIsland.qml)
// ══════════════════════════════════════════════════════════════════════
// Îlot central dynamique style macOS / iOS / r/unixporn :
// - Compact au repos : Heure par défaut + mini lecteur audio avec contrôles
// - Morphing fluide et extension au survol de la souris
// - Révélation progressive des applets système, réseau, tray et batterie
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property bool isHovered: islandMouseArea.containsMouse || extraMouseArea.containsMouse

    // Service MPRIS direct pour la réactivité instantanée
    readonly property var players: Mpris.players.values
    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        for (let i = 0; i < players.length; i++) {
            let p = players[i]
            if (p && p.playbackState === MprisPlaybackState.Playing) return p
        }
        for (let i = 0; i < players.length; i++) {
            let p = players[i]
            if (p && p.trackTitle && p.trackTitle.length > 0) return p
        }
        return players[0] || null
    }

    readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string mediaTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string mediaArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property bool isMediaActive: (mediaTitle !== "" || isPlaying)

    // Délai de rétractation (160 ms) pour une navigation fluide sans sursauts
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
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    // Fond en pilule élégante avec bordure subtile et flou d'arrière-plan
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

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU COMPACT (AU REPOS)
    // ──────────────────────────────────────────────────────────────────────
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

            // Horloge principale affichée par défaut
            Row {
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "" // Horloge
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Qt.formatDateTime(Theme.now, "hh:mm")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
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

            // Si un média est actif : Mini-lecteur audio compact avec bouton play/pause
            Row {
                visible: root.isMediaActive
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.alpha(Theme.accent, playCompactArea.containsMouse ? 0.35 : 0.18)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "" : "" // pause / play
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: Theme.accent
                    }

                    MouseArea {
                        id: playCompactArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                    }
                }

                Text {
                    text: {
                        let t = root.mediaTitle
                        if (!t) return "Audio"
                        return t.length > 16 ? (t.substring(0, 15) + "…") : t
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Si aucun média : Badge Workspace actif en secondaire
            Row {
                visible: !root.isMediaActive
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Hyprland.focusedWorkspace ? ("WS " + Hyprland.focusedWorkspace.id) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Qt.alpha(Theme.fg, 0.75)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU ÉTENDU (AU SURVOL)
    // ──────────────────────────────────────────────────────────────────────
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

            // Centre : Horloge + Date cliquable (Calendrier) OU Média détaillé
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Si aucun média : Horloge + Date
                Row {
                    visible: !root.isMediaActive
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

                // Si média actif : Titre + Contrôles Précédent / Play / Suivant
                Row {
                    visible: root.isMediaActive
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: {
                            let t = root.mediaTitle
                            let a = root.mediaArtist
                            if (!t) return "Audio"
                            return a ? (t + " — " + a) : t
                        }
                        color: Theme.accent
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.family: Theme.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Précédent
                    Text {
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: prevMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer) root.activePlayer.previous()
                        }
                    }

                    // Play / Pause
                    Text {
                        text: root.isPlaying ? "" : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: playMouse.containsMouse ? Theme.accent : Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                        }
                    }

                    // Suivant
                    Text {
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: nextMouse.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activePlayer) root.activePlayer.next()
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.isMediaActive
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