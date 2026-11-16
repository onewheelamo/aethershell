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

    // Indicateurs VPN (droite) et capture vidéo/audio (gauche avant les ws)
    property string vpnState: "disconnected" // "connected" | "disconnected" | "error"
    property string captureState: "none"     // "video" | "audio" | "none"
    property bool plankaEcheanceProche: false
    property string plankaUrgence: "none"    // "none" | "orange" | "rouge"

    Process {
        id: plankaStatutProc
        command: ["python3", Quickshell.shellPath("core/planka_service.py"), "statut"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.plankaEcheanceProche = Boolean(d && d.echeance_proche)
                    root.plankaUrgence = String((d && d.urgence) || "none")
                } catch (e) {}
            }
        }
    }

    Timer {
        id: plankaStatutTimer
        interval: 60000
        repeat: true
        running: Theme.barStyle === "island" && Theme.ilotProjetsActif
        triggeredOnStart: true
        onTriggered: if (!plankaStatutProc.running) plankaStatutProc.running = true
    }

    Process {
        id: indicateursProc
        command: ["python3", Quickshell.shellPath("core/indicateurs_service.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d.vpn === "string") root.vpnState = d.vpn
                    if (d && typeof d.capture === "string") root.captureState = d.capture
                } catch (e) {}
            }
        }
    }

    Timer {
        id: indicateursTimer
        interval: 3000
        repeat: true
        running: Theme.barStyle === "island"
        triggeredOnStart: true
        onTriggered: if (!indicateursProc.running) indicateursProc.running = true
    }

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
    readonly property bool notifToastActive: Theme.barStyle === "island"
        && Theme.notifToastVisible
        && Theme.notifToast !== null
        && !panelOpen
    readonly property bool meteoExpanded: Theme.barStyle === "island"
        && Theme.activePopup === "applet:meteo"
        && !panelOpen
        && !notifToastActive
    readonly property string etat: panelOpen ? "panneau" : (notifToastActive ? "toast" : (meteoExpanded ? "meteo" : (expanded ? "etendu_barre" : "compact")))

    // Attrapeur de focus Hyprland pour l'extension météo inline (clic extérieur -> ferme)
    property bool pretGrabMeteo: false
    onMeteoExpandedChanged: {
        if (meteoExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabMeteo = false
            delaiGrabMeteo.restart()
            Theme.rafraichirMeteo(false)
            meteoContainer.forceActiveFocus()
        } else {
            delaiGrabMeteo.stop()
            pretGrabMeteo = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabMeteo
        interval: 150
        repeat: false
        onTriggered: if (root.meteoExpanded) root.pretGrabMeteo = true
    }

    HyprlandFocusGrab {
        active: root.meteoExpanded && root.pretGrabMeteo
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.activePopup === "applet:meteo") Theme.activePopup = ""
        }
    }

    Binding {
        target: Theme
        property: "notifToastHovered"
        value: root.notifToastActive && root.isHovered
    }

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
            Theme.islandNavActive = false
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
                Theme.islandNavActive = false
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

    readonly property real toastHeight: Math.max(Theme.barHeight + 24, toastContentCol.implicitHeight + 24)
    readonly property real meteoHeight: Math.max(140, meteoContentCol.implicitHeight + 28)
    implicitHeight: panelOpen ? 420 : (notifToastActive ? toastHeight : (meteoExpanded ? meteoHeight : Theme.barHeight))
    height: panelOpen ? 420 : (notifToastActive ? toastHeight : (meteoExpanded ? meteoHeight : Theme.barHeight))
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
    readonly property real meteoWidth: Math.max(410, meteoContentCol.implicitWidth + 32)
    readonly property real expandedWidth: Math.max(
        compactRestWidth,
        fullContentRow.implicitWidth + Theme.padH * 2
    )

    readonly property int sidePanelWidth: (panelOpen && Theme.islandSidePanel !== "") ? 340 : 0
    width: panelOpen ? (680 + sidePanelWidth) : (notifToastActive ? 400 : (meteoExpanded ? meteoWidth : (expanded ? expandedWidth : compactWidth)))

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
        rayon: root.panelOpen ? Math.max(Theme.pillRadius, 18) : ((root.notifToastActive || root.meteoExpanded) ? Math.max(Theme.globalRadius, 16) : Theme.pillRadius)
        Behavior on rayon { NumberAnimation { duration: Math.max(80, Theme.panelAnimDuration - 20); easing.type: Easing.OutCubic } }
        teinte: (root.panelOpen || root.notifToastActive || root.meteoExpanded) ? Theme.surfaceBg : Theme.barBg
        bordureCouleur: (root.isCalendarOpen || root.panelOpen || root.notifToastActive || root.meteoExpanded) ? Theme.accentMuted : Theme.accent
        bordureLargeur: Theme.barBorder ? 1 : 0
        actif: root.panelOpen || root.notifToastActive || root.meteoExpanded
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
        clip: true
        opacity: (root.expanded || root.panelOpen || root.notifToastActive || root.meteoExpanded) ? 0.0 : 1.0
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

        // 2. Repos : Capture (si active) + Workspaces (points/tiret) à gauche + Heure + lecteur audio + VPN à droite
        Row {
            id: compactContentRow
            anchors.centerIn: parent
            spacing: 10
            visible: !Theme.osdVisible

            // Point capture vidéo (rouge) / audio seule (orange) avant les ws
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowCapture, "compact") && root.captureState !== "none"
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.captureState === "video" ? "#ef4444" : "#f97316"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            WorkspacesApplet {
                id: compactWorkspaces
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "compact")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "compact") && Theme.ilotVisibleIn(Theme.ilotShowClock, "compact")
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Horloge principale sans glyphe (clic -> panneau étendu)
            Text {
                visible: Theme.ilotVisibleIn(Theme.ilotShowClock, "compact")
                text: Qt.formatTime(clock.date, "HH:mm")
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(Theme.textSm * Theme.barScale))
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
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "compact") && root.isMediaActive
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Si un média est actif : titre du morceau en cours
            Text {
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "compact") && root.isMediaActive
                text: {
                    let t = root.mediaTitle
                    if (!t) return "Audio"
                    return t.length > 16 ? (t.substring(0, 15) + "…") : t
                }
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                font.weight: Font.Medium
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            // Applets configurés en mode « Repos » ou « Les deux »
            AppletRow {
                id: compactApplets
                directModel: Theme.appletsPourIlot("compact", "all")
                visible: compactApplets.applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Icône Projets (columns-3) si échéance Planka < 24h
            Item {
                visible: Theme.ilotProjetsActif && Theme.ilotVisibleIn(Theme.ilotShowPlanka, "compact") && root.plankaEcheanceProche
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    glyph: "columns-3"
                    size: Theme.iconSm
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(4)
                }
            }

            // Point VPN à droite (bleu = connecté, blanc = déconnecté, jaune = erreur)
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowVpn, "compact")
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.vpnState === "connected"
                    ? "#00a3d5"
                    : (root.vpnState === "error" ? "#eab308" : "#ffffff")
                Behavior on color { ColorAnimation { duration: 150 } }
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
        clip: true
        opacity: (root.expanded && !root.panelOpen && !root.notifToastActive && !root.meteoExpanded && root.width >= root.expandedWidth - 16) ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
            id: fullContentRow
            anchors.centerIn: parent
            spacing: 10

            // Côté Gauche : Point capture (si actif) + Workspaces (points/tiret maintenus) + Applets gauche
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowCapture, "expanded") && root.captureState !== "none"
                width: 6
                height: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: root.captureState === "video" ? "#ef4444" : "#f97316"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            WorkspacesApplet {
                id: expandedWorkspaces
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "expanded")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            AppletRow {
                id: leftApplets
                directModel: Theme.appletsPourIlot("expanded", "left")
                visible: applets.length > 0 && implicitWidth > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Centre : Horloge + Date (clic -> panneau étendu)
            Item {
                visible: Theme.ilotVisibleIn(Theme.ilotShowClock, "expanded")
                width: clockDateRow.implicitWidth
                height: clockDateRow.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

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

            // Séparateur + titre média en mode étendu (si configuré dans Indicateurs de la pilule)
            Rectangle {
                id: expandedMediaSep
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "expanded") && root.isMediaActive
                width: 1
                height: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.15
            }

            Text {
                id: expandedMediaTitle
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "expanded") && root.isMediaActive
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    let t = root.mediaTitle
                    if (!t) return "Audio"
                    return t.length > 20 ? (t.substring(0, 19) + "…") : t
                }
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                font.weight: Font.Medium
                color: Theme.accent
            }

            // Côté Droit : Applets droite
            AppletRow {
                id: rightApplets
                directModel: Theme.appletsPourIlot("expanded", "right")
                visible: applets.length > 0 && implicitWidth > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Bouton d'accès rapide au panneau de configuration
            Rectangle {
                visible: Theme.showConfigButton
                width: 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
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

            // Icône Projets (columns-3) maintenue au survol si échéance Planka < 24h
            Item {
                visible: Theme.ilotProjetsActif && Theme.ilotVisibleIn(Theme.ilotShowPlanka, "expanded") && root.plankaEcheanceProche
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    glyph: "columns-3"
                    size: Theme.iconSm
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(4)
                }
            }

            // Point VPN à droite en mode étendu
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowVpn, "expanded")
                width: 6
                height: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: root.vpnState === "connected"
                    ? "#00a3d5"
                    : (root.vpnState === "error" ? "#eab308" : "#ffffff")
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CAPSULE NOTIFICATION « DROP FROM ISLAND »
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: toastContainer
        anchors.fill: parent
        clip: true
        opacity: root.notifToastActive ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // Clic sur le fond de la capsule : ouvre l'onglet Alertes & Tâches du panneau
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Theme.notifOps && Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                root.ouvrirPanneau(1)
            }
        }

        Column {
            id: toastContentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 5

            // En-tête : icône cloche + application + heure + sourdine + fermeture
            RowLayout {
                width: parent.width
                spacing: 6

                Icon {
                    glyph: "bell"
                    size: 11
                    color: Theme.accent
                    opacityLevel: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: Theme.notifToast ? String(Theme.notifToast.appName || "Système") : ""
                    color: Theme.accent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: Theme.notifToast ? String(Theme.notifToast.time || "") : ""
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                }

                // Mettre cette application en sourdine (toasts)
                Item {
                    width: 18
                    height: 18
                    Icon {
                        anchors.centerIn: parent
                        glyph: "bell-off"
                        size: 12
                        color: islandQuietMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: islandQuietMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.notifOps && Theme.notifOps.quietToast) Theme.notifOps.quietToast()
                        }
                    }
                }

                // Fermer la capsule sans ouvrir le panneau
                Item {
                    width: 18
                    height: 18
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 12
                        color: islandDismissMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: islandDismissMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.notifOps && Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                        }
                    }
                }
            }

            // Titre (cliquable pour ouvrir l'application / action par défaut)
            Item {
                width: parent.width
                height: islandToastTitle.implicitHeight

                Text {
                    id: islandToastTitle
                    width: parent.width
                    text: Theme.notifToast ? String(Theme.notifToast.summary || "") : ""
                    color: (islandToastTitleMa.containsMouse && islandToastTitleMa.enabled)
                        ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: islandToastTitleMa
                    anchors.fill: parent
                    enabled: Boolean(Theme.notifToast && Theme.notifOps && Theme.notifOps.hasTarget && Theme.notifOps.hasTarget(Theme.notifToast))
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (Theme.notifToast && Theme.notifOps && Theme.notifOps.open) {
                            Theme.notifOps.open(Theme.notifToast, false)
                        }
                    }
                }
            }

            // Corps du message
            Text {
                visible: Boolean(Theme.notifToast && Theme.notifToast.body && Theme.notifToast.body !== "")
                width: parent.width
                text: Theme.notifToast ? String(Theme.notifToast.body || "") : ""
                color: Qt.alpha(Theme.fg, 0.85)
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Boutons d'actions D-Bus de la notification
            Flow {
                width: parent.width
                visible: Boolean(Theme.notifToast && Theme.notifOps && Theme.notifOps.actions && Theme.notifOps.actions(Theme.notifToast).length > 0)
                spacing: Theme.space1

                Repeater {
                    model: (Theme.notifToast && Theme.notifOps && Theme.notifOps.actions)
                        ? Theme.notifOps.actions(Theme.notifToast) : []

                    Rectangle {
                        required property var modelData
                        width: islandActionLbl.implicitWidth + Theme.space3 * 2
                        height: 22
                        radius: Theme.globalRadius
                        color: islandActionMa.containsMouse
                            ? Qt.alpha(Theme.accent, 0.22)
                            : Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: islandActionMa.containsMouse ? Theme.accent : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            id: islandActionLbl
                            anchors.centerIn: parent
                            text: modelData.text || modelData.identifier
                            color: islandActionMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.9)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: islandActionMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.notifToast && Theme.notifOps && Theme.notifOps.invoke) {
                                    Theme.notifOps.invoke(Theme.notifToast, modelData.identifier)
                                    if (Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // EXTENSION MÉTÉO INLINE (MÊMES INFOS QUE LE WIDGET DE BUREAU)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: meteoContainer
        anchors.fill: parent
        clip: true
        focus: root.meteoExpanded
        Keys.onEscapePressed: Theme.activePopup = ""
        opacity: root.meteoExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        readonly property var meteo: Theme.meteoData
        readonly property bool ok: Theme.meteoLoaded && meteo && meteo.ok === true
        readonly property var previsions: (meteo && meteo.previsions) ? meteo.previsions.slice(1, 6) : []

        function meteoNombre(v, suffixe) {
            return (v === undefined || v === null) ? "—" : Math.round(Number(v)) + (suffixe || "")
        }

        function meteoJourCourt(iso) {
            const d = new Date(String(iso || "") + "T12:00:00")
            if (isNaN(d.getTime())) return String(iso || "")
            return d.toLocaleDateString(Qt.locale("fr_FR"), "ddd")
        }

        readonly property string meteoGlyphe: {
            const i = String((meteo && meteo.icon) || "").toLowerCase()
            if (i === "sun" || i === "clear") return "sun"
            if (i === "moon" || i === "night") return "weather-night"
            if (i === "cloud" || i === "overcast") return "cloud"
            if (i === "fog" || i === "rain" || i === "drizzle" || i === "snow" || i === "storm")
                return "weather-cloud"
            return (meteo && meteo.day === false) ? "weather-night" : "cloud"
        }

        Column {
            id: meteoContentCol
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Relevé du jour + actions (rafraîchir / fermer)
            RowLayout {
                width: Math.max(376, meteoForecastRow.implicitWidth)
                spacing: 12

                Icon {
                    glyph: meteoContainer.meteoGlyphe
                    size: 32
                    color: Theme.accent
                    opacityLevel: meteoContainer.ok ? 1.0 : 0.45
                }

                Text {
                    text: meteoContainer.ok ? Math.round(meteoContainer.meteo.temp) + "°" : "—"
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: 28
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        width: parent.width
                        text: meteoContainer.ok
                            ? String(meteoContainer.meteo.label || "")
                            : (Theme.meteoStatut !== "" ? Theme.meteoStatut : "Chargement…")
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: meteoContainer.ok ? String(meteoContainer.meteo.city || "") : ""
                        color: Qt.alpha(Theme.fg, 0.65)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "refresh"
                        size: 13
                        color: meteoRefreshMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: meteoRefreshMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.rafraichirMeteo(true)
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 13
                        color: meteoCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: meteoCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.activePopup = ""
                    }
                }
            }

            // Détails du jour (identiques au widget de bureau)
            Text {
                visible: meteoContainer.ok
                text: meteoContainer.ok
                    ? ("min " + meteoContainer.meteoNombre(meteoContainer.meteo.tmin, "°")
                       + " · max " + meteoContainer.meteoNombre(meteoContainer.meteo.tmax, "°")
                       + " · ressenti " + meteoContainer.meteoNombre(meteoContainer.meteo.feels, "°")
                       + " · " + meteoContainer.meteoNombre(meteoContainer.meteo.humidite, " %")
                       + " · vent " + meteoContainer.meteoNombre(meteoContainer.meteo.vent, " km/h")
                       + (Number(meteoContainer.meteo.pluie_mm) > 0
                          ? " · pluie " + meteoContainer.meteoNombre(meteoContainer.meteo.pluie_mm, " mm") : "")
                       + ((meteoContainer.meteo.stale === true || meteoContainer.meteo.cached === true)
                          ? " · dernière valeur connue" : ""))
                    : ""
                color: Qt.alpha(Theme.fg, 0.72)
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
            }

            // Prévisions des 5 jours suivants (identiques au widget de bureau)
            Row {
                id: meteoForecastRow
                visible: meteoContainer.ok && meteoContainer.previsions.length > 0
                spacing: 10

                Repeater {
                    model: meteoContainer.previsions

                    delegate: Rectangle {
                        required property var modelData
                        width: 68
                        height: forecastCol.implicitHeight + 10
                        radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                        color: Qt.alpha(Theme.surfaceVariant, 0.35)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.08)

                        Column {
                            id: forecastCol
                            anchors.centerIn: parent
                            width: parent.width - 8
                            spacing: 1

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: meteoContainer.meteoJourCourt(modelData.date)
                                color: Qt.alpha(Theme.fg, 0.75)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.capitalization: Font.Capitalize
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: meteoContainer.meteoNombre(modelData.tmin, "°") + " / " + meteoContainer.meteoNombre(modelData.tmax, "°")
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.bold: true
                                font.features: { "tnum": 1 }
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: modelData.pluie !== null && modelData.pluie !== undefined
                                text: meteoContainer.meteoNombre(modelData.pluie, " %")
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
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