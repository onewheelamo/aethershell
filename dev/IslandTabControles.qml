import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 1 DE L'ÎLOT : CONTRÔLES RAPIDES (icône rectangles/grille)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    // ── État local synchronisé avec les services système ──────────────
    readonly property var sysInfo: Theme.systemInfo || ({})
    readonly property var wifiInfo: sysInfo.wifi || ({})
    readonly property var batInfo: sysInfo.battery || ({})
    readonly property bool isLaptop: Boolean(batInfo && batInfo.present)

    property bool wifiEnabled: Boolean(wifiInfo && (wifiInfo.enabled !== false))
    property string wifiSsid: (wifiInfo && wifiInfo.ssid) ? String(wifiInfo.ssid) : ""
    property bool wifiConnected: Boolean(wifiInfo && wifiInfo.connected)

    property bool btPowered: false
    property string btDevice: ""

    property bool nuitActive: false
    property int nuitTemp: 4200

    property bool batLimit80: Boolean(batInfo && batInfo.limit_80)
    property int batPlafond: Number((batInfo && batInfo.limit_pct) || 80)

    property int volumePct: {
        let v = (sysInfo.volume && sysInfo.volume.percent !== undefined) ? Number(sysInfo.volume.percent) : 50
        return Math.max(0, Math.min(100, Math.round(v)))
    }
    property bool volumeMuted: Boolean(sysInfo.volume && sysInfo.volume.muted)

    property int brightPct: {
        let b = (sysInfo.brightness !== undefined) ? Number(sysInfo.brightness) : 80
        return Math.max(5, Math.min(100, Math.round(b)))
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
    }

    Process {
        id: volProc
    }

    Process {
        id: brightProc
    }

    // Composant tuile réutilisable (6 tuiles rapides)
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
        Layout.preferredHeight: 54
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

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

        // Grille 2x3 des 6 tuiles
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 8

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
                onChevronClicked: Theme.islandPanelTab = 3
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
                onChevronClicked: Theme.islandPanelTab = 2
            }

            QuickTile {
                glyphName: root.isLaptop ? "battery" : "cog"
                title: root.isLaptop ? ("Limite " + root.batPlafond + " %") : "Configuration"
                subtitle: root.isLaptop
                    ? (root.batLimit80 ? "Santé batterie active" : "Charge complète (100 %)")
                    : "Ouvrir les réglages"
                active: root.isLaptop ? root.batLimit80 : false
                onToggled: {
                    if (root.isLaptop) {
                        let nextLim = root.batLimit80 ? 100 : 80
                        root.batLimit80 = !root.batLimit80
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
                Layout.preferredHeight: 54
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
                Layout.preferredWidth: 26
                Layout.preferredHeight: 24
                radius: 6
                color: audioTabMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)

                Text {
                    anchors.centerIn: parent
                    text: "⇄"
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Theme.fg
                }

                MouseArea {
                    id: audioTabMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandPanelTab = 1
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

        Item { Layout.fillHeight: true }
    }
}
