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
        command: [Quickshell.shellPath("core/as-core"), "system-service", "info"]
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
        command: [Quickshell.shellPath("core/as-core"), "weather"]
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
        const args = [Quickshell.shellPath("core/as-core"), "weather"]
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
        command: [Quickshell.shellPath("core/as-core"), "daemon", "2"]
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
        command: [Quickshell.shellPath("core/as-core"), "wifi-qr", "status"]
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
        command: [Quickshell.shellPath("core/as-core"), "system-service", "wifi"]
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
        const cmd = [Quickshell.shellPath("core/as-core"), "system-service", "wifi"]
        if (rescan === false) cmd.push("--no-rescan")
        wifiScanProc.command = cmd
        wifiScanProc.running = true
    }

    property bool wifiConnecting: false
    signal wifiConnectFinished(bool ok, string ssid, string message)
    property string _pendingWifiSsid: ""

    property Process wifiConnectProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiConnecting = false
                let ok = false
                let msg = ""
                let ssid = root._pendingWifiSsid
                try {
                    const d = JSON.parse(text.trim())
                    ok = Boolean(d.success)
                    msg = String(d.message || "")
                    if (d.ssid) ssid = String(d.ssid)
                } catch (e) {}
                if (ok) {
                    root.rafraichirSystemInfo()
                    root.scanWifi(false)
                }
                root.wifiConnectFinished(ok, ssid, msg)
            }
        }
    }

    function connectWifi(ssid, pwd) {
        if (!ssid || wifiConnectProc.running) return
        root._pendingWifiSsid = String(ssid)
        root.wifiConnecting = true
        wifiConnectProc.command = [
            Quickshell.shellPath("core/as-core"), "system-service",
            "wifi_connect", String(ssid), String(pwd || "")
        ]
        wifiConnectProc.running = true
    }

    function signalIconFor(sig, connected) {
        if (connected === false && Number(sig || 0) <= 0) return "wifi-none"
        const s = Number(sig || 0)
        if (s >= 75) return "wifi-full"
        if (s >= 50) return "wifi-high"
        if (s >= 25) return "wifi-medium"
        return s > 0 ? "wifi-low" : "wifi-none"
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
        command: [Quickshell.shellPath("core/as-core"), "bluetooth", "etat"]
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
        btActionProc.command = [Quickshell.shellPath("core/as-core"), "bluetooth"].concat(args)
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

    // ── Démons et veilles d'arrière-plan (tray, xdg, thèmes, nuit) ──────────
    property Process trayWatchdogProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "tray-watchdog", "--interval", "10"]
    }

    property Process lienSystemeProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "lien-systeme", "--appliquer"]
    }

    property Process themesScanProc: Process {
        running: true
        command: [Quickshell.shellPath("core/as-core"), "themes-scan", "--sync"]
        onExited: Theme.relireCatalogue()
    }

    property Process themesVeilleProc: Process {
        running: true
        command: ["sh", Quickshell.shellPath("core/veille_themes.sh")]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf(".colors") >= 0) themesDebounce.restart() }
        }
    }

    property Timer themesDebounce: Timer {
        interval: 600
        repeat: false
        onTriggered: {
            if (themesScanProc.running) return
            themesScanProc.running = true
        }
    }

    property var nuitEtat: ({})
    property Process nuitApplyProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "nuit", "appliquer"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d === "object") root.nuitEtat = d
                } catch (e) {}
            }
        }
    }

    property Timer nuitApplyTimer: Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (nuitApplyProc.running) return
            nuitApplyProc.running = true
        }
    }

    // ── Cache partagé des paires Popup ↔ Widget (USB, Todo, Hermes) ──────────
    property var usbData: ({})
    property Process usbPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "usb", "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.usbData = (d.detail && d.detail.usb) ? d.detail.usb : d
                } catch (e) {
                    root.usbData = ({})
                }
            }
        }
    }
    function rafraichirUsb() {
        usbPollProc.running = false
        usbPollProc.running = true
    }

    property var todoData: ({})
    property Process todoPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "todo", "etat", "--options={\"fichier\": \"*\"}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.todoData = (d.detail && d.detail.todo) ? d.detail.todo : d
                } catch (e) {
                    root.todoData = ({})
                }
            }
        }
    }
    function rafraichirTodo() {
        todoPollProc.running = false
        todoPollProc.running = true
    }

    property var hermesData: ({})
    property bool hermesCharge: false
    property Process hermesPollProc: Process {
        command: [Quickshell.shellPath("core/as-core"), "hermes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.hermesData = (d.detail || ({})).hermes || ({})
                } catch (e) {
                    root.hermesData = ({})
                }
                root.hermesCharge = true
            }
        }
    }
    function rafraichirHermes() {
        hermesPollProc.running = false
        hermesPollProc.running = true
    }

    // ── Mises à jour système partagées (pacman / dnf / apt, évite les verrous) ──
    property string majGestionnaire: ""
    property int majNombre: 0
    property bool majPret: false
    property bool majActif: false

    onMajActifChanged: {
        if (majActif && majGestionnaire === "" && !majDetectProc.running) {
            majDetectProc.running = true
        }
    }

    property Process majDetectProc: Process {
        command: ["sh", "-c", "command -v pacman >/dev/null && echo arch; command -v dnf >/dev/null && echo dnf; command -v apt-get >/dev/null && echo apt"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lignes = text.trim().split("\n").map(function (s) { return s.trim() })
                for (let i = 0; i < lignes.length; ++i) {
                    if (lignes[i] === "arch" || lignes[i] === "dnf" || lignes[i] === "apt") {
                        root.majGestionnaire = lignes[i]
                        break
                    }
                }
                if (root.majGestionnaire !== "") root.verifierMaj()
            }
        }
    }

    property Process majVerifProc: Process {
        command: ["sh", "-c", root.majGestionnaire === "dnf"
                  ? "timeout 60 dnf -q check-update 2>/dev/null | grep -cE '^[A-Za-z0-9][A-Za-z0-9_.+-]*\\.'"
                  : (root.majGestionnaire === "apt"
                     ? "timeout 20 apt-get -s upgrade 2>/dev/null | grep -c '^Inst '"
                     : "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^[[:space:]]*$' | wc -l")]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.majNombre = isNaN(n) ? 0 : n
                root.majPret = true
            }
        }
    }

    property Timer majTimer: Timer {
        interval: 300000
        repeat: true
        running: root.majActif && root.majGestionnaire !== ""
        onTriggered: root.verifierMaj()
    }

    function verifierMaj() {
        if (root.majGestionnaire === "" || majVerifProc.running) return
        majVerifProc.running = true
    }

    function lancerMaj() {
        if (root.majGestionnaire === "dnf")
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "sudo dnf upgrade --refresh"])
        else if (root.majGestionnaire === "apt")
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "sudo apt update && sudo apt upgrade"])
        else
            Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"), "arch-update"])
    }
}
