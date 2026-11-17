import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 1 DE L'ÎLOT : CONTRÔLES RAPIDES (icône rectangles/grille)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var activePlayer: null
    property var validPlayers: []

    readonly property var currentPlayer: activePlayer ? activePlayer : ((validPlayers && validPlayers.length > 0) ? validPlayers[0] : null)
    readonly property bool isPlaying: currentPlayer ? (currentPlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string trackTitle: currentPlayer ? (currentPlayer.trackTitle || "Aucun titre") : "Aucun média"
    readonly property string trackArtist: currentPlayer ? (currentPlayer.trackArtist || "") : ""
    readonly property string artUrl: currentPlayer ? (currentPlayer.trackArtUrl || "") : ""

    property bool miniLecteurRetracte: false

    // ── État local synchronisé avec les services système ──────────────
    readonly property var sysInfo: Theme.systemInfo || ({})
    readonly property var wifiInfo: sysInfo.wifi || ({})
    readonly property var batInfo: sysInfo.battery || ({})
    readonly property bool isLaptop: Boolean(sysInfo.has_battery || (batInfo && batInfo.present))

    property bool wifiEnabled: Boolean(wifiInfo && (wifiInfo.enabled !== false))
    property string wifiSsid: (wifiInfo && wifiInfo.ssid) ? String(wifiInfo.ssid) : ""
    property bool wifiConnected: Boolean(wifiInfo && wifiInfo.connected)

    property bool btPowered: false
    property string btDevice: ""

    property bool nuitActive: false
    property int nuitTemp: 4200

    property bool batLimit80: Boolean(batInfo && batInfo.limit_80)
    property int batPlafond: Number((batInfo && batInfo.limit_pct) || 80)

    readonly property bool vizActif: {
        let _rev = Theme.barAppletsRev
        let a = Theme.barAppletsActifs ? Theme.barAppletsActifs["visualiseur"] : null
        return a ? Boolean(a.enabled !== false) : false
    }

    Process { id: vizCmdProc }

    property int volumePct: {
        let v = (sysInfo.volume && (sysInfo.volume.level !== undefined ? sysInfo.volume.level : sysInfo.volume.percent) !== undefined)
            ? Number(sysInfo.volume.level !== undefined ? sysInfo.volume.level : sysInfo.volume.percent) : 50
        return Math.max(0, Math.min(100, Math.round(v)))
    }
    property bool volumeMuted: Boolean(sysInfo.volume && sysInfo.volume.muted)

    property int brightPct: {
        let b = (sysInfo.brightness !== undefined) ? Number(sysInfo.brightness) : 80
        return Math.max(5, Math.min(100, Math.round(b)))
    }

    property string powerProfile: "balanced"
    property bool hasPowerProfiles: false

    property bool audioDrawerOpen: false
    property var audioSinks: []
    property string defaultSinkName: ""

    property var scratchpadWindows: []

    function labelProfil(p) {
        if (p === "performance") return "Performance"
        if (p === "power-saver") return "Économie"
        return "Équilibré"
    }

    function nextProfil(p) {
        if (p === "power-saver") return "balanced"
        if (p === "balanced") return "performance"
        return "power-saver"
    }

    function shortSinkLabel(name) {
        const s = String(name || "")
        if (s.indexOf("bluez") !== -1) return "Bluetooth"
        if (s.indexOf("hdmi") !== -1 || s.indexOf("HDMI") !== -1) return "HDMI / DisplayPort"
        if (s.indexOf("usb") !== -1 || s.indexOf("USB") !== -1) return "Audio USB"
        if (s.indexOf("analog") !== -1 || s.indexOf("pci") !== -1) return "Haut-parleurs / Jack"
        return s.length > 26 ? s.substring(0, 25) + "…" : s
    }

    function rafraichirEtats() {
        if (!btProc.running) {
            btProc.command = ["python3", Quickshell.shellPath("core/bluetooth_service.py"), "etat"]
            btProc.running = true
        }
        if (!nuitProc.running) {
            nuitProc.command = ["python3", Quickshell.shellPath("core/nuit_service.py"), "etat"]
            nuitProc.running = true
        }
        if (!wifiCheckProc.running) {
            wifiCheckProc.running = true
        }
        if (!powerProfileReadProc.running) {
            powerProfileReadProc.running = true
        }
        if (!scratchpadProc.running) {
            scratchpadProc.running = true
        }
        if (root.audioDrawerOpen && !audioSinksProc.running) {
            audioSinksProc.running = true
        }
    }

    Timer {
        id: initDelayTimer
        interval: Theme.panelAnimDuration + 30
        repeat: false
        onTriggered: root.rafraichirEtats()
    }

    Connections {
        target: Theme
        function onIslandPanelOpenChanged() {
            if (Theme.islandPanelOpen && Theme.islandPanelTab === 0) {
                initDelayTimer.restart()
            }
        }
        function onSystemInfoChanged() {
            if (root.batInfo) {
                root.batLimit80 = Boolean(root.batInfo.limit_80)
                root.batPlafond = Number(root.batInfo.limit_pct || 80)
            }
        }
    }

    Component.onCompleted: {
        if (Theme.islandPanelOpen) initDelayTimer.restart()
    }

    Process {
        id: wifiCheckProc
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = text.trim().toLowerCase()
                if (s === "enabled" || s === "disabled") {
                    root.wifiEnabled = (s === "enabled")
                }
            }
        }
    }

    Process {
        id: wifiToggleProc
        onExited: wifiCheckProc.running = true
    }

    Process {
        id: btProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    root.btPowered = Boolean(d.allume || d.powered)
                    let dev = ""
                    if (d.connectes && d.connectes.length > 0) {
                        dev = String(d.connectes[0].nom || d.connectes[0].name || "")
                    }
                    root.btDevice = dev
                } catch (e) {}
            }
        }
    }

    Process {
        id: nuitProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    root.nuitActive = Boolean(d.allume)
                    if (d.temperature) root.nuitTemp = Number(d.temperature)
                } catch (e) {}
            }
        }
    }

    Process {
        id: dndBridge
    }

    Process {
        id: actionProc
        property string sortie: ""
        stdout: StdioCollector {
            onStreamFinished: actionProc.sortie = text.trim()
        }
        onExited: code => {
            let motif = ""
            try {
                const d = JSON.parse(actionProc.sortie)
                if (d && d.error) motif = String(d.error)
            } catch (e) {}
            if (code !== 0 && motif !== "") {
                Quickshell.execDetached(["notify-send", "-a", "AetherShell", "-u", "normal", "Réglage non appliqué", motif])
            }
            actionProc.sortie = ""
            Theme.rafraichirSystemInfo()
        }
    }

    Process {
        id: volProc
    }

    Process {
        id: brightProc
    }

    Process {
        id: powerProfileReadProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p === "performance" || p === "balanced" || p === "power-saver") {
                    root.hasPowerProfiles = true
                    root.powerProfile = p
                }
            }
        }
    }

    Process {
        id: powerProfileSetProc
        onExited: if (!powerProfileReadProc.running) powerProfileReadProc.running = true
    }

    Process {
        id: audioSinksProc
        command: ["sh", "-c", "pactl get-default-sink 2>/dev/null; echo '---'; pactl list short sinks 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---")
                root.defaultSinkName = (parts[0] || "").trim()
                const lines = (parts[1] || "").trim().split("\n")
                const list = []
                for (let i = 0; i < lines.length; i++) {
                    const cols = lines[i].trim().split(/\s+/)
                    if (cols.length >= 2 && cols[1]) {
                        list.push({ name: cols[1], label: root.shortSinkLabel(cols[1]) })
                    }
                }
                root.audioSinks = list
            }
        }
    }

    Process {
        id: audioSwitchProc
        onExited: if (!audioSinksProc.running) audioSinksProc.running = true
    }

    Process {
        id: scratchpadProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const all = JSON.parse(text)
                    const res = []
                    if (Array.isArray(all)) {
                        for (let i = 0; i < all.length; i++) {
                            const c = all[i]
                            if (c && c.workspace && String(c.workspace.name || "") === "special:scratchpad") {
                                res.push({
                                    address: String(c.address || ""),
                                    klass: String(c["class"] || c.initialClass || "App"),
                                    title: String(c.title || c["class"] || "Fenêtre")
                                })
                            }
                        }
                    }
                    root.scratchpadWindows = res
                } catch (e) {
                    root.scratchpadWindows = []
                }
            }
        }
    }

    Process {
        id: scratchpadActionProc
        onExited: if (!scratchpadProc.running) scratchpadProc.running = true
    }

    // Composant tuile réutilisable (tuiles rapides)
    component QuickTile: Rectangle {
        id: tile
        property string glyphName: "cog"
        property string title: ""
        property string subtitle: ""
        property bool active: false
        property bool hasChevron: false
        signal toggled()
        signal chevronClicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 42
        radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
        color: active
            ? Qt.alpha(Theme.accent, tileMa.containsMouse ? 0.28 : 0.20)
            : Qt.alpha(Theme.surfaceVariant, tileMa.containsMouse ? 0.48 : 0.34)
        border.width: 1
        border.color: active ? Qt.alpha(Theme.accent, 0.55) : Qt.alpha(Theme.fg, 0.08)
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 8
                color: tile.active ? Theme.accent : Qt.alpha(Theme.fg, 0.08)

                Icon {
                    anchors.centerIn: parent
                    glyph: tile.glyphName
                    size: Theme.iconMd
                    color: tile.active ? Theme.bg : Theme.fg
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: tile.title
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.DemiBold
                    color: Theme.fg
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.subtitle
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: tile.active ? Theme.accent : Qt.alpha(Theme.fg, 0.65)
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: tile.hasChevron
                Layout.preferredWidth: 22
                Layout.preferredHeight: 28
                radius: 6
                color: chevMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                z: 2

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    font.family: Theme.fontUi
                    font.pixelSize: 16
                    color: Qt.alpha(Theme.fg, 0.75)
                }

                MouseArea {
                    id: chevMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.chevronClicked()
                }
            }
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            anchors.rightMargin: tile.hasChevron ? 30 : 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.toggled()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // ── Mini lecteur musique à gauche des contrôles rapides ───────────
        Rectangle {
            id: miniLecteurCard
            Layout.preferredWidth: root.miniLecteurRetracte ? 38 : 186
            Layout.fillHeight: true
            clip: true
            radius: Math.max(12, Math.round(Theme.pillRadius * 0.7))
            color: Qt.alpha(Theme.surfaceVariant, 0.34)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            // Bouton flèche en haut à droite pour rétracter / étendre le mini lecteur
            Rectangle {
                id: miniLecteurToggleBtn
                z: 5
                width: 24
                height: 24
                radius: 12
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: root.miniLecteurRetracte ? 7 : 8
                color: miniToggleMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

                Behavior on anchors.rightMargin {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Icon {
                    anchors.centerIn: parent
                    glyph: "chevron-right"
                    size: 14
                    color: miniToggleMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.8)
                    rotation: root.miniLecteurRetracte ? 180 : 0
                    Behavior on rotation {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: miniToggleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.miniLecteurRetracte = !root.miniLecteurRetracte
                }
            }

            // Icône discrète au centre lorsque le mini lecteur est rétracté
            Icon {
                anchors.centerIn: parent
                glyph: "music"
                size: Theme.iconSm
                color: root.isPlaying ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                opacity: root.miniLecteurRetracte ? 0.9 : 0.0
                visible: opacity > 0.05
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                opacity: root.miniLecteurRetracte ? 0.0 : 1.0
                visible: opacity > 0.05
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Text {
                    Layout.fillWidth: true
                    text: "LECTURE"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.weight: Font.Bold
                    color: Theme.accent
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }

                VinylArt {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 104
                    artUrl: root.artUrl
                    playing: root.isPlaying
                    iconSize: 32

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.islandPanelTab = 2
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.trackTitle
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: root.currentPlayer ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.trackArtist !== ""
                        Layout.fillWidth: true
                        text: root.trackArtist
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Qt.alpha(Theme.fg, 0.7)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                // Boutons Précédent / Lecture-Pause / Suivant
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: prevMiniMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)
                        opacity: root.currentPlayer && root.currentPlayer.canGoPrevious ? 1.0 : 0.4

                        Icon {
                            anchors.centerIn: parent
                            glyph: "previous"
                            size: Theme.iconSm
                            color: Theme.fg
                        }

                        MouseArea {
                            id: prevMiniMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.currentPlayer !== null && Boolean(root.currentPlayer.canGoPrevious)
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (root.currentPlayer) root.currentPlayer.previous()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 19
                        color: playMiniMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.24)
                        opacity: root.currentPlayer ? 1.0 : 0.45

                        Icon {
                            anchors.centerIn: parent
                            glyph: root.isPlaying ? "pause" : "play"
                            size: Theme.iconMd
                            color: playMiniMa.containsMouse ? Theme.bg : Theme.accent
                        }

                        MouseArea {
                            id: playMiniMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.currentPlayer !== null
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (root.currentPlayer) root.currentPlayer.togglePlaying()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 16
                        color: nextMiniMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)
                        opacity: root.currentPlayer && root.currentPlayer.canGoNext ? 1.0 : 0.4

                        Icon {
                            anchors.centerIn: parent
                            glyph: "next"
                            size: Theme.iconSm
                            color: Theme.fg
                        }

                        MouseArea {
                            id: nextMiniMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.currentPlayer !== null && Boolean(root.currentPlayer.canGoNext)
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (root.currentPlayer) root.currentPlayer.next()
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Contrôles rapides à droite ────────────────────────────────────
        Flickable {
            id: controlsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: controlsCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: controlsCol
            width: controlsFlick.width
            spacing: 8

        // En-tête onglet
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "CONTRÔLES RAPIDES"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }
            Text {
                text: "Actions instantanées & niveaux système."
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.6)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Sélecteur rapide de contexte de travail (Normal / Focus / Réunion / Détente)
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: Theme.workContexts || []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isActive: Theme.activeContext === modelData.id
                    Layout.fillWidth: true
                    height: 28
                    radius: Math.max(8, Math.round(Theme.globalRadius * 0.5))
                    color: isActive
                        ? Qt.alpha(Theme.accent, 0.22)
                        : (ctxMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.72) : Qt.alpha(Theme.surfaceVariant, 0.4))
                    border.width: 1
                    border.color: isActive ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: modelData.icon || "widgets"
                            size: 12
                            color: isActive ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.bold: isActive
                            color: isActive ? Theme.accent : Theme.fg
                        }
                    }

                    MouseArea {
                        id: ctxMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.applyContext(modelData.id)
                    }
                }
            }
        }

        // Grille 2x4 des tuiles rapides
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 5

            QuickTile {
                glyphName: root.wifiConnected ? "wifi-full" : "wifi"
                title: "Wi-Fi"
                subtitle: !root.wifiEnabled
                    ? "Désactivé"
                    : (root.wifiConnected && root.wifiSsid !== "" ? ("Actif · " + root.wifiSsid) : "Activé · Hors ligne")
                active: root.wifiEnabled
                hasChevron: true
                onToggled: {
                    let target = root.wifiEnabled ? "off" : "on"
                    root.wifiEnabled = !root.wifiEnabled
                    wifiToggleProc.command = ["nmcli", "radio", "wifi", target]
                    wifiToggleProc.running = true
                }
                onChevronClicked: Theme.islandPanelTab = 2
            }

            QuickTile {
                glyphName: "bluetooth"
                title: "Bluetooth"
                subtitle: !root.btPowered
                    ? "Désactivé"
                    : (root.btDevice !== "" ? root.btDevice : "Actif · Prêt")
                active: root.btPowered
                onToggled: {
                    btProc.command = ["python3", Quickshell.shellPath("core/bluetooth_service.py"), "basculer"]
                    btProc.running = true
                }
            }

            QuickTile {
                glyphName: "weather-night"
                title: "Mode nuit"
                subtitle: root.nuitActive ? ("Actif · " + root.nuitTemp + " K") : ("Inactif · " + root.nuitTemp + " K")
                active: root.nuitActive
                onToggled: {
                    nuitProc.command = ["python3", Quickshell.shellPath("core/nuit_service.py"), "basculer"]
                    nuitProc.running = true
                }
            }

            QuickTile {
                glyphName: Theme.doNotDisturb ? "bell-off" : "bell"
                title: "Ne pas déranger"
                subtitle: Theme.doNotDisturb
                    ? "Silencieux"
                    : ("Désactivé (" + Theme.notifCount + " alerte" + (Theme.notifCount > 1 ? "s" : "") + ")")
                active: Theme.doNotDisturb
                hasChevron: true
                onToggled: {
                    Theme.doNotDisturb = !Theme.doNotDisturb
                    dndBridge.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                                         "style", "do_not_disturb", Theme.doNotDisturb ? "true" : "false"]
                    dndBridge.running = true
                }
                onChevronClicked: Theme.islandPanelTab = 1
            }

            QuickTile {
                glyphName: root.isLaptop ? "battery" : "cog"
                title: root.isLaptop ? "Charge max 80 %" : "Configuration"
                subtitle: root.isLaptop
                    ? (root.batLimit80 ? ("Activée (plafond " + root.batPlafond + " %)") : "Désactivée (charge 100 %)")
                    : "Ouvrir les réglages"
                active: root.isLaptop ? root.batLimit80 : false
                onToggled: {
                    if (root.isLaptop) {
                        let nextLim = root.batLimit80 ? 100 : 80
                        root.batLimit80 = !root.batLimit80
                        root.batPlafond = nextLim
                        actionProc.command = ["python3", Quickshell.shellPath("core/system_service.py"), "limit", String(nextLim)]
                        actionProc.running = true
                    } else {
                        Theme.islandPanelOpen = false
                        Theme.configPanelVisible = true
                    }
                }
            }

            // Tuile 6 : Session & Énergie (mini-boutons directs)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
                color: Qt.alpha(Theme.surfaceVariant, 0.34)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.08)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "Session"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.DemiBold
                        color: Theme.fg
                    }

                    Repeater {
                        model: [
                            { glyph: "lock", tip: "Verrouiller", cmd: ["loginctl", "lock-session"], danger: false },
                            { glyph: "weather-night", tip: "Veille", cmd: ["systemctl", "suspend"], danger: false },
                            { glyph: "restart", tip: "Redémarrer", cmd: ["systemctl", "reboot"], danger: true },
                            { glyph: "power", tip: "Éteindre", cmd: ["systemctl", "poweroff"], danger: true }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 8
                            color: sessMa.containsMouse
                                ? Qt.alpha(modelData.danger ? Theme.error : Theme.accent, 0.25)
                                : Qt.alpha(Theme.fg, 0.08)

                            Icon {
                                anchors.centerIn: parent
                                glyph: parent.modelData.glyph
                                size: Theme.iconSm
                                color: sessMa.containsMouse
                                    ? (parent.modelData.danger ? Theme.error : Theme.accent)
                                    : Theme.fg
                            }

                            MouseArea {
                                id: sessMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.islandPanelOpen = false
                                    actionProc.command = parent.modelData.cmd
                                    actionProc.running = true
                                }
                            }
                        }
                    }
                }
            }

            // Tuile 7 : Anti-veille (Caffeine)
            QuickTile {
                glyphName: "coffee"
                title: "Caffeine"
                subtitle: Theme.caffeineActif ? "Veille bloquée" : "Inactif"
                active: Theme.caffeineActif
                onToggled: Theme.caffeineActif = !Theme.caffeineActif
            }

            // Tuile 8 : Profil de performance
            QuickTile {
                glyphName: "speedometer"
                title: "Performance"
                subtitle: root.hasPowerProfiles ? root.labelProfil(root.powerProfile) : "Indisponible"
                active: root.hasPowerProfiles && root.powerProfile === "performance"
                onToggled: {
                    if (!root.hasPowerProfiles || powerProfileSetProc.running) return
                    const nxt = root.nextProfil(root.powerProfile)
                    root.powerProfile = nxt
                    powerProfileSetProc.command = ["powerprofilesctl", "set", nxt]
                    powerProfileSetProc.running = true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Curseur Volume
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 8
                color: muteMa.containsMouse ? Qt.alpha(Theme.accent, 0.2) : "transparent"

                Icon {
                    anchors.centerIn: parent
                    glyph: root.volumeMuted || root.volumePct <= 0 ? "volume-off" : (root.volumePct < 50 ? "volume-medium" : "volume-high")
                    size: Theme.iconMd
                    color: root.volumeMuted ? Theme.error : Theme.accent
                }

                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.volumeMuted = !root.volumeMuted
                        volProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
                        volProc.running = true
                    }
                }
            }

            Text {
                Layout.preferredWidth: 68
                text: "Volume"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                color: Theme.fg
            }

            Item {
                id: volSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.fg, 0.14)

                    Rectangle {
                        width: parent.width * (root.volumePct / 100)
                        height: parent.height
                        radius: 3
                        color: root.volumeMuted ? Qt.alpha(Theme.fg, 0.35) : Theme.accent
                    }
                }

                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, (parent.width - width) * (root.volumePct / 100)))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.fg
                    border.width: 2
                    border.color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function applyVol(mx) {
                        let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)))
                        root.volumePct = pct
                        volProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (pct / 100).toFixed(2)]
                        volProc.running = true
                    }
                    onPressed: mouse => applyVol(mouse.x)
                    onPositionChanged: mouse => { if (pressed) applyVol(mouse.x) }
                }
            }

            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: root.volumePct + " %"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                id: vizCycleBtn
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                radius: 6
                readonly property string vizMode: !root.vizActif ? "off" : (Theme.vizEffectiveStyle === "onde" ? "onde" : "barres")
                color: root.vizActif
                    ? Qt.alpha(Theme.accent, vizMa.containsMouse ? 0.30 : 0.20)
                    : (vizMa.containsMouse ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.fg, 0.08))

                // Icône 1 : Barres (ou barres barrées quand éteint)
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    visible: vizCycleBtn.vizMode !== "onde"

                    Rectangle {
                        Layout.preferredWidth: 2.5
                        Layout.preferredHeight: 6
                        Layout.alignment: Qt.AlignBottom
                        radius: 1
                        color: root.vizActif ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
                    }
                    Rectangle {
                        Layout.preferredWidth: 2.5
                        Layout.preferredHeight: 12
                        Layout.alignment: Qt.AlignBottom
                        radius: 1
                        color: root.vizActif ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
                    }
                    Rectangle {
                        Layout.preferredWidth: 2.5
                        Layout.preferredHeight: 8
                        Layout.alignment: Qt.AlignBottom
                        radius: 1
                        color: root.vizActif ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
                    }
                }

                // Barre diagonale discrète quand le visualiseur est éteint
                Rectangle {
                    visible: vizCycleBtn.vizMode === "off"
                    anchors.centerIn: parent
                    width: 15
                    height: 1.5
                    radius: 1
                    rotation: -35
                    color: Qt.alpha(Theme.fg, 0.65)
                }

                // Icône 2 : Onde sinusoïdale quand le mode « onde » est actif
                Canvas {
                    id: vizWaveIcon
                    visible: vizCycleBtn.vizMode === "onde"
                    anchors.centerIn: parent
                    width: 16
                    height: 12
                    property color strokeCol: Theme.accent
                    onStrokeColChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = strokeCol
                        ctx.lineWidth = 1.8
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        for (let x = 0; x <= width; x += 1) {
                            const t = (x / width) * Math.PI * 2
                            const y = height / 2 - Math.sin(t) * (height * 0.36)
                            if (x === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                    }
                }

                MouseArea {
                    id: vizMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (vizCmdProc.running) return
                        const styleKey = Theme.barStyle === "island" ? "viz_style_island" : "viz_style_classic"
                        if (vizCycleBtn.vizMode === "off") {
                            vizCmdProc.command = [
                                "sh", "-c",
                                "python3 \"$1\" style \"$2\" barres && python3 \"$3\" activer visualiseur",
                                "sh",
                                Quickshell.shellPath("core/config_manager.py"),
                                styleKey,
                                Quickshell.shellPath("core/bar_applets.py")
                            ]
                        } else if (vizCycleBtn.vizMode === "barres") {
                            vizCmdProc.command = [
                                "python3", Quickshell.shellPath("core/config_manager.py"),
                                "style", styleKey, "onde"
                            ]
                        } else {
                            vizCmdProc.command = [
                                "python3", Quickshell.shellPath("core/bar_applets.py"),
                                "desactiver", "visualiseur"
                            ]
                        }
                        vizCmdProc.running = true
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                radius: 6
                color: root.audioDrawerOpen
                    ? Qt.alpha(Theme.accent, 0.28)
                    : (audioTabMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08))

                Text {
                    anchors.centerIn: parent
                    text: "⇄"
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: root.audioDrawerOpen ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: audioTabMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.audioDrawerOpen = !root.audioDrawerOpen
                        if (root.audioDrawerOpen && !audioSinksProc.running) {
                            audioSinksProc.running = true
                        }
                    }
                }
            }
        }

        // Sous-tiroir sélecteur de sortie audio instantané
        Rectangle {
            visible: root.audioDrawerOpen
            Layout.fillWidth: true
            Layout.preferredHeight: sinkFlow.implicitHeight + 12
            radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
            color: Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.3)

            Flow {
                id: sinkFlow
                anchors.fill: parent
                anchors.margins: 6
                spacing: 6

                Repeater {
                    model: root.audioSinks
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: modelData.name === root.defaultSinkName
                        width: sinkLbl.implicitWidth + 16
                        height: 24
                        radius: 6
                        color: current ? Theme.accent : (sinkMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06))

                        Text {
                            id: sinkLbl
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.bold: current
                            color: current ? Theme.bg : Theme.fg
                        }

                        MouseArea {
                            id: sinkMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (audioSwitchProc.running) return
                                root.defaultSinkName = modelData.name
                                audioSwitchProc.command = ["pactl", "set-default-sink", modelData.name]
                                audioSwitchProc.running = true
                            }
                        }
                    }
                }
            }
        }

        // Curseur Luminosité
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Icon {
                    anchors.centerIn: parent
                    glyph: "brightness"
                    size: Theme.iconMd
                    color: Theme.accent
                }
            }

            Text {
                Layout.preferredWidth: 68
                text: "Luminosité"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                color: Theme.fg
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.alpha(Theme.fg, 0.14)

                    Rectangle {
                        width: parent.width * (root.brightPct / 100)
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }
                }

                Rectangle {
                    x: Math.max(0, Math.min(parent.width - width, (parent.width - width) * (root.brightPct / 100)))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.fg
                    border.width: 2
                    border.color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function applyBright(mx) {
                        let pct = Math.max(5, Math.min(100, Math.round((mx / width) * 100)))
                        root.brightPct = pct
                        brightProc.command = ["python3", Quickshell.shellPath("core/system_service.py"), "brightness", String(pct)]
                        brightProc.running = true
                    }
                    onPressed: mouse => applyBright(mouse.x)
                    onPositionChanged: mouse => { if (pressed) applyBright(mouse.x) }
                }
            }

            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: root.brightPct + " %"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.fg
            }

            Item { Layout.preferredWidth: 26 }
        }

        // Barre Scratchpads visuels (`special:scratchpad`)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
            color: Qt.alpha(Theme.surfaceVariant, 0.30)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "SCRATCHPAD"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.weight: Font.Bold
                    color: Theme.accent
                }

                Text {
                    visible: root.scratchpadWindows.length === 0
                    Layout.fillWidth: true
                    text: "Aucune fenêtre (SUPER + ,)"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    color: Qt.alpha(Theme.fg, 0.5)
                    elide: Text.ElideRight
                }

                Row {
                    visible: root.scratchpadWindows.length > 0
                    Layout.fillWidth: true
                    spacing: 5
                    clip: true

                    Repeater {
                        model: root.scratchpadWindows.slice(0, 4)
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.min(115, spLbl.implicitWidth + 14)
                            height: 20
                            radius: 6
                            color: spMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                            Text {
                                id: spLbl
                                anchors.centerIn: parent
                                width: parent.width - 10
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.klass
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                color: spMa.containsMouse ? Theme.accent : Theme.fg
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: spMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.islandPanelOpen = false
                                    scratchpadActionProc.command = [
                                        "sh", "-c",
                                        "hyprctl dispatch togglespecialworkspace scratchpad && hyprctl dispatch focuswindow address:" + modelData.address
                                    ]
                                    scratchpadActionProc.running = true
                                }
                            }
                        }
                    }
                }
            }
        }
        }
        }
    }
}
