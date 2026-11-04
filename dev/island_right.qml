import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Notifications

// ════════════════════════════════════════════════════════════════════════════
// RIGHT ISLAND: HARDWARE CONTROLS, SYSTRAY & POWER MENU (island_right.qml)
// ════════════════════════════════════════════════════════════════════════════
// Architecture Overview:
//   • Section 1: Popup Geometry & System State Properties
//   • Section 2: Helper Functions & Formatters (signal, battery, volume icons)
//   • Section 3: IPC & Hardware Background Processes (system info, actions, WiFi, notifications)
//   • Section 4: Arch-Update Check Service (pacman + AUR update counter & timer)
//   • Section 5: Main Right Island Bar UI:
//       - 5.1 Systray & Notifications (Arch-Update badge, Tray icons, Notif bell)
//       - 5.2 WiFi / Network Button (status, SSID, signal strength)
//       - 5.3 System Controls Box (Battery status, Volume, Brightness)
//       - 5.4 Tablet Mode Virtual Keyboard Button (on-screen keyboard toggle)
//       - 5.5 Power Menu Button (scaled dynamically to bar height)
//   • Section 6: Hyprland Focus Grab (dismiss popups on outside click)
//   • Section 7: Popups:
//       - 7.1 Interactive WiFi Network Selection Panel
//       - 7.2 System Controls Panel (ASUS Battery 80% limit, Volume slider, Brightness slider)
//       - 7.3 Power & Session Management Menu (Shutdown, Reboot, Lock, Suspend, Logout)
//       - 7.4 Notification Center Popup (notification list & history)
//       - 7.5 Ephemeral Toast Popup (incoming desktop notifications)
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandRight

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: POPUP GEOMETRY & SYSTEM STATE PROPERTIES
    // ────────────────────────────────────────────────────────────────────────
    // Keep popups fully inside the bar window (= screen width) with an 8px margin.
    // Vertical offset so that every popup opens 6px under the BAR (island bottom).
    function popupY(item) {
        return islandRight.height + 6 - islandRight.mapFromItem(item, 0, 0).y
    }

    function clampPopupX(item, relX, popupW) {
        const win = islandRight.QsWindow.window
        if (!win) return relX
        const ix = win.contentItem.mapFromItem(item, 0, 0).x
        const absX = Math.max(8, Math.min(win.width - popupW - 8, ix + relX))
        return absX - ix
    }
    implicitWidth: mainRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Host & hardware properties
    property string hostName: "Station"
    property bool hasBattery: false
    property bool hasBacklight: false

    property int batPercent: 0
    property string batStatus: "Unknown"
    property bool batLimit80: false

    property int volPercent: 0
    property bool volMuted: false

    property int briPercent: 100

    property bool wifiConnected: false
    property string wifiSsid: ""
    property int wifiSignal: 0
    property string netType: "wifi"

    property bool tabletMode: false

    // WiFi Panel State
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string expandedSsid: ""
    property string connectingStatus: ""
    property bool connectingBusy: false

    // Notifications State
    property var notificationsList: []
    property var latestToast: null

    // Arch-Update State
    property bool hasArchUpdate: false
    property int pendingUpdatesCount: 0

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HELPER FUNCTIONS & FORMATTERS
    // ────────────────────────────────────────────────────────────────────────
    // Renvoient un NOM d'icône (Icon.qml), plus un glyphe brut : c'est ce qui
    // garantit une seule famille, une seule taille et un seul centrage.
    function signalIconFor(sig, connected) {
        if (!connected && sig <= 0) return "wifi-none"
        if (sig >= 75) return "wifi-full"
        if (sig >= 50) return "wifi-high"
        if (sig >= 25) return "wifi-medium"
        return "wifi-low"
    }

    function batteryIconFor(pct, status) {
        if (status === "Charging" || status === "Full") return "battery-charging"
        if (pct >= 90) return "battery-full"
        if (pct >= 70) return "battery-70"
        if (pct >= 50) return "battery-50"
        if (pct >= 25) return "battery-25"
        if (pct >= 10) return "battery-10"
        return "battery-outline"
    }

    function volumeIconFor(pct, muted) {
        if (muted || pct <= 0) return "mute"
        if (pct < 35) return "volume-low"
        if (pct < 70) return "volume-medium"
        return "volume-high"
    }

    function applySystemInfo(data) {
        if (!data) return
        if (typeof data.hostname === "string" && data.hostname.length > 0) {
            hostName = data.hostname.charAt(0).toUpperCase() + data.hostname.slice(1)
        }
        if (typeof data.has_battery === "boolean") {
            hasBattery = data.has_battery
        }
        if (typeof data.has_backlight === "boolean") {
            hasBacklight = data.has_backlight
        }
        if (data.battery) {
            batPercent = Number(data.battery.level || 0)
            batStatus = String(data.battery.status || "Unknown")
            batLimit80 = Boolean(data.battery.limit_80)
        }
        if (data.volume) {
            volPercent = Number(data.volume.level || 0)
            volMuted = Boolean(data.volume.muted)
        }
        if (typeof data.brightness === "number") {
            briPercent = data.brightness
        }
        if (data.wifi) {
            wifiConnected = Boolean(data.wifi.connected)
            wifiSsid = String(data.wifi.ssid || "")
            wifiSignal = Number(data.wifi.signal || 0)
            netType = String(data.wifi.type || "wifi")
        }
        if (typeof data.tablet_mode === "boolean") {
            tabletMode = data.tablet_mode
        }
    }

    function refreshSystemInfo() {
        if (!sysInfoProc.running) sysInfoProc.running = true
    }

    // Only one scan / connection at a time: extra requests are queued instead of
    // killing the running process (a killed process would deliver truncated JSON).
    property bool wifiScanQueued: false
    property bool wifiScanQueuedRescan: false

    function startWifiScan(rescan) {
        const args = ["python3", Quickshell.shellPath("core/system_service.py"), "wifi"]
        if (!rescan) args.push("--no-rescan")
        wifiScanProc.command = args
        wifiScanProc.running = true
    }

    function scanWifi(rescan) {
        wifiScanning = true
        if (wifiScanProc.running) {
            wifiScanQueued = true
            wifiScanQueuedRescan = wifiScanQueuedRescan || Boolean(rescan)
            return
        }
        startWifiScan(rescan)
    }

    function connectToWifi(ssid, password) {
        if (wifiConnectProc.running) return
        connectingBusy = true
        connectingStatus = "Connexion à " + ssid + "..."
        wifiConnectProc.command = [
            "python3",
            Quickshell.shellPath("core/system_service.py"),
            "wifi_connect",
            ssid,
            password || ""
        ]
        wifiConnectProc.running = true
    }

    // Actions (volume, brightness...) are serialized: while one runs, newer ones are queued.
    // A queued action replaces an older queued one of the same kind so that dragging a slider
    // only applies the latest value instead of dropping it.
    property var sysActionQueue: []

    function startSysAction(args) {
        sysActionProc.command = ["python3", Quickshell.shellPath("core/system_service.py")].concat(args)
        sysActionProc.running = true
    }

    function runSysAction(args) {
        if (!sysActionProc.running) {
            startSysAction(args)
            return
        }
        // "mute" is a toggle action: do not deduplicate / replace previous mute toggles.
        // For continuous values (volume, brightness), replace older pending requests of the same type.
        const isToggle = (args[0] === "mute")
        const q = isToggle ? sysActionQueue.slice() : sysActionQueue.filter(a => a[0] !== args[0])
        q.push(args)
        sysActionQueue = q
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: IPC & HARDWARE BACKGROUND PROCESSES
    // ────────────────────────────────────────────────────────────────────────
    NotificationServer {
        id: notifServer
        keepOnReload: true
        onNotification: notification => {
            notification.tracked = true
            const entry = {
                id: notification.id,
                appName: notification.appName || "Système",
                summary: notification.summary || "Notification",
                body: notification.body || "",
                time: Qt.formatDateTime(new Date(), "hh:mm"),
                raw: notification
            }
            const next = [entry].concat(islandRight.notificationsList).slice(0, 30)
            islandRight.notificationsList = next
            // Application écartée des toasts : la notification va directement au
            // centre, sans apparition spontanée.
            if (Theme.quietNotifApps.indexOf(entry.appName) < 0) {
                islandRight.latestToast = entry
                toastTimer.restart()
            }
        }
    }

    Timer {
        id: toastTimer
        interval: 4500
        repeat: false
        onTriggered: islandRight.latestToast = null
    }

    // Écarte une application des toasts, ou la rétablit. La liste vit dans
    // core/style_vars.json : Theme.qml la recharge via son FileView.
    function setToastQuiet(appName, quiet) {
        if (!appName) return
        quietNotifProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                                  "notif_quiet", quiet ? "true" : "false", appName]
        quietNotifProc.running = true
    }

    function quietToastSource() {
        if (!latestToast) return
        setToastQuiet(latestToast.appName, true)
        latestToast = null
    }

    property Process quietNotifProc: Process {}

    Process {
        id: sysInfoProc
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    islandRight.applySystemInfo(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: sysActionProc
        onExited: {
            if (islandRight.sysActionQueue.length > 0) {
                const q = islandRight.sysActionQueue.slice()
                const next = q.shift()
                islandRight.sysActionQueue = q
                islandRight.startSysAction(next)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // Stale result: a newer action is queued, don't overwrite the optimistic UI value
                if (islandRight.sysActionQueue.length > 0) return
                try {
                    const parsed = JSON.parse(text.trim())
                    if (typeof parsed.limit_80 === "boolean" && !parsed.battery) {
                        islandRight.batLimit80 = parsed.limit_80
                        islandRight.refreshSystemInfo()
                    } else {
                        // Full info or partial ({volume} / {brightness}) payload
                        islandRight.applySystemInfo(parsed)
                    }
                } catch (e) {
                    islandRight.refreshSystemInfo()
                }
            }
        }
    }

    Process {
        id: wifiScanProc
        onExited: {
            if (islandRight.wifiScanQueued) {
                const rescan = islandRight.wifiScanQueuedRescan
                islandRight.wifiScanQueued = false
                islandRight.wifiScanQueuedRescan = false
                islandRight.startWifiScan(rescan)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (islandRight.wifiScanQueued) return // stale: a newer scan is queued
                islandRight.wifiScanning = false
                try {
                    islandRight.wifiNetworks = JSON.parse(text.trim())
                } catch (e) {
                    islandRight.wifiNetworks = []
                }
            }
        }
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                islandRight.connectingBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.success) {
                        islandRight.connectingStatus = "✓ Connecté à " + res.ssid
                        islandRight.expandedSsid = ""
                        islandRight.refreshSystemInfo()
                        islandRight.scanWifi(false)
                    } else {
                        islandRight.connectingStatus = "✕ Échec : " + (res.message || "Mot de passe incorrect")
                    }
                } catch (e) {
                    islandRight.connectingStatus = "✕ Erreur de connexion"
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: islandRight.refreshSystemInfo()
    }

    // Les touches média changent le volume via osd.sh : l'OSD est le seul signal
    // disponible, on s'en sert pour rafraîchir l'icône tout de suite au lieu
    // d'attendre le prochain sondage de 5 s. On ne teste pas `osdVisible` :
    // showOsd() écrit kind puis valeur avant de passer visible, donc au moment
    // du signal la surface est encore masquée.
    Connections {
        target: Theme
        function onOsdValueChanged() {
            if (Theme.osdKind === "volume" || Theme.osdKind === "mute") islandRight.refreshSystemInfo()
        }
        function onOsdKindChanged() {
            if (Theme.osdKind === "volume" || Theme.osdKind === "mute") islandRight.refreshSystemInfo()
        }
    }

    Connections {
        target: Theme
        function onActivePopupChanged() {
            if (Theme.activePopup === "wifi") {
                islandRight.connectingStatus = ""
                islandRight.scanWifi(true)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: ARCH-UPDATE CHECK SERVICE
    // ────────────────────────────────────────────────────────────────────────
    Process {
        id: checkArchUpdateInstalledProc
        command: ["sh", "-c", "command -v arch-update >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                islandRight.hasArchUpdate = (text.trim() === "1")
                if (islandRight.hasArchUpdate && !checkUpdatesProc.running) {
                    checkUpdatesProc.running = true
                }
            }
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["sh", "-c", "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^\\s*$' | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const count = parseInt(text.trim(), 10)
                    islandRight.pendingUpdatesCount = isNaN(count) ? 0 : count
                } catch (e) {
                    islandRight.pendingUpdatesCount = 0
                }
            }
        }
    }

    Timer {
        id: checkUpdatesTimer
        interval: 1800000 // Refresh every 30 minutes
        running: islandRight.hasArchUpdate
        repeat: true
        onTriggered: {
            if (!checkUpdatesProc.running) checkUpdatesProc.running = true
        }
    }

    Component.onCompleted: {
        checkArchUpdateInstalledProc.running = true
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 5: MAIN RIGHT ISLAND BAR UI
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: islandBg
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }


        Row {
            id: mainRow
            anchors.centerIn: parent
            spacing: 12

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.1: SYSTRAY & NOTIFICATIONS
            // ────────────────────────────────────────────────────────────────
            Row {
                id: systraySection
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Notification Center Trigger Button
                Rectangle {
                    id: notifBtn
                    width: notifRow.implicitWidth + 10
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: Theme.activePopup === "notifications"
                        ? Theme.accent
                        : (notifMa.containsMouse ? Theme.surfaceVariant : "transparent")

                    Row {
                        id: notifRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: islandRight.notificationsList.length > 0 ? "bell" : "bell-off"
                            size: Theme.iconSm
                            color: Theme.activePopup === "notifications"
                                ? Theme.bg
                                : (islandRight.notificationsList.length > 0 ? Theme.warn : Theme.fg)
                        }

                        Text {
                            visible: islandRight.notificationsList.length > 0
                            text: String(islandRight.notificationsList.length)
                            color: Theme.activePopup === "notifications" ? Theme.bg : Theme.warn
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: notifMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            islandRight.latestToast = null
                            Theme.togglePopup("notifications")
                        }
                    }
                }

                // Arch-Update Tray Button
                Rectangle {
                    id: archUpdateBtn
                    visible: islandRight.hasArchUpdate
                    width: archUpdateRow.implicitWidth + 10
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: archUpdateMa.containsMouse ? Theme.surfaceVariant : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: archUpdateRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "arch"
                            size: Theme.iconSm
                            color: islandRight.pendingUpdatesCount > 0 ? Theme.warn : Theme.fg
                            opacityLevel: islandRight.pendingUpdatesCount > 0 ? 1 : 0.6
                        }

                        Text {
                            visible: islandRight.pendingUpdatesCount > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(islandRight.pendingUpdatesCount)
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: archUpdateMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (!checkUpdatesProc.running) checkUpdatesProc.running = true
                            } else {
                                Quickshell.execDetached(["kitty", "arch-update"])
                            }
                        }
                    }
                }

                // Menu contextuel des items du systray, rendu maison (TrayMenu.qml).
    TrayMenu {
        id: trayMenu
    }

    // Background Application Icons (Steam, ProtonVPN, etc.) via StatusNotifierItem
                Repeater {
                    model: SystemTray.items

                    Rectangle {
                        id: trayDelegate
                        required property var modelData

                        // Icône : celle de l'item, sauf correspondance déclarée dans
                        // core/tray_icons.json (par Id). Un item qui ne publie aucune
                        // image — IconPixmap vide, IconName vide — n'a pas de case du
                        // tout : c'est ce qui dessinait un pixmap illisible.
                        readonly property string itemIcon: Theme.trayIconFor(trayDelegate.modelData.id)
                        readonly property string iconSource: itemIcon !== ""
                            ? itemIcon
                            : (trayDelegate.modelData.icon ? String(trayDelegate.modelData.icon) : "")

                        width: 24
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: trayMa.containsMouse ? Theme.surfaceVariant : "transparent"
                        visible: iconSource !== ""

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: trayDelegate.iconSource
                            sourceSize: Qt.size(16, 16)
                            smooth: true
                        }

                        MouseArea {
                            id: trayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                const win = islandRight.QsWindow.window
                                const pt = win ? win.contentItem.mapFromItem(trayDelegate, 0, trayDelegate.height) : Qt.point(0, 0)
                                if (mouse.button === Qt.RightButton || trayDelegate.modelData.onlyMenu) {
                                    if (trayDelegate.modelData.hasMenu && win) {
                                        // Pas `display()` : la fenêtre interne de Quickshell
                                        // rend un menu blanc sans nos tokens (TrayMenu.qml).
                                        trayMenu.open(trayDelegate.modelData, pt.x, pt.y)
                                    }
                                } else if (mouse.button === Qt.LeftButton) {
                                    trayDelegate.modelData.activate()
                                } else if (mouse.button === Qt.MiddleButton) {
                                    trayDelegate.modelData.secondaryActivate()
                                }
                            }
                            onWheel: wheel => {
                                trayDelegate.modelData.scroll(wheel.angleDelta.y, false)
                            }
                        }
                    }
                }
            }

            // Visual Separator 1 (Between Systray and Network)
            Rectangle {
                width: 1
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceVariant
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.2: WIFI / NETWORK BUTTON
            // ────────────────────────────────────────────────────────────────
            Rectangle {
                id: networkBtn
                width: netRow.implicitWidth + 12
                height: 28
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.activePopup === "wifi"
                    ? Theme.accent
                    : (netMa.containsMouse ? Theme.surfaceVariant : "transparent")

                Row {
                    id: netRow
                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: islandRight.netType === "ethernet"
                            ? "ethernet"
                            : islandRight.signalIconFor(islandRight.wifiSignal, islandRight.wifiConnected)
                        size: Theme.iconSm
                        color: Theme.activePopup === "wifi"
                            ? Theme.bg
                            : (islandRight.wifiConnected ? Theme.accent : Theme.error)
                    }

                    Text {
                        text: islandRight.wifiConnected
                            ? (islandRight.wifiSsid !== "" ? islandRight.wifiSsid : "WiFi")
                            : "Déconnecté"
                        color: Theme.activePopup === "wifi" ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textSm
                        font.bold: islandRight.wifiConnected
                    }
                }

                MouseArea {
                    id: netMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.togglePopup("wifi")
                }
            }

            // Visual Separator 2 (Visually separating Systray/Network from System Controls)
            Rectangle {
                width: 2
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accentMuted
                opacity: 0.6
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.3: SYSTEM CONTROLS & HARDWARE MONITORS
            // ────────────────────────────────────────────────────────────────
            // Battery status & 80% limit, volume slider, brightness slider
            Rectangle {
                id: systemControlsBox
                width: sysControlsRow.implicitWidth + 14
                height: 28
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.activePopup === "system"
                    ? Qt.alpha(Theme.accent, 0.25)
                    : (sysBoxMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.color: Theme.activePopup === "system" ? Theme.accent : "transparent"
                border.width: 1

                MouseArea {
                    id: sysBoxMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.togglePopup("system")
                }

                Row {
                    id: sysControlsRow
                    anchors.centerIn: parent
                    spacing: 12

                    // Battery indicator (+ 80% shield badge when limiter is active, hidden on Desktop Tower)
                    Row {
                        visible: islandRight.hasBattery
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: islandRight.batteryIconFor(islandRight.batPercent, islandRight.batStatus)
                            size: Theme.iconSm
                            color: (islandRight.batPercent <= 15 && islandRight.batStatus !== "Charging")
                                ? Theme.error
                                : (islandRight.batStatus === "Charging" ? Theme.success : Theme.accent)
                        }

                        Text {
                            text: islandRight.batPercent + "%"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: islandRight.batPercent <= 15
                        }

                        Rectangle {
                            visible: islandRight.batLimit80
                            width: 24
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 2
                            color: Theme.success
                            Text {
                                anchors.centerIn: parent
                                text: "80%"
                                color: Theme.bg
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }
                        }
                    }

                    // Entrée unique vers le panneau système (volume, luminosité, batterie).
                    // Les pourcentages ont quitté la barre : volume et luminosité passent par
                    // l'OSD (bas-centre) et par les curseurs du panneau. L'icône garde l'état
                    // muet, et la molette y règle le volume comme le font les touches média.
                    Item {
                        width: 20
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.centerIn: parent
                            glyph: islandRight.volumeIconFor(islandRight.volPercent, islandRight.volMuted)
                            size: Theme.iconSm
                            color: islandRight.volMuted ? Theme.error : Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    islandRight.volMuted = !islandRight.volMuted
                                    islandRight.runSysAction(["mute"])
                                    Theme.showOsd("volume", islandRight.volMuted ? 0 : islandRight.volPercent)
                                } else {
                                    Theme.togglePopup("system")
                                }
                            }
                            onWheel: wheel => {
                                const step = wheel.angleDelta.y > 0 ? 5 : -5
                                const nextVol = Math.max(0, Math.min(150, islandRight.volPercent + step))
                                islandRight.volPercent = nextVol
                                islandRight.volMuted = false
                                islandRight.runSysAction(["volume", String(nextVol)])
                                Theme.showOsd("volume", nextVol)
                            }
                        }
                    }
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.4: TABLET MODE VIRTUAL KEYBOARD BUTTON
            // ────────────────────────────────────────────────────────────────
            // Visible only in Lenovo Yoga Tablet Mode
            Rectangle {
                id: keyboardBtn
                visible: islandRight.tabletMode
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Icon {
                    anchors.centerIn: parent
                    glyph: "keyboard"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "wvkbd-mobintl || cosmic-osk || wvkbd"])
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.5: POWER MENU BUTTON (Scaled to bar height)
            // ────────────────────────────────────────────────────────────────
            Rectangle {
                id: powerBtn
                anchors.verticalCenter: parent.verticalCenter
                property real heightRatio: 0.70
                readonly property real btnSize: Math.max(18, Math.round(Theme.barHeight * heightRatio))
                width: btnSize
                height: btnSize
                radius: Math.min(Theme.globalRadius, Math.round(btnSize / 2))
                color: Theme.activePopup === "power"
                    ? Theme.error
                    : (powerMa.containsMouse ? Qt.alpha(Theme.error, 0.16) : "transparent")
                border.color: Theme.activePopup === "power" ? Theme.error : "transparent"
                border.width: 1

                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Icon {
                    anchors.centerIn: parent
                    glyph: "power"
                    size: Theme.iconSm
                    color: Theme.activePopup === "power"
                        ? Theme.bg
                        : (powerMa.containsMouse ? Theme.error : Theme.fg)
                    opacityLevel: Theme.activePopup === "power" ? 1 : 0.85
                }

                MouseArea {
                    id: powerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.togglePopup("power")
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 6: HYPRLAND OUTSIDE CLICK / FOCUS GRAB
    // ────────────────────────────────────────────────────────────────────────
    // Dismisses open right-island popups when clicking anywhere on the desktop
    HyprlandFocusGrab {
        active: Theme.activePopup === "wifi"
            || Theme.activePopup === "system"
            || Theme.activePopup === "power"
            || Theme.activePopup === "notifications"
        windows: [
            wifiPanelPopup,
            systemPanelPopup,
            powerMenuPopup,
            notificationsPopup,
            islandRight.QsWindow.window
        ]
        onCleared: {
            if (Theme.activePopup !== "calendar") {
                Theme.activePopup = ""
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 7: POPUP WINDOWS
    // ────────────────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.1: INTERACTIVE WIFI MANAGEMENT POPUP
    // ────────────────────────────────────────────────────────────────────────
    PopupWindow {
        id: wifiPanelPopup
        anchor.item: networkBtn
        anchor.rect.x: (networkBtn.width - implicitWidth) / 2
        anchor.rect.y: islandRight.popupY(networkBtn)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(networkBtn, (networkBtn.width - implicitWidth) / 2, implicitWidth), islandRight.popupY(networkBtn), anchor.rect.width, anchor.rect.height)
        implicitWidth: 320
        implicitHeight: 390
        color: "transparent"
        visible: Theme.activePopup === "wifi"
        grabFocus: visible && islandRight.expandedSsid !== ""

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header + Rescan button
                Item {
                    width: parent.width
                    height: 26

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "wifi"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Réseaux disponibles"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: 68
                        height: 24
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: rescanMa.containsMouse ? Theme.accent : Theme.surfaceVariant

                        Text {
                            anchors.centerIn: parent
                            text: islandRight.wifiScanning ? "Scan..." : "↻ Scan"
                            color: rescanMa.containsMouse ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            id: rescanMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRight.scanWifi(true)
                        }
                    }
                }

                // Connection feedback banner
                Rectangle {
                    visible: islandRight.connectingStatus !== ""
                    width: parent.width
                    height: 26
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: islandRight.connectingStatus.indexOf("✓") === 0
                        ? Theme.success
                        : (islandRight.connectingStatus.indexOf("✕") === 0 ? Theme.error : Theme.info)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: islandRight.connectingStatus
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Scrollable list of WiFi networks with inline password input under clicked SSID
                Flickable {
                    id: wifiFlick
                    width: parent.width
                    height: islandRight.connectingStatus !== "" ? 285 : 315
                    contentWidth: width
                    contentHeight: networkListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: networkListCol
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: !islandRight.wifiScanning && islandRight.wifiNetworks.length === 0
                            text: "Aucun réseau WiFi détecté."
                            color: Qt.alpha(Theme.fg, 0.7)
                            font.pixelSize: Theme.textSm
                            font.italic: true
                        }

                        Repeater {
                            model: islandRight.wifiNetworks

                            Column {
                                id: netItemCol
                                required property var modelData
                                width: networkListCol.width
                                spacing: 0

                                readonly property bool isExpanded: islandRight.expandedSsid === modelData.ssid

                                // Network Row (Signal icon + SSID + Connected/Lock status)
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: Theme.globalRadius
                                    color: netItemCol.modelData.in_use
                                        ? Qt.alpha(Theme.accent, 0.22)
                                        : (netRowMa.containsMouse || netItemCol.isExpanded ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.45))
                                    border.color: netItemCol.modelData.in_use
                                        ? Theme.accent
                                        : (netItemCol.isExpanded ? Theme.accentMuted : "transparent")
                                    border.width: (netItemCol.modelData.in_use || netItemCol.isExpanded) ? 1 : 0

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // Dynamic signal strength icon at start of line
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: islandRight.signalIconFor(netItemCol.modelData.signal, true)
                                            size: Theme.iconSm
                                            color: netItemCol.modelData.signal >= 60
                                                ? Theme.success
                                                : (netItemCol.modelData.signal >= 30 ? Theme.warn : Theme.error)
                                        }

                                        // Network SSID
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: netItemCol.modelData.ssid
                                            color: Theme.fg
                                            font.pixelSize: Theme.textSm
                                            font.bold: netItemCol.modelData.in_use
                                            elide: Text.ElideRight
                                            width: 175
                                        }
                                    }

                                    // Right badge: Signal % + Connected / Lock icon
                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: netItemCol.modelData.in_use
                                                ? "Connecté"
                                                : (netItemCol.modelData.signal + "%")
                                            color: netItemCol.modelData.in_use ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.pixelSize: Theme.textXs
                                            font.bold: netItemCol.modelData.in_use
                                        }

                                        Icon {
                                            visible: Boolean(netItemCol.modelData.secured)
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "lock"
                                            size: 10
                                            color: Theme.fg
                                        }
                                    }

                                    MouseArea {
                                        id: netRowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (netItemCol.modelData.in_use) return
                                            if (!netItemCol.modelData.secured) {
                                                // Open network -> connect immediately
                                                islandRight.connectToWifi(netItemCol.modelData.ssid, "")
                                            } else {
                                                // Toggle inline password field right below this network
                                                islandRight.expandedSsid = netItemCol.isExpanded ? "" : netItemCol.modelData.ssid
                                            }
                                        }
                                    }
                                }

                                // Inline Password Box directly underneath the clicked network
                                Rectangle {
                                    id: inlinePassBox
                                    visible: netItemCol.isExpanded
                                    width: parent.width
                                    height: visible ? 44 : 0
                                    color: Theme.surfaceVariant
                                    radius: Theme.globalRadius
                                    border.color: Theme.accentMuted
                                    border.width: 1

                                    onVisibleChanged: {
                                        if (visible) {
                                            passInput.text = ""
                                            passInput.forceActiveFocus()
                                        }
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 6

                                        Rectangle {
                                            width: parent.width - 82
                                            height: parent.height
                                            color: Theme.bg
                                            radius: Theme.globalRadius
                                            border.color: passInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                            border.width: 1

                                            Text {
                                                visible: passInput.text.length === 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                text: "Mot de passe WiFi (ou vide si connu)..."
                                                color: Qt.alpha(Theme.fg, 0.45)
                                                font.pixelSize: Theme.textXs
                                            }

                                            TextInput {
                                                id: passInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                verticalAlignment: TextInput.AlignVCenter
                                                echoMode: TextInput.Password
                                                focus: netItemCol.isExpanded
                                                selectByMouse: true
                                                color: Theme.fg
                                                font.pixelSize: Theme.textSm
                                                clip: true
                                                onAccepted: islandRight.connectToWifi(netItemCol.modelData.ssid, passInput.text)
                                                Keys.onEscapePressed: islandRight.expandedSsid = ""
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                acceptedButtons: Qt.NoButton
                                            }
                                        }

                                        Rectangle {
                                            width: 74
                                            height: parent.height
                                            radius: Theme.globalRadius
                                            color: connectBtnMa.containsMouse ? Theme.accentMuted : Theme.accent

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Joindre"
                                                color: Theme.bg
                                                font.pixelSize: Theme.textXs
                                                font.bold: true
                                            }

                                            MouseArea {
                                                id: connectBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: islandRight.connectToWifi(netItemCol.modelData.ssid, passInput.text)
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

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.2: SYSTEM HARDWARE & CONTROLS POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Controls ASUS Battery 80% charge threshold, audio volume slider, and backlight brightness slider
    PopupWindow {
        id: systemPanelPopup
        anchor.item: systemControlsBox
        anchor.rect.x: (systemControlsBox.width - implicitWidth) / 2
        anchor.rect.y: islandRight.popupY(systemControlsBox)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(systemControlsBox, (systemControlsBox.width - implicitWidth) / 2, implicitWidth), islandRight.popupY(systemControlsBox), anchor.rect.width, anchor.rect.height)
        implicitWidth: 310
        implicitHeight: sysCol.implicitHeight + 28
        color: "transparent"
        visible: Theme.activePopup === "system"

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: sysCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 14

                Row {
                    spacing: Theme.space2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "cog"
                        size: Theme.iconSm
                        color: Theme.accent
                        opacityLevel: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Contrôles système · " + islandRight.hostName
                        color: Theme.fg
                        font.pixelSize: Theme.textLg
                        font.bold: true
                    }
                }

                // 1. Volume Slider Control
                Column {
                    width: parent.width
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: islandRight.volumeIconFor(islandRight.volPercent, islandRight.volMuted)
                                size: Theme.iconSm
                                color: islandRight.volMuted ? Theme.error : Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Volume audio"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            text: islandRight.volMuted ? "Muet (Cliquer pour activer)" : (islandRight.volPercent + "%")
                            color: islandRight.volMuted ? Theme.error : Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandRight.runSysAction(["mute"])
                            }
                        }
                    }

                    Rectangle {
                        id: volTrack
                        width: parent.width
                        height: 12
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: Math.min(1, Math.max(0, islandRight.volPercent / 100)) * parent.width
                            height: parent.height
                            radius: Theme.globalRadius
                            color: islandRight.volMuted ? Theme.error : Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function applyPos(mx) {
                                const pct = Math.round(Math.max(0, Math.min(1, mx / volTrack.width)) * 100)
                                islandRight.volPercent = pct
                                islandRight.runSysAction(["volume", String(pct)])
                            }
                            onPressed: mouse => applyPos(mouse.x)
                            onPositionChanged: mouse => { if (pressed) applyPos(mouse.x) }
                        }
                    }
                }

                // 2. Brightness Slider Control (Laptop / Backlight only)
                Column {
                    visible: islandRight.hasBacklight
                    width: parent.width
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "brightness"
                                size: Theme.iconSm
                                color: Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Luminosité de l'écran"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            text: islandRight.briPercent + "%"
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    Rectangle {
                        id: briTrack
                        width: parent.width
                        height: 12
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: Math.min(1, Math.max(0.05, islandRight.briPercent / 100)) * parent.width
                            height: parent.height
                            radius: Theme.globalRadius
                            color: Theme.accentMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function applyPos(mx) {
                                const pct = Math.round(Math.max(0.05, Math.min(1, mx / briTrack.width)) * 100)
                                islandRight.briPercent = pct
                                islandRight.runSysAction(["brightness", String(pct)])
                            }
                            onPressed: mouse => applyPos(mouse.x)
                            onPositionChanged: mouse => { if (pressed) applyPos(mouse.x) }
                        }
                    }
                }

                // Divider
                Rectangle {
                    visible: islandRight.hasBattery
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                // 3. Battery Status & 80% Charge Limiter Card (Laptop only)
                Rectangle {
                    visible: islandRight.hasBattery
                    width: parent.width
                    height: 68
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: islandRight.batLimit80 ? Theme.success : "transparent"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 20

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.space1

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "battery"
                                    size: Theme.iconSm
                                    color: Theme.fg
                                    opacityLevel: 0.9
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Batterie : " + islandRight.batPercent + "% (" + islandRight.batStatus + ")"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Limiter la charge à 80% (Santé)"
                                color: Qt.alpha(Theme.fg, 0.9)
                                font.pixelSize: Theme.textXs
                            }

                            // 80% Limiter Toggle Button
                            Rectangle {
                                width: 64
                                height: 22
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.globalRadius
                                color: islandRight.batLimit80 ? Theme.success : Theme.bg
                                border.color: islandRight.batLimit80 ? Theme.success : Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: islandRight.batLimit80 ? "80% ON" : "100%"
                                    color: islandRight.batLimit80 ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const nextTarget = islandRight.batLimit80 ? 100 : 80
                                        islandRight.batLimit80 = !islandRight.batLimit80
                                        islandRight.runSysAction(["limit", String(nextTarget)])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.3: GENEROUS POWER MENU POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Anchored to the rightmost extremity: Shutdown, Reboot, Lock, Suspend, Logout
    PopupWindow {
        id: powerMenuPopup
        anchor.item: islandRight
        anchor.rect.x: islandRight.width - implicitWidth
        anchor.rect.y: islandRight.popupY(islandRight)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(islandRight, islandRight.width - implicitWidth, implicitWidth), islandRight.popupY(islandRight), anchor.rect.width, anchor.rect.height)
        implicitWidth: 280
        // Hauteur dérivée du contenu : une valeur fixe coupait la dernière ligne
        // (le bas n'avait plus que 0 px de marge au lieu de 14).
        implicitHeight: powerCard.implicitHeight
        color: "transparent"
        visible: Theme.activePopup === "power"

        Rectangle {
            id: powerCard
            anchors.fill: parent
            implicitHeight: powerColumn.implicitHeight + 28
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.error
            border.width: 1

            Column {
                id: powerColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                // Même en-tête que « Notifications » : glyphe du jeu d'icônes
                // puis libellé. Le caractère brut ⏻ (U+23FB) tombait en police de
                // repli, plus fin et collé au texte.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.space2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "power"
                        size: Theme.iconSm
                        color: Theme.error
                        opacityLevel: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Session & Alimentation"
                        color: Theme.error
                        font.pixelSize: Theme.textLg
                        font.bold: true
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                Repeater {
                    model: [
                        { icon: "lock", title: "Verrouiller la session", sub: "Protéger l'écran actif", cmd: "hyprlock || loginctl lock-session", danger: false },
                        { icon: "logout", title: "Fermer la session", sub: "Quitter Hyprland", cmd: "hyprctl dispatch 'hl.dsp.exit()' || hyprctl dispatch exit", danger: false },
                        { icon: "sleep", title: "Mise en veille", sub: "Suspendre en mémoire", cmd: "systemctl suspend", danger: false },
                        { icon: "restart", title: "Redémarrer", sub: "Relancer la machine " + islandRight.hostName, cmd: "systemctl reboot", danger: true },
                        { icon: "power", title: "Extinction", sub: "Arrêter complètement le système", cmd: "systemctl poweroff", danger: true }
                    ]

                    Rectangle {
                        id: pwrItem
                        required property var modelData
                        width: parent.width
                        height: 46
                        radius: Theme.globalRadius
                        color: pwrItemMa.containsMouse
                            ? (modelData.danger ? Qt.alpha(Theme.error, 0.25) : Theme.surfaceVariant)
                            : Qt.alpha(Theme.surfaceVariant, 0.45)
                        border.color: pwrItemMa.containsMouse
                            ? (modelData.danger ? Theme.error : Theme.accent)
                            : "transparent"
                        border.width: 1

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: pwrItem.modelData.icon
                                size: Theme.iconMd
                                color: pwrItem.modelData.danger ? Theme.error : Theme.fg
                                opacityLevel: 1
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: pwrItem.modelData.title
                                    color: pwrItem.modelData.danger ? Theme.error : Theme.fg
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }

                                Text {
                                    text: pwrItem.modelData.sub
                                    color: Qt.alpha(Theme.fg, 0.65)
                                    font.pixelSize: Theme.textXs
                                }
                            }
                        }

                        MouseArea {
                            id: pwrItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.activePopup = ""
                                Quickshell.execDetached(["sh", "-c", pwrItem.modelData.cmd])
                            }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.4: NOTIFICATION CENTER POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Chronological notification history with dismiss & clear-all controls
    PopupWindow {
        id: notificationsPopup
        anchor.item: notifBtn
        anchor.rect.x: (notifBtn.width - implicitWidth) / 2
        anchor.rect.y: islandRight.popupY(notifBtn)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(notifBtn, (notifBtn.width - implicitWidth) / 2, implicitWidth), islandRight.popupY(notifBtn), anchor.rect.width, anchor.rect.height)
        implicitWidth: 320
        implicitHeight: 340
        color: "transparent"
        visible: Theme.activePopup === "notifications"

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ────────────────────────────────────────────────────────────
                // En-tête : compteur discret, action neutre au repos
                // ────────────────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "bell"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: islandRight.notificationsList.length > 0
                            text: islandRight.notificationsList.length
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    // « Tout effacer » : discret au repos, rouge seulement au survol.
                    // Le rouge reste un signal, pas une décoration.
                    Item {
                        visible: islandRight.notificationsList.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: clearText.implicitWidth + 12
                        height: 20

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.globalRadius
                            color: clearMa.containsMouse ? Qt.alpha(Theme.error, 0.12) : "transparent"
                        }

                        Text {
                            id: clearText
                            anchors.centerIn: parent
                            text: "Tout effacer"
                            color: clearMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRight.notificationsList = []
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // Cartes empilées, la plus récente en tête
                // ────────────────────────────────────────────────────────────
                Flickable {
                    id: notifFlick
                    width: parent.width
                    // Le pied « sans apparition spontanée » rogne la liste d'autant.
                    height: 268 - (quietFooter.visible ? quietFooter.height + 6 : 0)
                    contentWidth: width
                    contentHeight: notifListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: notifListCol
                        width: parent.width
                        spacing: 8

                        // État vide
                        Item {
                            visible: islandRight.notificationsList.length === 0
                            width: parent.width
                            height: notifFlick.height

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.space2

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    glyph: "bell-off"
                                    size: Theme.iconLg
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    opacityLevel: 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Aucune notification"
                                    color: Qt.alpha(Theme.fg, 0.55)
                                    font.pixelSize: Theme.textSm
                                }
                            }
                        }

                        Repeater {
                            model: islandRight.notificationsList

                            Rectangle {
                                id: notifCard
                                required property var modelData
                                required property int index
                                width: notifListCol.width
                                height: notifCardCol.implicitHeight + 20
                                radius: Theme.globalRadius
                                color: cardMa.containsMouse
                                    ? Qt.lighter(Theme.surfaceVariant, 1.15)
                                    : Theme.surfaceVariant
                                clip: true

                                Behavior on color { ColorAnimation { duration: 120 } }

                                // Liseré d'application : 2 px, franc sur la carte la
                                // plus récente, effacé sur les anciennes.
                                Rectangle {
                                    width: 2
                                    height: parent.height
                                    color: Qt.alpha(Theme.accent, index === 0 ? 0.95 : 0.35)
                                }

                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }

                                Column {
                                    id: notifCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Item {
                                        width: parent.width
                                        height: 18

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.space1

                                            Text {
                                                text: modelData.appName
                                                width: Math.min(implicitWidth, notifCardCol.width - 78)
                                                color: Theme.accent
                                                font.pixelSize: Theme.textXs
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: "·"
                                                color: Qt.alpha(Theme.fg, 0.4)
                                                font.pixelSize: Theme.textXs
                                            }
                                            Text {
                                                text: modelData.time
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.pixelSize: Theme.textXs
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        Icon {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "close"
                                            size: 10
                                            color: closeMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)
                                            opacityLevel: 1

                                            MouseArea {
                                                id: closeMa
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const copy = islandRight.notificationsList.slice()
                                                    copy.splice(index, 1)
                                                    islandRight.notificationsList = copy
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.summary
                                        color: Theme.fg
                                        font.pixelSize: Theme.textSm
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        visible: modelData.body !== ""
                                        width: parent.width
                                        text: modelData.body
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.textXs
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────
                // Applications écartées des toasts : le choix se fait
                // depuis un toast (cloche barrée) et se défait ici.
                // ────────────────────────────────────────────────────
                Item {
                    id: quietFooter
                    width: parent.width
                    height: visible ? quietCol.implicitHeight + 12 : 0
                    visible: Theme.quietNotifApps.length > 0

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.08)
                    }

                    Column {
                        id: quietCol
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: parent.width
                        spacing: 6

                        Row {
                            spacing: Theme.space1

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "bell-off"
                                size: 10
                                color: Qt.alpha(Theme.fg, 0.45)
                                opacityLevel: 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications silencieuses"
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.text2xs
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: Theme.quietNotifApps

                                Rectangle {
                                    required property var modelData
                                    width: quietChipText.implicitWidth + 26
                                    height: 20
                                    radius: Theme.globalRadius
                                    color: Theme.surfaceVariant

                                    Text {
                                        id: quietChipText
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, 130)
                                        text: modelData
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.text2xs
                                        elide: Text.ElideRight
                                    }

                                    Icon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: "close"
                                        size: 9
                                        color: chipClose.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                                        opacityLevel: 1

                                        MouseArea {
                                            id: chipClose
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: islandRight.setToastQuiet(modelData, false)
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

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.5: EPHEMERAL NOTIFICATION TOAST POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Auto-dismissing transient toast on incoming notifications
    PopupWindow {
        id: toastPopup
        anchor.item: islandRight
        anchor.rect.x: islandRight.width - implicitWidth
        anchor.rect.y: islandRight.popupY(islandRight)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(islandRight, islandRight.width - implicitWidth, implicitWidth), islandRight.popupY(islandRight), anchor.rect.width, anchor.rect.height)
        implicitWidth: 300
        implicitHeight: toastCol.implicitHeight + 20
        color: "transparent"
        visible: islandRight.latestToast !== null && Theme.activePopup === ""
            && Theme.quietNotifApps.indexOf(islandRight.latestToast ? islandRight.latestToast.appName : "") < 0

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceVariantBg
            radius: Theme.globalRadius
            clip: true

            // Zone de clic sur tout le toast : déclarée avant le contenu pour que
            // le bouton « écarter » du contenu reste cliquable par-dessus.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Le clic ouvre le centre de notifications ; le toast s'efface ensuite
                // de lui-même (timer d'expiration).
                onClicked: {
                    islandRight.latestToast = null
                    Theme.activePopup = "notifications"
                }
            }

            Column {
                id: toastCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Item {
                    width: parent.width
                    height: 16

                    Icon {
                        id: toastBell
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "bell"
                        size: 10
                        color: Theme.accent
                        opacityLevel: 1
                    }

                    Text {
                        anchors.left: toastBell.right
                        anchors.leftMargin: Theme.space1
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 46)
                        text: islandRight.latestToast ? islandRight.latestToast.appName : ""
                        color: Theme.accent
                        font.pixelSize: Theme.textXs
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Écarte cette application des toasts : sa notification reste
                    // dans le centre, elle n'apparaît simplement plus ici.
                    Icon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "bell-off"
                        size: 12
                        color: toastQuietMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)
                        opacityLevel: 1

                        MouseArea {
                            id: toastQuietMa
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRight.quietToastSource()
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: islandRight.latestToast ? islandRight.latestToast.summary : ""
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    visible: Boolean(islandRight.latestToast && islandRight.latestToast.body !== "")
                    width: parent.width
                    text: islandRight.latestToast ? islandRight.latestToast.body : ""
                    color: Qt.alpha(Theme.fg, 0.85)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
