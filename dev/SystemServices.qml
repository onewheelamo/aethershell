pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Services système partagés : Wi-Fi, scan QR Wi-Fi, Bluetooth et lancement isolé.
QtObject {
    id: root

    // ── Wi-Fi ────────────────────────────────────────────────────────────────
    property var wifiNetworks: []
    property bool wifiScanning: false
    property bool wifiEnabled: Boolean(Theme.systemInfo && Theme.systemInfo.wifi && (Theme.systemInfo.wifi.enabled !== false))
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
            Theme.rafraichirSystemInfo()
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
}
