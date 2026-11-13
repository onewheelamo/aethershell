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

    readonly property string ile: "haut:milieu"

    // Panneau calendrier interactif rattaché à l'îlot dynamique
    Loader {
        id: calPanneauLoader
        active: Theme.barStyle === "island"
        source: "CalendrierPanneau.qml"
        onLoaded: {
            if (!item) return
            item.ancre = Qt.binding(() => root)
            item.ouvert = Qt.binding(() => Theme.barStyle === "island" && Theme.activePopup === "calendar")
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
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

    readonly property bool isCalendarOpen: Theme.activePopup === "calendar"
    readonly property bool isPopupOpen: Theme.activePopup !== ""
    readonly property bool panelOpen: Theme.islandPanelOpen
    readonly property string etat: panelOpen ? "panneau" : (expanded ? "etendu_barre" : "compact")

    // Attrapeur de focus Hyprland armé à +150 ms à l'ouverture du panneau
    property bool pretGrab: false
    onPanelOpenChanged: {
        if (panelOpen) {
            retractTimer.stop()
            expanded = true
            pretGrab = false
            delaiGrab.restart()
            panelContainer.forceActiveFocus()
        } else {
            delaiGrab.stop()
            pretGrab = false
            Theme.islandNeedsKeyboard = false
            if (!isHovered && !isPopupOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrab
        interval: 150
        repeat: false
        onTriggered: if (root.panelOpen) root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.panelOpen && root.pretGrab
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (root.panelOpen) {
                Theme.islandPanelOpen = false
                Theme.islandNeedsKeyboard = false
            }
        }
    }

    function ouvrirPanneau(tabIdx) {
        Theme.activePopup = ""
        if (tabIdx !== undefined) Theme.islandPanelTab = tabIdx
        Theme.islandPanelOpen = true
    }

    // Délai de rétractation (160 ms) pour une navigation fluide sans sursauts
    property bool expanded: isHovered || isPopupOpen || panelOpen
    onIsHoveredChanged: {
        if (isHovered || isPopupOpen || panelOpen) {
            retractTimer.stop()
            expanded = true
        } else {
            retractTimer.restart()
        }
    }
    onIsPopupOpenChanged: {
        if (isPopupOpen || panelOpen) {
            retractTimer.stop()
            expanded = true
        } else if (!isHovered) {
            retractTimer.restart()
        }
    }

    Timer {
        id: retractTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (!root.isHovered && !root.isPopupOpen && !root.panelOpen) root.expanded = false
        }
    }

    implicitHeight: panelOpen ? 420 : Theme.barHeight
    height: panelOpen ? 420 : Theme.barHeight
    Behavior on height {
        NumberAnimation {
            duration: Theme.panelAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // Largeur dynamique animée selon l'état
    readonly property real osdWidth: Math.max(160, osdRow.implicitWidth + Theme.padH * 2 + 16)
    readonly property real compactRestWidth: Math.max(90, compactContentRow.implicitWidth + Theme.padH * 2)
    readonly property real compactWidth: Theme.osdVisible ? osdWidth : compactRestWidth
    readonly property real expandedWidth: Math.max(
        460,
        leftApplets.implicitWidth
        + clockDateRow.implicitWidth
        + rightApplets.implicitWidth
        + (Theme.showConfigButton ? 36 : 0)
        + Theme.padH * 3 + 28
    )

    readonly property int sidePanelWidth: (panelOpen && Theme.islandSidePanel !== "") ? 340 : 0
    width: panelOpen ? (680 + sidePanelWidth) : (expanded ? expandedWidth : compactWidth)

    Behavior on width {
        NumberAnimation {
            duration: Theme.panelAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // Fond en pilule élégante avec surface floutée unifiée (identique à config_panel / PanneauSurface)
    SurfaceFloutee {
        id: bgRect
        anchors.fill: parent
        rayon: root.panelOpen ? Math.max(Theme.pillRadius, 18) : Theme.pillRadius
        Behavior on rayon { NumberAnimation { duration: Math.max(80, Theme.panelAnimDuration - 20); easing.type: Easing.OutCubic } }
        teinte: root.panelOpen ? Theme.surfaceBg : Theme.barBg
        bordureCouleur: (root.isCalendarOpen || root.panelOpen) ? Theme.accentMuted : Theme.accent
        bordureLargeur: Theme.barBorder ? 1 : 0
        actif: root.panelOpen
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU COMPACT (AU REPOS)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: compactContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight
        opacity: (root.expanded || root.panelOpen) ? 0.0 : 1.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // Clic sur la pilule compacte : ouvre le panneau de raccourcis (façon Android)
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.ouvrirPanneau(0)
        }

        // 1. OSD actif : affiche le volume / luminosité dans la pilule
        Row {
            id: osdRow
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
                font.family: Theme.fontUi
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

            // Horloge principale sans glyphe (clic -> panneau étendu)
            Text {
                text: Qt.formatTime(clock.date, "HH:mm")
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                font.weight: Font.Bold
                color: Theme.fg
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
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
                        font.family: Theme.fontUi
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
                    font.family: Theme.fontUi
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight
        opacity: (root.expanded && !root.panelOpen) ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            id: fullContentRow
            anchors.fill: parent
            anchors.leftMargin: Theme.padH
            anchors.rightMargin: Theme.padH
            spacing: 12

            // Côté Gauche : Workspaces / Programmes minimisés / Systray / Batterie
            Item {
                Layout.preferredWidth: leftApplets.implicitWidth
                Layout.fillHeight: true
                AppletRow {
                    id: leftApplets
                    ile: "haut:debut"
                    include: ["systray", "workspaces", "minimise", "luminosite", "batterie"]
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item { Layout.fillWidth: true }

            // Centre : Horloge + Date (clic -> panneau étendu ; plus de lecteur dans la barre déployée)
            Item {
                Layout.preferredWidth: clockDateRow.implicitWidth
                Layout.fillWidth: false
                Layout.fillHeight: true

                Row {
                    id: clockDateRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: Qt.formatTime(clock.date, "HH:mm")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Qt.formatDate(clock.date, "ddd d MMM")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Medium
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            Item { Layout.fillWidth: true }

            // Côté Droit : Systray / Batterie / Workspaces / Programmes minimisés
            Item {
                Layout.preferredWidth: rightApplets.implicitWidth
                Layout.fillHeight: true
                AppletRow {
                    id: rightApplets
                    ile: "haut:fin"
                    include: ["systray", "workspaces", "minimise", "luminosite", "batterie"]
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Bouton d'accès rapide au panneau de configuration
            Rectangle {
                visible: Theme.showConfigButton
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: Theme.globalRadius
                color: Theme.configPanelVisible
                    ? Theme.accent
                    : (islandGearMa.containsMouse ? Theme.surfaceVariant : "transparent")

                Icon {
                    anchors.centerIn: parent
                    glyph: "cog"
                    size: Theme.iconMd
                    color: Theme.configPanelVisible ? Theme.bg : Theme.fg
                    opacityLevel: 1
                }

                MouseArea {
                    id: islandGearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.configPanelVisible = !Theme.configPanelVisible
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU PANNEAU ÉTENDU (ÉTAT 3 : 680 × 420 px, RAIL 5 ONGLETS)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: panelContainer
        anchors.fill: parent
        clip: true
        focus: root.panelOpen
        Keys.onEscapePressed: Theme.islandPanelOpen = false
        opacity: root.panelOpen ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Loader {
            id: islandPanelLoader
            anchors.fill: parent
            active: true
            asynchronous: true
            source: "IslandPanel.qml"
            onLoaded: {
                if (!item) return
                item.clockDate = Qt.binding(() => clock.date)
                item.activePlayer = Qt.binding(() => root.activePlayer)
                item.validPlayers = Qt.binding(() => root.validPlayers)
                item.isPlaying = Qt.binding(() => root.isPlaying)
                item.mediaTitle = Qt.binding(() => root.mediaTitle)
                item.isMediaActive = Qt.binding(() => root.isMediaActive)
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