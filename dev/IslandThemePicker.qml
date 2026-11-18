import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Sélecteur de jeu de couleurs inline de l'Îlot dynamique (SUPER + C).
Item {
    id: root
    property bool open: false
    property int fadeDuration: 240
    property int selectedIdx: 0

    anchors.fill: parent
    clip: true
    focus: root.open
    opacity: root.open ? 1.0 : 0.0
    visible: opacity > 0.05
    Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

    Keys.onEscapePressed: Theme.themePickerOpen = false
    Keys.onLeftPressed: root.handleNav("prev")
    Keys.onRightPressed: root.handleNav("next")
    Keys.onReturnPressed: root.handleNav("apply")

    Component.onCompleted: ShellState.themeNavHook = root.handleNav

    Process {
        id: themesScanProc
        command: ["python3", Quickshell.shellPath("core/themes_scan.py"), "--sync"]
    }

    function activate() {
        if (!themesScanProc.running) themesScanProc.running = true
        const list = Theme.paletteNoms || []
        const cur = list.indexOf(Theme.activeTheme)
        root.selectedIdx = cur >= 0 ? cur : 0
        themeListView.positionViewAtIndex(root.selectedIdx, ListView.Center)
        root.forceActiveFocus()
    }

    function applyScheme(nom) {
        if (!nom) return
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/theme_manager.py"), String(nom)])
        Theme.themePickerOpen = false
    }

    function handleNav(action) {
        const list = Theme.paletteNoms || []
        const n = list.length
        if (n <= 0) return
        if (action === "prev" || action === "left" || action === "gauche") {
            root.selectedIdx = (root.selectedIdx - 1 + n) % n
            themeListView.positionViewAtIndex(root.selectedIdx, ListView.Center)
        } else if (action === "next" || action === "right" || action === "droite") {
            root.selectedIdx = (root.selectedIdx + 1) % n
            themeListView.positionViewAtIndex(root.selectedIdx, ListView.Center)
        } else if (action === "apply" || action === "valider") {
            const idx = Math.max(0, Math.min(n - 1, root.selectedIdx))
            root.applyScheme(list[idx])
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
                text: "JEUX DE COULEURS"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.accent
            }

            Text {
                Layout.fillWidth: true
                text: (Theme.paletteNoms ? Theme.paletteNoms.length : 0) + " schémas"
                font.family: Theme.fontUi
                font.pixelSize: Theme.text2xs
                color: Qt.alpha(Theme.fg, 0.55)
            }

            Item {
                width: 22
                height: 22
                Icon {
                    anchors.centerIn: parent
                    glyph: "close"
                    size: 13
                    color: themeCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                    opacityLevel: 1
                }
                MouseArea {
                    id: themeCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.themePickerOpen = false
                }
            }
        }

        ListView {
            id: themeListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            model: Theme.paletteNoms || []

            WheelHandler {
                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                    themeListView.contentX = Math.max(0, Math.min(Math.max(0, themeListView.contentWidth - themeListView.width), themeListView.contentX - delta * 0.8))
                }
            }

            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property var pal: (Theme.paletteCouleurs && Theme.paletteCouleurs[modelData]) ? Theme.paletteCouleurs[modelData] : ({})
                readonly property string label: String((Theme.paletteEtiquettes && Theme.paletteEtiquettes[modelData]) || modelData)
                readonly property bool isCurrent: modelData === Theme.activeTheme
                readonly property bool isSelected: index === root.selectedIdx

                width: 172
                height: themeListView.height
                radius: Math.max(10, Math.round(Theme.globalRadius * 0.65))
                color: pal.bg ? Qt.alpha(String(pal.bg), 0.88) : Qt.alpha(Theme.surfaceVariant, 0.45)
                border.width: (isCurrent || isSelected || thCardMa.containsMouse) ? 2 : 1
                border.color: isCurrent
                    ? Theme.accent
                    : ((isSelected || thCardMa.containsMouse) ? String(pal.accent || Theme.accent) : Qt.alpha(Theme.fg, 0.14))

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item { Layout.fillHeight: true }

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        Repeater {
                            model: [
                                String(pal.bg || Theme.bg),
                                String(pal.surface || Theme.surface),
                                String(pal.accent || Theme.accent),
                                String(pal.accent_muted || Theme.accentMuted),
                                String(pal.fg || Theme.fg)
                            ]
                            delegate: Rectangle {
                                required property string modelData
                                width: 16
                                height: 16
                                radius: 8
                                color: modelData
                                border.width: 1
                                border.color: Qt.alpha("#ffffff", 0.22)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: label
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.bold: isCurrent || isSelected
                        color: String(pal.fg || Theme.fg)
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: isCurrent
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Actif"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                        color: String(pal.accent || Theme.accent)
                    }
                }

                MouseArea {
                    id: thCardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIdx = index
                    onClicked: {
                        root.selectedIdx = index
                        root.applyScheme(modelData)
                    }
                }
            }
        }
    }
}
