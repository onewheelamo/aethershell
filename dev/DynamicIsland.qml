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

    property var currentTime: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.currentTime = new Date()
    }

    property bool isHovered: islandMouseArea.containsMouse || extraMouseArea.containsMouse

    // Service MPRIS direct pour la réactivité instantanée
    readonly property var players: Mpris.players.values

    // Respecte le filtre navigateur activé dans les réglages de l'applet musique
    readonly property bool ignorerNavigateurs: {
        let a = (Theme.barAppletsActifs && Theme.barAppletsActifs["musique"]) ? Theme.barAppletsActifs["musique"].options : null
        return (a && a.ignorer_navigateurs !== undefined) ? Boolean(a.ignorer_navigateurs) : true
    }

    function isBrowserPlayer(p) {
        if (!p) return false
        let id = (p.identity || "").toLowerCase()
        let entry = (p.desktopEntry || "").toLowerCase()
        let bus = (p.busName || "").toLowerCase()
        const navs = ["firefox", "chromium", "chrome", "brave", "vivaldi", "epiphany", "zen", "edge", "opera"]
        return navs.some(n => id.indexOf(n) !== -1 || entry.indexOf(n) !== -1 || bus.indexOf(n) !== -1)
    }

    readonly property var validPlayers: {
        if (!players || players.length === 0) return []
        let res = []
        for (let i = 0; i < players.length; i++) {
            let p = players[i]
            if (!p) continue
            if (root.ignorerNavigateurs && isBrowserPlayer(p)) continue
            res.push(p)
        }
        return res
    }

    readonly property var activePlayer: {
        let list = validPlayers
        if (!list || list.length === 0) return null
        // 1. Cherche en priorité un lecteur en cours de lecture avec titre
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.playbackState === MprisPlaybackState.Playing && p.trackTitle && p.trackTitle.trim().length > 0) {
                return p
            }
        }
        // 2. Cherche un lecteur avec titre valide (même en pause)
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.trackTitle && p.trackTitle.trim().length > 0) {
                return p
            }
        }
        // 3. Lecteur en cours de lecture quelconque
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return list[0] || null
    }

    readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string mediaTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string mediaArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property bool isMediaActive: (mediaTitle.trim() !== "")

    // Synchronise Theme.mediaPlaying si nécessaire
    onIsPlayingChanged: Theme.mediaPlaying = isPlaying
    onMediaTitleChanged: Theme.mediaTitle = mediaTitle
    onMediaArtistChanged: Theme.mediaArtist = mediaArtist

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
    readonly property real expandedWidth: Math.max(460, leftApplets.implicitWidth + (root.isMediaActive ? mediaDetailRow.implicitWidth : clockDateRow.implicitWidth) + rightApplets.implicitWidth + Theme.padH * 3 + 28)

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
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // 1. OSD actif : affiche le volume / luminosité dans la pilule
        Row {
            anchors.centerIn: parent
            spacing: 8
            visible: Theme.osdVisible

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: Theme.osdKind === "brightness" ? "brightness"
                    : Theme.osdKind === "mute" ? "volume-off"
                    : (Theme.osdValue <= 0 ? "mute" : Theme.osdValue < 50 ? "volume-medium" : "volume-high")
                size: Theme.iconSm
                color: Theme.accent
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                height: 4
                radius: 2
                color: Theme.surfaceVariant
                Rectangle {
                    width: parent.width * (Theme.osdValue / 100)
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Theme.osdValue) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.fg
            }
        }

        // 2. Repos : Heure pure (sans glyphe) et lecteur audio
        Row {
            id: compactContentRow
            anchors.centerIn: parent
            spacing: 12
            visible: !Theme.osdVisible

            // Horloge principale sans glyphe
            Text {
                text: Qt.formatDateTime(root.currentTime, "hh:mm")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.textSm
                font.weight: Font.Bold
                color: Theme.fg
                anchors.verticalCenter: parent.verticalCenter
            }

            // Séparateur subtil (uniquement si média actif)
            Rectangle {
                visible: root.isMediaActive
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
                        text: root.isPlaying ? "󰏤" : "󰐊" // pause / play
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
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU ÉTENDU (AU SURVOL)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: expandedContainer
        anchors.fill: parent
        opacity: root.expanded ? 1.0 : 0.0
        visible: opacity > 0.05
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
                Layout.preferredWidth: root.isMediaActive ? mediaDetailRow.implicitWidth : clockDateRow.implicitWidth
                Layout.fillWidth: false
                Layout.fillHeight: true

                // Si aucun média : Horloge + Date
                Row {
                    id: clockDateRow
                    visible: !root.isMediaActive
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: Qt.formatDateTime(root.currentTime, "hh:mm")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Qt.formatDateTime(root.currentTime, "ddd d MMM")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Medium
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Si média actif : Titre + Contrôles Précédent / Play / Suivant
                Row {
                    id: mediaDetailRow
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
                            let s = a ? (t + " — " + a) : t
                            return s.length > 28 ? (s.substring(0, 26) + "…") : s
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
                    onClicked: Theme.activePopup = (Theme.activePopup === "calendrier" ? "" : "calendrier")
                }
            }

            // Côté Droit : Applets système, réseau, systray, batterie, etc.
            // L'applet "musique" est exclue pour éviter le doublon avec le lecteur central
            Item {
                Layout.preferredWidth: rightApplets.implicitWidth
                Layout.fillHeight: true
                AppletRow {
                    id: rightApplets
                    ile: "haut:fin"
                    exclude: ["musique"]
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