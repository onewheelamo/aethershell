import QtQuick
import QtQuick.Layouts
import Quickshell

// Tiroir Live Activity inline de l'Îlot dynamique (tâches longues, minuteur, enregistrement, téléchargements).
Item {
    id: root
    property bool open: false
    property int fadeDuration: 240
    property var liveActivities: []

    anchors.fill: parent
    clip: true
    focus: root.open
    opacity: root.open ? 1.0 : 0.0
    visible: opacity > 0.05
    Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: Theme.islandLiveActivityOpen = false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Icon {
                glyph: "clock"
                size: Theme.iconSm
                color: Theme.accent
            }

            Text {
                Layout.fillWidth: true
                text: "Activités en cours (" + root.liveActivities.length + ")"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                font.bold: true
                color: Theme.fg
            }

            Rectangle {
                id: p5Btn
                property bool hovered: false
                width: 40
                height: 22
                radius: 6
                color: (root.open && hovered) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.55)
                Text { anchors.centerIn: parent; text: "+5m"; font.family: Theme.fontUi; font.pixelSize: Theme.text2xs; font.bold: true; color: Theme.accent }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: root.open
                    cursorShape: Qt.PointingHandCursor
                    onEntered: p5Btn.hovered = true
                    onExited: p5Btn.hovered = false
                    onClicked: { p5Btn.hovered = false; ShellState.startTimer(5, "Minuteur 5m") }
                }
            }

            Rectangle {
                id: p25Btn
                property bool hovered: false
                width: 46
                height: 22
                radius: 6
                color: (root.open && hovered) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.55)
                Text { anchors.centerIn: parent; text: "+25m"; font.family: Theme.fontUi; font.pixelSize: Theme.text2xs; font.bold: true; color: Theme.accent }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: root.open
                    cursorShape: Qt.PointingHandCursor
                    onEntered: p25Btn.hovered = true
                    onExited: p25Btn.hovered = false
                    onClicked: { p25Btn.hovered = false; ShellState.startTimer(25, "Pomodoro 25m") }
                }
            }

            Rectangle {
                width: 68
                height: 22
                radius: 6
                color: Qt.alpha(Theme.bg, 0.55)
                border.width: 1
                border.color: customTimerInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.16)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 2
                    spacing: 2

                    TextInput {
                        id: customTimerInput
                        Layout.fillWidth: true
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        color: Theme.fg
                        horizontalAlignment: TextInput.AlignHCenter
                        validator: IntValidator { bottom: 1; top: 999 }
                        maximumLength: 3
                        selectByMouse: true
                        Keys.onEscapePressed: Theme.islandLiveActivityOpen = false
                        onAccepted: {
                            const m = parseInt(text, 10)
                            if (!isNaN(m) && m > 0) {
                                ShellState.startTimer(m, "Minuteur " + m + "m")
                                text = ""
                            }
                        }

                        Text {
                            visible: customTimerInput.text === ""
                            anchors.centerIn: parent
                            text: "min"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            color: Qt.alpha(Theme.fg, 0.42)
                        }
                    }

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 5
                        color: customGoMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)
                        Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 8; color: Theme.accent }
                        MouseArea {
                            id: customGoMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const m = parseInt(customTimerInput.text, 10)
                                if (!isNaN(m) && m > 0) {
                                    ShellState.startTimer(m, "Minuteur " + m + "m")
                                    customTimerInput.text = ""
                                } else {
                                    customTimerInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 22
                height: 22
                radius: 6
                color: laCloseMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.45)
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 10; font.bold: true; color: laCloseMa.containsMouse ? Theme.error : Theme.fg }
                MouseArea { id: laCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Theme.islandLiveActivityOpen = false }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.fg, 0.1) }

        Text {
            visible: root.liveActivities.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "Aucune activité longue en cours"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            color: Qt.alpha(Theme.fg, 0.5)
        }

        ListView {
            visible: root.liveActivities.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            clip: true
            model: root.liveActivities

            delegate: Rectangle {
                required property var modelData
                readonly property bool canFocusWindow: modelData.kind === "update" || modelData.kind === "download"
                width: ListView.view.width
                height: 62
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.55))
                color: (canFocusWindow && laCardMa.containsMouse)
                    ? Qt.alpha(Theme.surfaceVariant, 0.72)
                    : Qt.alpha(Theme.surfaceVariant, 0.42)
                border.width: 1
                border.color: Qt.alpha(modelData.color || Theme.accent, (canFocusWindow && laCardMa.containsMouse) ? 0.65 : 0.32)

                MouseArea {
                    id: laCardMa
                    anchors.fill: parent
                    enabled: canFocusWindow
                    hoverEnabled: canFocusWindow
                    cursorShape: canFocusWindow ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        Theme.islandLiveActivityOpen = false
                        Quickshell.execDetached([
                            Quickshell.shellPath("core/as-core"), "live-activity",
                            "--focus", String(modelData.kind), String(modelData.pid || 0)
                        ])
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: modelData.color || Theme.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.title || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.bold: true
                                color: Theme.fg
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.subtitle || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                color: Qt.alpha(Theme.fg, 0.65)
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: String(modelData.etaText || "") !== ""
                            Layout.preferredWidth: etaBadgeTxt.implicitWidth + 12
                            Layout.preferredHeight: 20
                            radius: 6
                            color: Qt.alpha(modelData.color || Theme.accent, 0.16)

                            Text {
                                id: etaBadgeTxt
                                anchors.centerIn: parent
                                text: String(modelData.etaText || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                                color: modelData.color || Theme.accent
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "timer"
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            radius: 6
                            color: pauseMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.65)
                            Text {
                                anchors.centerIn: parent
                                text: modelData.paused ? "▶" : "⏸"
                                font.pixelSize: 10
                                color: Theme.fg
                            }
                            MouseArea {
                                id: pauseMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.togglePauseTimer()
                            }
                        }

                        Rectangle {
                            visible: modelData.kind === "record" || modelData.kind === "timer" || modelData.kind === "ipc"
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            radius: 6
                            color: stopMa.containsMouse ? Qt.alpha(Theme.error, 0.28) : Qt.alpha(Theme.surfaceVariant, 0.65)
                            Text {
                                anchors.centerIn: parent
                                text: "■"
                                font.pixelSize: 10
                                color: stopMa.containsMouse ? Theme.error : Theme.fg
                            }
                            MouseArea {
                                id: stopMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.kind === "record") {
                                        Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"])
                                    } else if (modelData.kind === "timer") {
                                        ShellState.stopTimer()
                                    } else if (modelData.kind === "ipc") {
                                        ShellState.handleLiveActivity("stop", modelData.id, "", -1)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: laBarTrack
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Qt.alpha(Theme.fg, 0.14)
                        clip: true

                        Rectangle {
                            height: parent.height
                            radius: 3
                            color: modelData.color || Theme.accent
                            readonly property real p: Number(modelData.progress)
                            width: p >= 0 ? Math.round(parent.width * Math.max(0, Math.min(100, p)) / 100.0) : Math.round(parent.width * 0.32)
                            x: p >= 0 ? 0 : laIndOff
                            property real laIndOff: 0
                            SequentialAnimation on laIndOff {
                                running: root.open && Number(modelData.progress) < 0
                                loops: Animation.Infinite
                                NumberAnimation { from: 0; to: Math.max(0, laBarTrack.width * 0.68); duration: 1050; easing.type: Easing.InOutSine }
                                NumberAnimation { from: Math.max(0, laBarTrack.width * 0.68); to: 0; duration: 1050; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
            }
        }
    }
}
