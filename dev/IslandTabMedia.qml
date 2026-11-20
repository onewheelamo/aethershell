import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 2 DE L'ÎLOT : AFFICHAGE & SON (icône monitor)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property bool embedded: false
    implicitHeight: mediaCol.implicitHeight

    property var monitorsList: []
    property string primaryMonitor: ""
    property string selectedMonitorName: ""

    readonly property var selectedMonitor: {
        for (let i = 0; i < monitorsList.length; i++) {
            if (monitorsList[i].name === selectedMonitorName) return monitorsList[i]
        }
        return monitorsList.length > 0 ? monitorsList[0] : null
    }

    property var sinks: []
    property string defaultSink: ""
    property bool micMuted: false

    function refreshDisplay() {
        if (!displayStateProc.running) displayStateProc.running = true
    }

    function refreshAudio() {
        if (!sinkListProc.running) sinkListProc.running = true
        if (!micCheckProc.running) micCheckProc.running = true
    }

    Component.onCompleted: {
        refreshDisplay()
        refreshAudio()
    }

    Process {
        id: displayStateProc
        command: [Quickshell.shellPath("core/as-core"), "config", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    const disp = d.display || ({})
                    const list = disp.monitors || []
                    root.monitorsList = list
                    root.primaryMonitor = String(disp.primary || "")
                    if (list.length > 0) {
                        let found = false
                        for (let i = 0; i < list.length; i++) {
                            if (list[i].name === root.selectedMonitorName) { found = true; break }
                        }
                        if (!found) {
                            root.selectedMonitorName = root.primaryMonitor !== "" ? root.primaryMonitor : list[0].name
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: displayCmdProc
        onExited: root.refreshDisplay()
    }

    Process {
        id: sinkListProc
        command: ["sh", "-c", "pactl get-default-sink; echo '---'; pactl list short sinks"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.split("---")
                if (parts.length < 2) return
                let defName = parts[0].trim()
                root.defaultSink = defName
                let lines = parts[1].trim().split("\n")
                let res = []
                for (let i = 0; i < lines.length; i++) {
                    let cols = lines[i].split("\t")
                    if (cols.length >= 2) {
                        let name = cols[1].trim()
                        let label = name
                        if (name.indexOf("bluez") !== -1) label = "Casque Bluetooth"
                        else if (name.indexOf("hdmi") !== -1) label = "Sortie HDMI / DP"
                        else if (name.indexOf("analog") !== -1 || name.indexOf("pci") !== -1) label = "Haut-parleurs / Jack"
                        else if (name.indexOf("usb") !== -1) label = "Audio USB"
                        res.push({ name: name, label: label, isDefault: (name === defName) })
                    }
                }
                root.sinks = res
            }
        }
    }

    Process {
        id: micCheckProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.micMuted = (text.indexOf("MUTED") !== -1)
            }
        }
    }

    Process {
        id: audioCmdProc
        onExited: root.refreshAudio()
    }

    ColumnLayout {
        id: mediaCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: root.embedded ? undefined : parent.bottom
        spacing: 10

        // En-tête
        RowLayout {
            visible: !root.embedded
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "AFFICHAGE & SON"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Text {
                visible: root.selectedMonitor !== null
                text: root.selectedMonitor
                    ? (root.selectedMonitor.width + "×" + root.selectedMonitor.height + " · " + root.selectedMonitor.refreshRate + " Hz")
                    : ""
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.accent
            }
        }

        Rectangle {
            visible: !root.embedded
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Carte Écran principal & Résolution
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                // Ligne 1 : Écrans & choix de l'écran principal
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Écran :"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Bold
                        color: Qt.alpha(Theme.fg, 0.7)
                    }

                    Repeater {
                        model: root.monitorsList
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: root.selectedMonitorName === modelData.name
                            readonly property bool prim: Boolean(modelData.is_primary)
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: monLbl.implicitWidth + 16
                            radius: 7
                            color: sel ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                            border.width: 1
                            border.color: sel ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                            Text {
                                id: monLbl
                                anchors.centerIn: parent
                                text: (parent.prim ? "★ " : "") + parent.modelData.name
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.weight: parent.sel ? Font.Bold : Font.Normal
                                color: parent.sel ? Theme.accent : Theme.fg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedMonitorName = parent.modelData.name
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.selectedMonitor !== null && !Boolean(root.selectedMonitor.is_primary)
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: primBtnLbl.implicitWidth + 16
                        radius: 7
                        color: primBtnMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.18)
                        border.width: 1
                        border.color: Theme.accent

                        Text {
                            id: primBtnLbl
                            anchors.centerIn: parent
                            text: "Définir principal"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            font.weight: Font.Bold
                            color: primBtnMa.containsMouse ? Theme.bg : Theme.accent
                        }

                        MouseArea {
                            id: primBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.selectedMonitor) return
                                displayCmdProc.command = [
                                    Quickshell.shellPath("core/as-core"), "config",
                                    "monitor_primary", root.selectedMonitor.name
                                ]
                                displayCmdProc.running = true
                            }
                        }
                    }

                    Text {
                        visible: root.selectedMonitor !== null && Boolean(root.selectedMonitor.is_primary)
                        text: "Principal"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Bold
                        color: Theme.accent
                    }
                }

                // Ligne 2 : Choix de la résolution
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Résolution :"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Bold
                        color: Qt.alpha(Theme.fg, 0.7)
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        contentWidth: modesRow.implicitWidth
                        contentHeight: 26
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick

                        Row {
                            id: modesRow
                            spacing: 6

                            Repeater {
                                model: root.selectedMonitor ? (root.selectedMonitor.availableModes || []) : []
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property string curMode: root.selectedMonitor
                                        ? (root.selectedMonitor.width + "x" + root.selectedMonitor.height + "@" + root.selectedMonitor.refreshRate + "Hz")
                                        : ""
                                    readonly property bool activeMode: modelData === curMode
                                    width: modeLbl.implicitWidth + 14
                                    height: 24
                                    radius: 7
                                    color: activeMode
                                        ? Theme.accent
                                        : (modeMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06))

                                    Text {
                                        id: modeLbl
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.text2xs
                                        font.weight: parent.activeMode ? Font.Bold : Font.Normal
                                        color: parent.activeMode ? Theme.bg : Theme.fg
                                    }

                                    MouseArea {
                                        id: modeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root.selectedMonitor) return
                                            const sc = String(root.selectedMonitor.scale || 1)
                                            displayCmdProc.command = [
                                                Quickshell.shellPath("core/as-core"), "config",
                                                "monitor_mode", root.selectedMonitor.name, parent.modelData, sc
                                            ]
                                            displayCmdProc.running = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Sortie & Entrée audio
        Text {
            text: "SORTIE & ENTRÉE AUDIO"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: !root.embedded
            Layout.preferredHeight: root.embedded ? 172 : 0
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.30)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: sinksCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: sinksCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.sinks
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: modelData.isDefault ? Qt.alpha(Theme.accent, 0.22) : (sMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    Text {
                                        text: modelData.isDefault ? "●" : "○"
                                        font.pixelSize: 11
                                        color: modelData.isDefault ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.textXs
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: sMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        audioCmdProc.command = ["pactl", "set-default-sink", modelData.name]
                                        audioCmdProc.running = true
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

                // Micro + Visualiseur rapide
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Icon {
                        glyph: "microphone"
                        size: Theme.iconSm
                        color: root.micMuted ? Theme.error : Theme.fg
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.micMuted ? "Micro : Muet" : "Micro : Actif"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: root.micMuted ? Theme.error : Theme.fg
                    }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 88
                        radius: 6
                        color: root.micMuted ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.accent, 0.18)

                        Text {
                            anchors.centerIn: parent
                            text: root.micMuted ? "Réactiver" : "Couper"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: root.micMuted ? Theme.error : Theme.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                audioCmdProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
                                audioCmdProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }
}
