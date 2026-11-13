import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 5 DE L'ÎLOT : APPARENCE & DISPOSITION (icône palette)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property bool themesExpanded: false
    readonly property var tousThemes: (Theme.paletteNoms && Theme.paletteNoms.length > 0)
        ? Theme.paletteNoms : ["dynamic", "catppuccin"]
    readonly property var themesAffiches: themesExpanded
        ? tousThemes : tousThemes.slice(0, 6)

    Process {
        id: cfgProc
    }

    Process {
        id: themesScanProc
        command: ["python3", Quickshell.shellPath("core/themes_scan.py"), "--sync"]
        running: true
    }

    function runStyle(key, val) {
        cfgProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"), "style", String(key), String(val)]
        cfgProc.running = true
    }

    function applyPreset(name) {
        const nom = String(name)
        Theme.activeTheme = nom
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/theme_manager.py"), nom])
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainCol
            width: flick.width
            height: Math.max(flick.height, implicitHeight)
            spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "APPARENCE & DISPOSITION"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }
            Text {
                text: "Réglages visuels immédiats du shell."
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.6)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Thème & fond d'écran
        Text {
            text: "THÈME & FOND D'ÉCRAN"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.themesAffiches
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool active: Theme.activeTheme === modelData
                    readonly property string libelle: String(Theme.paletteEtiquettes[modelData]
                                                              || modelData.replace(/^kde-/, ""))
                    width: Math.max(82, Math.floor((mainCol.width - 12) / 3))
                    height: 28
                    radius: 8
                    color: active ? Qt.alpha(Theme.accent, 0.28)
                         : (preMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.65) : Qt.alpha(Theme.surfaceVariant, 0.4))
                    border.width: 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: parent.libelle
                        font.capitalization: Font.Capitalize
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: parent.active ? Font.Bold : Font.Normal
                        color: parent.active ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: preMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyPreset(parent.modelData)
                    }
                }
            }
        }

        Rectangle {
            visible: root.tousThemes.length > 6
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            radius: 6
            color: moreMa.containsMouse ? Qt.alpha(Theme.accent, 0.16) : Qt.alpha(Theme.surfaceVariant, 0.25)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            Text {
                anchors.centerIn: parent
                text: root.themesExpanded
                    ? "▴ Réduire les thèmes"
                    : "▾ Afficher tous les thèmes (" + root.tousThemes.length + ")"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.8)
            }

            MouseArea {
                id: moreMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.themesExpanded = !root.themesExpanded
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: wpMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.3)

            Text {
                anchors.centerIn: parent
                text: "🖼️  Changer de fond d'écran (SUPER+W)"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.DemiBold
                color: Theme.fg
            }

            MouseArea {
                id: wpMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Theme.islandPanelOpen = false
                    Quickshell.execDetached(["quickshell", "-n", "-p", Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"])
                }
            }
        }

        // Disposition de la barre
        Text {
            text: "DISPOSITION DE LA BARRE"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { key: "classic", label: "Barre classique" },
                    { key: "island", label: "Îlot dynamique" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: Theme.barStyle === modelData.key
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: active ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.surfaceVariant, 0.34)
                    border.width: 1
                    border.color: active ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: (active ? "✓ " : "") + parent.modelData.label
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: active ? Font.Bold : Font.Normal
                        color: active ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.runStyle("bar_style", parent.modelData.key)
                            Theme.barStyle = parent.modelData.key
                        }
                    }
                }
            }
        }

        // Surfaces & verre
        Text {
            text: "SURFACES & VERRE"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
        }

        // Opacité
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 72
                text: "Opacité"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.14)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (Theme.shellOpacity - 0.3) / 0.7))
                        height: parent.height
                        radius: 2.5
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setOp(mx) {
                        let v = 0.3 + Math.max(0, Math.min(1, mx / width)) * 0.7
                        v = Math.round(v * 20) / 20
                        Theme.shellOpacity = v
                        root.runStyle("shell_opacity", v.toFixed(2))
                    }
                    onPressed: mouse => setOp(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setOp(mouse.x) }
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: Math.round(Theme.shellOpacity * 100) + " %"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
        }

        // Arrondis
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 72
                text: "Arrondis"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Theme.fg, 0.14)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, (Theme.globalRadius - 4) / 20))
                        height: parent.height
                        radius: 2.5
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function setRad(mx) {
                        let r = Math.round(4 + Math.max(0, Math.min(1, mx / width)) * 20)
                        Theme.globalRadius = r
                        root.runStyle("global_radius", r)
                    }
                    onPressed: mouse => setRad(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setRad(mouse.x) }
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: Theme.globalRadius + " px"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.fg
            }
        }

        Item { Layout.fillHeight: true }

        // Bouton ouvrir panneau complet
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            radius: 10
            color: fullCfgMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.22)
            border.width: 1
            border.color: Theme.accent

            Text {
                anchors.centerIn: parent
                text: "⚙️  Ouvrir tous les réglages (SUPER+H)"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textSm
                font.weight: Font.Bold
                color: fullCfgMa.containsMouse ? Theme.bg : Theme.fg
            }

            MouseArea {
                id: fullCfgMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Theme.islandPanelOpen = false
                    Theme.configPanelVisible = true
                }
            }
        }
        }
    }
}
