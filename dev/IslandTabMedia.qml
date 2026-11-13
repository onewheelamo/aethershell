import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 2 DE L'ÎLOT : MÉDIA & SON (icône music)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var activePlayer: null
    property var validPlayers: []
    property int selectedPlayerIndex: 0

    readonly property var currentPlayer: {
        if (validPlayers && validPlayers.length > 0) {
            let idx = Math.max(0, Math.min(validPlayers.length - 1, selectedPlayerIndex))
            return validPlayers[idx]
        }
        return activePlayer
    }

    readonly property bool isPlaying: currentPlayer ? (currentPlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string trackTitle: currentPlayer ? (currentPlayer.trackTitle || "Aucun titre") : ""
    readonly property string trackArtist: currentPlayer ? (currentPlayer.trackArtist || "") : ""
    readonly property string trackAlbum: currentPlayer ? (currentPlayer.trackAlbum || "") : ""
    readonly property string artUrl: currentPlayer ? (currentPlayer.trackArtUrl || "") : ""
    readonly property real posSec: currentPlayer ? Number(currentPlayer.position || 0) : 0
    readonly property real lenSec: currentPlayer ? Number(currentPlayer.length || 0) : 0

    property var sinks: []
    property string defaultSink: ""
    property bool micMuted: false

    readonly property bool vizActif: {
        let _rev = Theme.barAppletsRev
        let a = Theme.barAppletsActifs ? Theme.barAppletsActifs["visualiseur"] : null
        return a ? Boolean(a.enabled !== false) : false
    }

    function fmtTime(sec) {
        let s = Math.max(0, Math.floor(sec || 0))
        let m = Math.floor(s / 60)
        let r = s % 60
        return String(m).padStart(2, "0") + ":" + String(r).padStart(2, "0")
    }

    function refreshAudio() {
        if (!sinkListProc.running) sinkListProc.running = true
        if (!micCheckProc.running) micCheckProc.running = true
    }

    Component.onCompleted: refreshAudio()

    // Rafraîchit la position de lecture chaque seconde tant que le média joue
    Timer {
        interval: 1000
        running: root.visible && root.isPlaying && root.currentPlayer !== null
        repeat: true
        onTriggered: {
            if (root.currentPlayer && root.currentPlayer.positionChanged) {
                root.currentPlayer.positionChanged()
            }
        }
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

    Process {
        id: vizCmdProc
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // En-tête + sélecteur de lecteur si multiple
        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "MÉDIA & SON"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                visible: root.validPlayers && root.validPlayers.length > 1
                Layout.preferredHeight: 24
                Layout.preferredWidth: playerSwitchText.implicitWidth + 16
                radius: 8
                color: Qt.alpha(Theme.accent, 0.16)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.35)

                Text {
                    id: playerSwitchText
                    anchors.centerIn: parent
                    text: (root.currentPlayer && root.currentPlayer.identity ? root.currentPlayer.identity : "Lecteur") + " ⇄"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.validPlayers.length > 0) {
                            root.selectedPlayerIndex = (root.selectedPlayerIndex + 1) % root.validPlayers.length
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

        // Carte MPRIS
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.currentPlayer ? 104 : 54
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            Text {
                visible: !root.currentPlayer
                anchors.centerIn: parent
                text: "Aucun média en cours de lecture"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                color: Qt.alpha(Theme.fg, 0.55)
            }

            RowLayout {
                visible: root.currentPlayer !== null
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                // Pochette
                Rectangle {
                    Layout.preferredWidth: 78
                    Layout.preferredHeight: 78
                    radius: 10
                    color: Qt.alpha(Theme.accent, 0.15)
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: root.artUrl !== ""
                    }

                    Icon {
                        visible: root.artUrl === ""
                        anchors.centerIn: parent
                        glyph: "music"
                        size: 28
                        color: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: root.trackTitle
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textMd
                        font.weight: Font.Bold
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.trackArtist + (root.trackAlbum ? (" · " + root.trackAlbum) : "")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Qt.alpha(Theme.fg, 0.7)
                        elide: Text.ElideRight
                    }

                    // Barre de progression
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: root.fmtTime(root.posSec)
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                            color: Qt.alpha(Theme.fg, 0.6)
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Qt.alpha(Theme.fg, 0.15)

                                Rectangle {
                                    width: root.lenSec > 0 ? parent.width * Math.min(1, root.posSec / root.lenSec) : 0
                                    height: parent.height
                                    radius: 2
                                    color: Theme.accent
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.currentPlayer && root.currentPlayer.canSeek && root.lenSec > 0
                                onClicked: mouse => {
                                    let target = (mouse.x / width) * root.lenSec
                                    root.currentPlayer.position = target
                                }
                            }
                        }

                        Text {
                            text: root.fmtTime(root.lenSec)
                            font.family: Theme.fontUi
                            font.pixelSize: 10
                            color: Qt.alpha(Theme.fg, 0.6)
                        }
                    }

                    // Contrôles de transport
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 18

                        Text {
                            text: "⏮"
                            font.family: Theme.fontUi
                            font.pixelSize: 15
                            color: prevM.containsMouse ? Theme.accent : Theme.fg
                            MouseArea {
                                id: prevM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.currentPlayer) root.currentPlayer.previous()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 26
                            radius: 8
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: root.isPlaying ? "⏸" : "▶"
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                color: Theme.bg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.currentPlayer) root.currentPlayer.togglePlaying()
                            }
                        }

                        Text {
                            text: "⏭"
                            font.family: Theme.fontUi
                            font.pixelSize: 15
                            color: nextM.containsMouse ? Theme.accent : Theme.fg
                            MouseArea {
                                id: nextM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.currentPlayer) root.currentPlayer.next()
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
            Layout.fillHeight: true
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

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: 112
                        radius: 6
                        color: root.vizActif ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: root.vizActif ? "Visualiseur : ON" : "Visualiseur : OFF"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: root.vizActif ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                vizCmdProc.command = [
                                    "python3", Quickshell.shellPath("core/bar_applets.py"),
                                    root.vizActif ? "desactiver" : "activer", "visualiseur"
                                ]
                                vizCmdProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }
}
