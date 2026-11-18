pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Services système partagés : Wi-Fi, scan QR Wi-Fi, Bluetooth et lancement isolé.
QtObject {
    id: root

    // ── État système partagé (core/system_service.py info) ──────────────────
    property var systemInfo: ({})
    property bool systemInfoPret: false

    property Process systemInfoProc: Process {
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d === "object") {
                        root.systemInfo = d
                        root.systemInfoPret = true
                    }
                } catch (e) {}
            }
        }
    }

    function rafraichirSystemInfo() {
        if (systemInfoProc.running) return
        systemInfoProc.running = true
    }

    property Timer systemInfoTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.rafraichirSystemInfo()
    }

    // ── Caffeine (inhibition mise en veille) ─────────────────────────────────
    property bool caffeineActif: false
    property Process caffeineProc: Process {
        command: ["systemd-inhibit", "--what=idle", "--who=AetherShell", "--why=Mode Caffeine", "sleep", "infinity"]
        running: root.caffeineActif
    }

    // ── Météo partagée (core/weather_service.py) ─────────────────────────────
    property var meteoData: ({})
    property string meteoStatut: ""
    property bool meteoLoaded: false
    property bool meteoActif: false

    property Process meteoProc: Process {
        command: ["python3", Quickshell.shellPath("core/weather_service.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.meteoLoaded = true
                try {
                    const d = JSON.parse(String(text).trim())
                    if (d && d.ok) {
                        root.meteoData = d
                        root.meteoStatut = ""
                    } else {
                        root.meteoData = ({})
                        root.meteoStatut = String((d && d.error) || "météo indisponible")
                    }
                } catch (e) {
                    root.meteoData = ({})
                    root.meteoStatut = "réponse météo illisible"
                }
            }
        }
    }

    function rafraichirMeteo(force) {
        meteoActif = true
        if (meteoProc.running) return
        const args = ["python3", Quickshell.shellPath("core/weather_service.py")]
        if (force) args.push("--force")
        meteoProc.command = args
        meteoProc.running = true
    }

    property Timer meteoTimer: Timer {
        interval: 600000
        repeat: true
        running: root.meteoActif
        onTriggered: root.rafraichirMeteo(false)
    }

    // ── Démon de métriques partagé (CPU / RAM / GPU / Réseau) ───────────────
    property var systemeData: ({})
    property bool systemeCharge: false
    property var reseauData: ({})
    property bool reseauCharge: false
    property bool metriquesActif: false

    property Process metriquesDaemonProc: Process {
        running: root.metriquesActif
        command: ["python3", Quickshell.shellPath("core/metriques_daemon.py"), "2"]
        stdout: SplitParser {
            onRead: line => {
                const s = String(line || "").trim()
                if (!s) return
                try {
                    const d = JSON.parse(s)
                    if (d && d.systeme) {
                        root.systemeData = d.systeme
                        root.systemeCharge = true
                    }
                    if (d && d.reseau) {
                        root.reseauData = d.reseau
                        root.reseauCharge = true
                    }
                } catch (e) {}
            }
        }
    }

    property Timer metriquesGardeTimer: Timer {
        interval: 10000
        repeat: true
        running: root.metriquesActif && !root.metriquesDaemonProc.running
        onTriggered: root.metriquesDaemonProc.running = true
    }

    // ── Wi-Fi ────────────────────────────────────────────────────────────────
    property var wifiNetworks: []
    property bool wifiScanning: false
    property bool wifiEnabled: Boolean(root.systemInfo && root.systemInfo.wifi && (root.systemInfo.wifi.enabled !== false))
    property bool qrWifiAvailable: false

    property Process wifiCheckProc: Process {
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim().toLowerCase()
                if (s === "enabled" || s === "disabled") root.wifiEnabled = (s === "enabled")
            }
        }
    }

    property Process wifiToggleProc: Process {
        onExited: {
            if (!wifiCheckProc.running) wifiCheckProc.running = true
            root.rafraichirSystemInfo()
            if (root.wifiEnabled) root.scanWifi()
        }
    }

    property Process qrStatusProc: Process {
        command: ["python3", Quickshell.shellPath("core/wifi_qr_scan.py"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim() || "{}")
                    root.qrWifiAvailable = Boolean(d.available)
                } catch (e) {
                    root.qrWifiAvailable = false
                }
            }
        }
    }

    property Process wifiScanProc: Process {
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                try {
                    const arr = JSON.parse(text.trim())
                    root.wifiNetworks = Array.isArray(arr) ? arr : []
                } catch (e) {
                    root.wifiNetworks = []
                }
            }
        }
        onExited: root.wifiScanning = false
    }

    property Timer wifiScanTimer: Timer {
        interval: 600000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.scanWifi()
    }

    function checkWifiRadio() {
        if (!wifiCheckProc.running) wifiCheckProc.running = true
    }

    function toggleWifiRadio() {
        if (wifiToggleProc.running) return
        const target = root.wifiEnabled ? "off" : "on"
        root.wifiEnabled = !root.wifiEnabled
        wifiToggleProc.command = ["nmcli", "radio", "wifi", target]
        wifiToggleProc.running = true
    }

    function checkQrWifi() {
        if (!qrStatusProc.running) qrStatusProc.running = true
    }

    function scanWifi(rescan) {
        if (wifiScanProc.running) return
        root.wifiScanning = true
        const cmd = ["python3", Quickshell.shellPath("core/system_service.py"), "wifi"]
        if (rescan === false) cmd.push("--no-rescan")
        wifiScanProc.command = cmd
        wifiScanProc.running = true
    }

    // ── Bluetooth ────────────────────────────────────────────────────────────
    property bool btPresent: false
    property bool btPowered: false
    property var btDevices: []
    property int btConnectedCount: 0
    property string btDevice: ""
    property bool btBusy: false

    function _applyBtState(txt) {
        try {
            const d = JSON.parse(txt.trim())
            root.btPresent = d.present === true
            root.btPowered = Boolean(d.allume || d.powered)
            root.btDevices = Array.isArray(d.appaires) ? d.appaires : []
            const conns = Array.isArray(d.connectes) ? d.connectes : []
            root.btConnectedCount = conns.length
            root.btDevice = conns.length > 0 ? String(conns[0].nom || conns[0].name || "") : ""
        } catch (e) {}
    }

    property Process btStateProc: Process {
        command: ["python3", Quickshell.shellPath("core/bluetooth_service.py"), "etat"]
        stdout: StdioCollector { onStreamFinished: root._applyBtState(text) }
    }

    property Process btActionProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.btBusy = false
                root._applyBtState(text)
            }
        }
        onExited: root.btBusy = false
    }

    function refreshBluetooth() {
        if (!btStateProc.running) btStateProc.running = true
    }

    function btCommand(args) {
        if (btActionProc.running) return
        root.btBusy = true
        btActionProc.command = ["python3", Quickshell.shellPath("core/bluetooth_service.py")].concat(args)
        btActionProc.running = true
    }

    // ── Formatage partagé (USB / Hermes) ─────────────────────────────────────
    function formatBytes(o) {
        const go = Number(o || 0) / 1073741824
        if (go >= 1000) return (go / 1000).toFixed(1).replace(".", ",") + " To"
        if (go >= 1) return Math.round(go) + " Go"
        return Math.round(go * 1000) + " Mo"
    }

    function formatTokens(n) {
        n = Number(n) || 0
        if (n >= 1e6) return (n / 1e6).toFixed(1).replace(".", ",") + " M"
        if (n >= 1e3) return Math.round(n / 1e3) + " k"
        return String(n)
    }

    function formatDuration(s) {
        s = Number(s) || 0
        if (s < 60) return Math.round(s) + " s"
        const m = Math.floor(s / 60)
        if (m < 60) return m + " min"
        const h = Math.floor(m / 60)
        return h + " h " + String(m % 60).padStart(2, "0")
    }

    // ── Lancement d'applications isolé (hors cgroup quickshell.service) ─────
    function launchInScope(shellCmd) {
        Quickshell.execDetached([
            "sh", "-c",
            'if command -v systemd-run >/dev/null 2>&1; then exec systemd-run --user --scope --quiet -- sh -c "$1"; else exec setsid sh -c "$1"; fi',
            "_", String(shellCmd)
        ])
    }

    // ── Icônes de zone de notification (core/tray_icons.json) ───────────────
    property var trayIconMap: ({})

    property FileView trayIconsFile: FileView {
        path: Quickshell.shellPath("core/tray_icons.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.trayIconMap = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.trayIconMap = ({})
            }
        }
    }

    function trayIconFor(itemId) {
        if (!itemId) return ""
        const entry = (root.trayIconMap || ({}))[itemId]
        if (!entry) return ""
        const value = (typeof entry === "string") ? entry : (entry.icon || "")
        if (!value) return ""
        if (value.charAt(0) === "/")
            return "file://" + value
        return "file://" + Quickshell.shellPath("assets/tray/" + value)
    }

    // ── Variables d'application (core/app_vars.json) ────────────────────────
    property var appVars: ({})

    property FileView appVarsFile: FileView {
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.appVars = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.appVars = ({})
            }
        }
    }

    function program(name) {
        return (root.appVars && root.appVars[name]) ? String(root.appVars[name]) : ""
    }
}
