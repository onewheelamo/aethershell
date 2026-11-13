import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 4 DE L'ÎLOT : SYSTÈME & RÉSEAU (icône monitor/cpu)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property int cpuPct: 0
    property int cpuTemp: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property int ramPct: 0
    property int gpuPct: 0
    property int gpuTemp: 0
    property string diskSummary: "--"
    property int diskPct: 0

    property var wifiNetworks: []
    property bool scanning: false
    property string passwordSsid: ""
    property string pendingConnectSsid: ""
    property string wifiStatusMsg: ""
    property bool wifiConnecting: false
    property bool btPresent: false
    property bool btOn: false
    property var btDevices: []
    property int btConnectedCount: 0
    property bool btBusy: false
    property string homelabLine: ""

    readonly property var sysInfo: Theme.systemInfo || ({})
    readonly property var wifiInfo: sysInfo.wifi || ({})

    function signalIconFor(sig) {
        let s = Number(sig || 0)
        if (s >= 80) return "wifi-full"
        if (s >= 60) return "wifi-high"
        if (s >= 40) return "wifi-medium"
        if (s >= 15) return "wifi-low"
        return "wifi-none"
    }

    function connectWifi(ssid, pwd) {
        if (!ssid || wifiConnectProc.running) return
        root.pendingConnectSsid = ssid
        root.wifiConnecting = true
        root.wifiStatusMsg = "Connexion à " + ssid + "…"
        wifiConnectProc.command = [
            "python3", Quickshell.shellPath("core/system_service.py"),
            "wifi_connect", String(ssid), String(pwd || "")
        ]
        wifiConnectProc.running = true
    }

    Connections {
        target: Theme
        function onIslandPanelOpenChanged() {
            if (!Theme.islandPanelOpen) {
                root.passwordSsid = ""
                root.wifiStatusMsg = ""
                Theme.islandNeedsKeyboard = false
            }
        }
    }

    function refreshTelemetry() {
        if (!sysStatsProc.running) sysStatsProc.running = true
        if (!diskStatsProc.running) diskStatsProc.running = true
        if (!homelabProc.running) homelabProc.running = true
        if (!btStateProc.running) btStateProc.running = true
    }

    function btCommand(args) {
        if (btActionProc.running) return
        root.btBusy = true
        btActionProc.command = ["python3", Quickshell.shellPath("core/bluetooth_service.py")].concat(args)
        btActionProc.running = true
    }

    function scanWifi() {
        if (wifiScanProc.running) return
        scanning = true
        wifiScanProc.running = true
    }

    Component.onCompleted: refreshTelemetry()

    // Sonde active uniquement quand cet onglet est visible
    Timer {
        interval: 3000
        running: root.visible && Theme.islandPanelOpen && Theme.islandPanelTab === 3
        repeat: true
        onTriggered: root.refreshTelemetry()
    }

    Process {
        id: sysStatsProc
        command: ["python3", Quickshell.shellPath("core/systeme_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    let barres = (d.compact && Array.isArray(d.compact.barres)) ? d.compact.barres : []
                    for (let i = 0; i < barres.length; i++) {
                        let b = barres[i]
                        if (b.cle === "cpu") root.cpuPct = Math.round(Number(b.valeur || 0))
                        else if (b.cle === "ram") root.ramPct = Math.round(Number(b.valeur || 0))
                        else if (b.cle === "gpu") root.gpuPct = Math.round(Number(b.valeur || 0))
                        else if (b.cle === "temp") root.cpuTemp = Math.round(Number(b.valeur || 0))
                    }
                    let det = d.detail || ({})
                    if (det.ram) {
                        root.ramUsed = Number(det.ram.utilisee_go || 0)
                        root.ramTotal = Number(det.ram.totale_go || 0)
                    }
                    if (det.gpu && det.gpu.temperature !== undefined) {
                        root.gpuTemp = Math.round(Number(det.gpu.temperature || 0))
                    }
                    if (det.temp && det.temp.cpu !== undefined) {
                        root.cpuTemp = Math.round(Number(det.temp.cpu || 0))
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: diskStatsProc
        command: ["python3", Quickshell.shellPath("core/disques_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    let montages = (d.detail && Array.isArray(d.detail.montages)) ? d.detail.montages : []
                    if (montages.length > 0) {
                        let p = montages.find(m => String(m.montage) === "/home")
                        if (!p) {
                            p = montages.reduce((best, cur) =>
                                (Number(cur.taille_go || 0) > Number(best.taille_go || 0)) ? cur : best,
                                montages[0])
                        }
                        root.diskPct = Math.round(Number(p.pourcent || 0))
                        root.diskSummary = Number(p.utilise_go || 0).toFixed(0) + " / " + Number(p.taille_go || 0).toFixed(0) + " Go"
                    } else if (d.compact && Array.isArray(d.compact.barres) && d.compact.barres.length > 0) {
                        root.diskPct = Math.round(Number(d.compact.barres[0].valeur || 0))
                        root.diskSummary = String(d.compact.barres[0].texte || "--")
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: wifiScanProc
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false
                try {
                    let arr = JSON.parse(text.trim())
                    root.wifiNetworks = arr.slice(0, 4)
                } catch (e) {
                    root.wifiNetworks = []
                }
            }
        }
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiConnecting = false
                let ok = false
                let msg = ""
                let ssid = root.pendingConnectSsid
                try {
                    let d = JSON.parse(text.trim())
                    ok = Boolean(d.success)
                    msg = String(d.message || "")
                    if (d.ssid) ssid = String(d.ssid)
                } catch (e) {}
                if (ok) {
                    root.passwordSsid = ""
                    Theme.islandNeedsKeyboard = false
                    root.wifiStatusMsg = ""
                    wifiPassInput.text = ""
                    if (wifiScanProc.running) wifiScanProc.running = false
                    wifiScanProc.command = ["python3", Quickshell.shellPath("core/system_service.py"), "wifi", "--no-rescan"]
                    wifiScanProc.running = true
                } else {
                    root.passwordSsid = ssid
                    Theme.islandNeedsKeyboard = true
                    wifiPassInput.forceActiveFocus()
                    root.wifiStatusMsg = msg !== "" ? msg : "Clé requise ou échec de connexion"
                }
            }
        }
    }

    Process {
        id: btStateProc
        command: ["python3", Quickshell.shellPath("core/bluetooth_service.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    root.btPresent = d.present === true
                    root.btOn = d.allume === true
                    root.btDevices = Array.isArray(d.appaires) ? d.appaires : []
                    root.btConnectedCount = Array.isArray(d.connectes) ? d.connectes.length : 0
                } catch (e) {}
            }
        }
    }

    Process {
        id: btActionProc
        onExited: {
            root.btBusy = false
            if (!btStateProc.running) btStateProc.running = true
        }
    }

    Process {
        id: homelabProc
        command: ["python3", Quickshell.shellPath("core/homelab_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    if (d && d.configure !== false && d.noeuds && d.noeuds.length > 0) {
                        let n = d.noeuds[0]
                        root.homelabLine = String(n.nom || "Homelab") + " · CPU " + Math.round(Number(n.cpu || 0)) + " % · RAM " + Math.round(Number(n.ram || 0)) + " %"
                    } else {
                        root.homelabLine = ""
                    }
                } catch (e) {
                    root.homelabLine = ""
                }
            }
        }
    }

    component GaugeCard: Rectangle {
        property string title: ""
        property string metric: ""
        property int pct: 0

        Layout.fillWidth: true
        Layout.preferredHeight: 54
        radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
        color: Qt.alpha(Theme.surfaceVariant, 0.34)
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.08)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: title
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.weight: Font.Bold
                    color: Theme.fg
                }
                Text {
                    text: metric
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: pct > 85 ? Theme.error : Theme.accent
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 5
                radius: 2.5
                color: Qt.alpha(Theme.fg, 0.14)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, pct / 100))
                    height: parent.height
                    radius: 2.5
                    color: pct > 85 ? Theme.error : Theme.accent
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "SYSTÈME & RÉSEAU"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: cfgBtnRow.implicitWidth + 16
                radius: 8
                color: cfgBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.surfaceVariant, 0.45)
                border.width: 1
                border.color: cfgBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.5) : Qt.alpha(Theme.fg, 0.12)

                RowLayout {
                    id: cfgBtnRow
                    anchors.centerIn: parent
                    spacing: 5

                    Icon {
                        glyph: "cog"
                        size: 12
                        color: cfgBtnMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                    }

                    Text {
                        text: "Configuration"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Medium
                        color: cfgBtnMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                    }
                }

                MouseArea {
                    id: cfgBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Theme.islandPanelOpen = false
                        Theme.configPanelVisible = true
                    }
                }
            }

            Text {
                text: "↻ Actualiser"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: refMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                MouseArea {
                    id: refMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshTelemetry()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 8

            GaugeCard {
                title: "CPU"
                metric: root.cpuPct + " %" + (root.cpuTemp > 0 ? (" · " + root.cpuTemp + " °C") : "")
                pct: root.cpuPct
            }

            GaugeCard {
                title: "RAM"
                metric: root.ramTotal > 0 ? (root.ramUsed.toFixed(1) + " / " + root.ramTotal.toFixed(0) + " Go") : (root.ramPct + " %")
                pct: root.ramPct
            }

            GaugeCard {
                title: "GPU"
                metric: root.gpuPct + " %" + (root.gpuTemp > 0 ? (" · " + root.gpuTemp + " °C") : "")
                pct: root.gpuPct
            }

            GaugeCard {
                title: "Disque /"
                metric: root.diskSummary + " (" + root.diskPct + " %)"
                pct: root.diskPct
            }
        }

        Text {
            text: "RÉSEAU"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.30)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Icon {
                        glyph: root.wifiInfo.connected ? "wifi-full" : "wifi-none"
                        size: Theme.iconMd
                        color: root.wifiInfo.connected ? Theme.accent : Theme.error
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.wifiInfo.connected
                            ? ((root.wifiInfo.ssid || "Connecté") + " (" + (root.wifiInfo.signal || 0) + " %)")
                            : "Hors ligne"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.DemiBold
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 74
                        radius: 7
                        color: Qt.alpha(Theme.accent, 0.18)

                        Text {
                            anchors.centerIn: parent
                            text: root.scanning ? "Scan…" : "↻ Scan"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scanWifi()
                        }
                    }
                }

                GridLayout {
                    visible: root.wifiNetworks.length > 0
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: root.wifiNetworks
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool isSelectedForPwd: root.passwordSsid === String(modelData.ssid || "")
                            readonly property bool isConnected: Boolean(modelData.in_use)

                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 7
                            color: isConnected
                                ? Qt.alpha(Theme.accent, 0.24)
                                : (isSelectedForPwd ? Qt.alpha(Theme.accent, 0.14) : (netChipMa.containsMouse ? Qt.alpha(Theme.fg, 0.13) : Qt.alpha(Theme.fg, 0.07)))
                            border.width: (isConnected || isSelectedForPwd) ? 1 : 0
                            border.color: isConnected ? Theme.accent : Theme.accentMuted

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 5

                                Icon {
                                    glyph: root.signalIconFor(modelData.signal)
                                    size: 13
                                    color: isConnected
                                        ? Theme.accent
                                        : (Number(modelData.signal || 0) >= 60 ? Theme.success : (Number(modelData.signal || 0) >= 30 ? Theme.warn : Theme.error))
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.ssid || "?")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    font.weight: isConnected ? Font.Bold : Font.Normal
                                    color: isConnected ? Theme.accent : Theme.fg
                                    elide: Text.ElideRight
                                }

                                Icon {
                                    visible: Boolean(modelData.secured) && !isConnected && !Boolean(modelData.known)
                                    glyph: "lock"
                                    size: 10
                                    color: Qt.alpha(Theme.fg, 0.6)
                                }

                                Text {
                                    text: (modelData.signal !== undefined ? modelData.signal : 0) + "%"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    color: isConnected ? Theme.accent : Qt.alpha(Theme.fg, 0.65)
                                }
                            }

                            MouseArea {
                                id: netChipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let ssid = String(modelData.ssid || "")
                                    if (!ssid || isConnected) return
                                    if (!Boolean(modelData.secured) || Boolean(modelData.known)) {
                                        root.passwordSsid = ""
                                        Theme.islandNeedsKeyboard = false
                                        root.connectWifi(ssid, "")
                                    } else {
                                        if (root.passwordSsid === ssid) {
                                            root.passwordSsid = ""
                                            Theme.islandNeedsKeyboard = false
                                        } else {
                                            root.passwordSsid = ssid
                                            root.wifiStatusMsg = ""
                                            wifiPassInput.text = ""
                                            Theme.islandNeedsKeyboard = true
                                            wifiPassInput.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Champ clé Wi-Fi si réseau inconnu / protégé
                Rectangle {
                    visible: root.passwordSsid !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 7
                    color: Qt.alpha(Theme.bg, 0.55)
                    border.width: 1
                    border.color: Theme.accentMuted

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 6

                        Icon {
                            glyph: "lock"
                            size: 12
                            color: Theme.accent
                        }

                        TextInput {
                            id: wifiPassInput
                            Layout.fillWidth: true
                            color: Theme.fg
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            echoMode: TextInput.Password
                            clip: true
                            selectByMouse: true
                            Keys.onReturnPressed: root.connectWifi(root.passwordSsid, text)
                            Keys.onEnterPressed: root.connectWifi(root.passwordSsid, text)
                            Keys.onEscapePressed: {
                                root.passwordSsid = ""
                                Theme.islandNeedsKeyboard = false
                            }

                            Text {
                                visible: parent.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clé pour " + root.passwordSsid + "…"
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                color: Qt.alpha(Theme.fg, 0.45)
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: 26
                            radius: 5
                            color: Qt.alpha(Theme.accent, 0.25)
                            Text {
                                anchors.centerIn: parent
                                text: "→"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Theme.accent
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectWifi(root.passwordSsid, wifiPassInput.text)
                            }
                        }

                        Rectangle {
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: 22
                            radius: 5
                            color: Qt.alpha(Theme.fg, 0.1)
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.pixelSize: 10
                                color: Qt.alpha(Theme.fg, 0.75)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.passwordSsid = ""
                                    Theme.islandNeedsKeyboard = false
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: root.wifiStatusMsg !== ""
                    Layout.fillWidth: true
                    text: root.wifiStatusMsg
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    color: root.wifiConnecting ? Theme.accent : Theme.error
                    elide: Text.ElideRight
                }

                // Séparateur Wi-Fi / Bluetooth
                Rectangle {
                    visible: root.btPresent
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.08)
                }

                // Bluetooth
                RowLayout {
                    visible: root.btPresent
                    Layout.fillWidth: true
                    spacing: 8

                    Icon {
                        glyph: "bluetooth"
                        size: Theme.iconMd
                        color: root.btOn ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.btOn
                            ? ("Bluetooth" + (root.btConnectedCount > 0 ? (" · " + root.btConnectedCount + " connecté(s)") : " · Activé"))
                            : "Bluetooth · Désactivé"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.DemiBold
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: 50
                        radius: 7
                        color: root.btOn ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.1)

                        Text {
                            anchors.centerIn: parent
                            text: root.btBusy ? "…" : (root.btOn ? "ON" : "OFF")
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            font.weight: Font.Bold
                            color: root.btOn ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.btCommand(["basculer"])
                        }
                    }
                }

                GridLayout {
                    visible: root.btPresent && root.btOn && root.btDevices.length > 0
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: root.btDevices.slice(0, 4)
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool btConn: Boolean(modelData.connecte)

                            Layout.fillWidth: true
                            Layout.preferredHeight: 26
                            radius: 7
                            color: btConn
                                ? Qt.alpha(Theme.accent, 0.24)
                                : (btDevMa.containsMouse ? Qt.alpha(Theme.fg, 0.13) : Qt.alpha(Theme.fg, 0.07))
                            border.width: btConn ? 1 : 0
                            border.color: Theme.accent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 5

                                Icon {
                                    glyph: "bluetooth"
                                    size: 11
                                    color: btConn ? Theme.accent : Qt.alpha(Theme.fg, 0.65)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.nom || modelData.mac || "Appareil")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    font.weight: btConn ? Font.Bold : Font.Normal
                                    color: btConn ? Theme.accent : Theme.fg
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: btDevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let mac = String(modelData.mac || "")
                                    if (!mac) return
                                    root.btCommand([btConn ? "deconnecter" : "connecter", mac])
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: root.btPresent && root.btOn && root.btDevices.length === 0
                    Layout.fillWidth: true
                    text: "Aucun appareil Bluetooth appairé"
                    font.family: Theme.fontUi
                    font.pixelSize: 10
                    color: Qt.alpha(Theme.fg, 0.5)
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Homelab si configuré
        Rectangle {
            visible: root.homelabLine !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 8
            color: Qt.alpha(Theme.surfaceVariant, 0.34)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.success
                }

                Text {
                    Layout.fillWidth: true
                    text: "Homelab · " + root.homelabLine
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.fg
                    elide: Text.ElideRight
                }
            }
        }
    }
}
