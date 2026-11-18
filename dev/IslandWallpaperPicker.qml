import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Sélecteur de fonds d'écran inline de l'Îlot dynamique (SUPER + W).
Item {
    id: root
    property bool open: false
    property int fadeDuration: 240
    property var wallpaperList: []
    property int selectedIdx: 0

    anchors.fill: parent
    clip: true
    focus: root.open
    opacity: root.open ? 1.0 : 0.0
    visible: opacity > 0.05
    Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: Theme.wallpaperPickerOpen = false
    Keys.onLeftPressed: root.handleNav("prev")
    Keys.onRightPressed: root.handleNav("next")
    Keys.onReturnPressed: root.handleNav("apply")

    Component.onCompleted: ShellState.wallpaperNavHook = root.handleNav

    Process {
        id: wallpaperScanProc
        command: [
            "python3", "-c",
            "import os, json\n"
            + "d = os.environ.get('QS_WP_DIR', '').strip() or os.path.expanduser('~/Images/wallpapers')\n"
            + "d = os.path.expanduser(os.path.expandvars(d))\n"
            + "exts = {'.png', '.jpg', '.jpeg', '.webp', '.avif'}\n"
            + "out = []\n"
            + "if os.path.isdir(d):\n"
            + "    for fn in sorted(os.listdir(d)):\n"
            + "        p = os.path.join(d, fn)\n"
            + "        if os.path.isfile(p) and os.path.splitext(fn)[1].lower() in exts:\n"
            + "            out.append({'path': p, 'name': os.path.splitext(fn)[0]})\n"
            + "print(json.dumps(out))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text.trim())
                    root.wallpaperList = Array.isArray(arr) ? arr : []
                    let curIdx = 0
                    for (let i = 0; i < root.wallpaperList.length; i++) {
                        if (root.wallpaperList[i].path === ShellState.wallpaperCourant) {
                            curIdx = i
                            break
                        }
                    }
                    root.selectedIdx = curIdx
                } catch (e) {
                    root.wallpaperList = []
                }
            }
        }
    }

    function activate() {
        wallpaperScanProc.environment = ({ "QS_WP_DIR": Theme.wallpaperDir || "" })
        if (!wallpaperScanProc.running) wallpaperScanProc.running = true
        root.forceActiveFocus()
    }

    function applyWallpaper(path) {
        if (!path) return
        ShellState.setWallpaperCourant(String(path))
        Quickshell.execDetached(["bash", Quickshell.shellPath("hyprquickpaper/commands.sh"), String(path)])
        Theme.wallpaperPickerOpen = false
    }

    function handleNav(action) {
        const n = root.wallpaperList.length
        if (n <= 0) return
        if (action === "prev" || action === "left" || action === "gauche") {
            root.selectedIdx = (root.selectedIdx - 1 + n) % n
            wpListView.positionViewAtIndex(root.selectedIdx, ListView.Contain)
        } else if (action === "next" || action === "right" || action === "droite") {
            root.selectedIdx = (root.selectedIdx + 1) % n
            wpListView.positionViewAtIndex(root.selectedIdx, ListView.Contain)
        } else if (action === "apply" || action === "valider") {
            const idx = Math.max(0, Math.min(n - 1, root.selectedIdx))
            root.applyWallpaper(root.wallpaperList[idx].path)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Icon {
                glyph: "palette"
                size: Theme.iconSm
                color: Theme.accent
            }

            Text {
                text: "FONDS D'ÉCRAN"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.accent
            }

            Text {
                Layout.fillWidth: true
                text: root.wallpaperList.length + " image" + (root.wallpaperList.length > 1 ? "s" : "")
                font.family: Theme.fontUi
                font.pixelSize: Theme.text2xs
                color: Qt.alpha(Theme.fg, 0.55)
            }

            Rectangle {
                visible: root.wallpaperList.length > 1
                Layout.preferredWidth: wpRandLbl.implicitWidth + 16
                Layout.preferredHeight: 22
                radius: 6
                color: wpRandMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                Text {
                    id: wpRandLbl
                    anchors.centerIn: parent
                    text: "Aléatoire"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.weight: Font.DemiBold
                    color: wpRandMa.containsMouse ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: wpRandMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const idx = Math.floor(Math.random() * root.wallpaperList.length)
                        root.selectedIdx = idx
                        wpListView.positionViewAtIndex(idx, ListView.Center)
                        root.applyWallpaper(root.wallpaperList[idx].path)
                    }
                }
            }

            Item {
                width: 22
                height: 22
                Icon {
                    anchors.centerIn: parent
                    glyph: "close"
                    size: 13
                    color: wpCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                    opacityLevel: 1
                }
                MouseArea {
                    id: wpCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.wallpaperPickerOpen = false
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                visible: root.wallpaperList.length === 0
                anchors.centerIn: parent
                text: "Aucune image trouvée dans le dossier des fonds d'écran"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.55)
            }

            ListView {
                id: wpListView
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                visible: root.wallpaperList.length > 0
                model: root.wallpaperList

                WheelHandler {
                    onWheel: event => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        wpListView.contentX = Math.max(0, Math.min(Math.max(0, wpListView.contentWidth - wpListView.width), wpListView.contentX - delta * 0.8))
                    }
                }

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: modelData.path === ShellState.wallpaperCourant
                    readonly property bool isSelected: index === root.selectedIdx
                    width: 212
                    height: wpListView.height
                    radius: Math.max(8, Math.round(Theme.globalRadius * 0.65))
                    color: Qt.alpha(Theme.surfaceVariant, 0.4)
                    border.width: (isCurrent || isSelected || wpCardMa.containsMouse) ? 2 : 1
                    border.color: isCurrent
                        ? Theme.accent
                        : ((isSelected || wpCardMa.containsMouse) ? Qt.alpha(Theme.accent, 0.65) : Qt.alpha(Theme.fg, 0.12))
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: "file://" + modelData.path
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 290
                        sourceSize.height: 180
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 22
                        color: Qt.alpha(Theme.bg, 0.72)

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.name
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.bold: isCurrent
                            color: isCurrent ? Theme.accent : Theme.fg
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: wpCardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIdx = index
                        onClicked: {
                            root.selectedIdx = index
                            root.applyWallpaper(modelData.path)
                        }
                    }
                }
            }
        }
    }
}
