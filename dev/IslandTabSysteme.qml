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
    property string homelabLine: ""

    readonly property var sysInfo: Theme.systemInfo || ({})
    readonly property var wifiInfo: sysInfo.wifi || ({})

    function refreshTelemetry() {
        if (!sysStatsProc.running) sysStatsProc.running = true
        if (!diskStatsProc.running) diskStatsProc.running = true
        if (!homelabProc.running) homelabProc.running = true
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
                    if (d.cpu) {
                        root.cpuPct = Math.round(Number(d.cpu.pct || d.cpu.usage || 0))
                        root.cpuTemp = Math.round(Number(d.cpu.temp || 0))
                    }
                    if (d.ram) {
                        root.ramPct = Math.round(Number(d.ram.pct || 0))
                        root.ramUsed = Number(d.ram.utilise_go || d.ram.used_gb || 0)
                        root.ramTotal = Number(d.ram.total_go || d.ram.total_gb || 0)
                    }
                    if (d.gpu) {
                        root.gpuPct = Math.round(Number(d.gpu.pct || 0))
                        root.gpuTemp = Math.round(Number(d.gpu.temp || 0))
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
                    let list = d.disques || d.disks || []
                    if (list.length > 0) {
                        let p = list[0]
                        root.diskPct = Math.round(Number(p.pct || p.percent || 0))
                        root.diskSummary = String(p.utilise || p.used || "") + " / " + String(p.total || "")
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

                RowLayout {
                    visible: root.wifiNetworks.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.wifiNetworks
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 6
                            color: modelData.active ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.fg, 0.08)

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                horizontalAlignment: Text.AlignHCenter
                                text: String(modelData.ssid || "?")
                                font.family: Theme.fontUi
                                font.pixelSize: 10
                                color: modelData.active ? Theme.accent : Theme.fg
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!modelData.active && modelData.ssid) {
                                        wifiConnectProc.command = ["python3", Quickshell.shellPath("core/system_service.py"), "wifi_connect", String(modelData.ssid)]
                                        wifiConnectProc.running = true
                                    }
                                }
                            }
                        }
                    }
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
