import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Surface plein écran de la barre de capture (SUPER + SHIFT + S).
// Le lancement attend 340 ms que la pastille soit sortie pour ne pas figurer sur la capture.
Item {
    id: root
    required property var targetScreen
    property string pendingCapture: ""

    Component.onCompleted: {
        ShellState.captureHook = function(mode) { root.requestCapture(mode) }
    }

    Timer {
        id: captureLaunchTimer
        interval: 340
        onTriggered: {
            if (root.pendingCapture === "") return
            Quickshell.execDetached([
                "bash", Quickshell.shellPath("core/screenshot.sh"), root.pendingCapture
            ])
            root.pendingCapture = ""
        }
    }

    function requestCapture(mode) {
        if (mode === "record-stop") {
            Theme.screenshotPickerVisible = false
            Quickshell.execDetached([
                "bash", Quickshell.shellPath("core/screenshot.sh"), mode
            ])
            return
        }
        root.pendingCapture = mode
        Theme.screenshotPickerVisible = false
        captureLaunchTimer.restart()
    }

    PanelWindow {
        id: screenshotPickerWindow
        screen: root.targetScreen
        visible: Theme.screenshotPickerVisible || closeTimer.running
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Theme.screenshotPickerVisible
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-shotbar"

        property bool shown: false

        Timer { id: closeTimer; interval: 300 }

        Timer {
            id: openTimer
            interval: 40
            onTriggered: screenshotPickerWindow.shown = true
        }

        Connections {
            target: Theme
            function onScreenshotPickerVisibleChanged() {
                if (Theme.screenshotPickerVisible) {
                    closeTimer.stop()
                    openTimer.restart()
                    recordingCheckProc.running = true
                } else {
                    openTimer.stop()
                    screenshotPickerWindow.shown = false
                    closeTimer.restart()
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: Theme.screenshotPickerVisible
            Keys.onEscapePressed: Theme.screenshotPickerVisible = false
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Theme.screenshotPickerVisible = false
        }

        ScreenshotBar {
            id: shotBar
            anchors.verticalCenter: parent.verticalCenter
            x: screenshotPickerWindow.shown ? 18 : -(width + 24)
            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            onRegionRequested: root.requestCapture("region")
            onFullRequested: root.requestCapture("full")
            onRecordRegionRequested: root.requestCapture("record-region")
            onRecordFullRequested: root.requestCapture("record-full")
            onRecordStopRequested: root.requestCapture("record-stop")
        }

        Process {
            id: recordingCheckProc
            command: ["pgrep", "-x", "wf-recorder"]
            stdout: StdioCollector {
                onStreamFinished: shotBar.recording = String(text).trim().length > 0
            }
        }
    }
}
