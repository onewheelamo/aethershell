import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."

// ══════════════════════════════════════════════════════════════════════
// VUE D'ENSEMBLE DES FENÊTRES — MISSION CONTROL (OverviewOverlay.qml)
// ══════════════════════════════════════════════════════════════════════
// Grille interactive des fenêtres ouvertes sur tous les bureaux Hyprland,
// avec filtre temps réel, navigation clavier, focus au clic gauche et
// fermeture au clic milieu / bouton ×.
// ══════════════════════════════════════════════════════════════════════

FocusScope {
    id: root

    property var clients: []
    signal closeRequested()
    signal refreshRequested()

    property string query: ""
    property int selectedIndex: 0

    readonly property var filteredClients: {
        const list = Array.isArray(clients) ? clients : []
        const q = query.trim().toLowerCase()
        const out = []
        for (let i = 0; i < list.length; i++) {
            const c = list[i]
            if (!c || !c.mapped) continue
            const title = String(c.title || "")
            const klass = String(c["class"] || c.initialClass || "")
            const wsName = (c.workspace && c.workspace.name) ? String(c.workspace.name) : ""
            const wsId = (c.workspace && c.workspace.id !== undefined) ? String(c.workspace.id) : ""
            const wsLbl = root.wsLabel(c)
            if (q !== "" && title.toLowerCase().indexOf(q) === -1
                && klass.toLowerCase().indexOf(q) === -1
                && wsName.toLowerCase().indexOf(q) === -1
                && wsId.toLowerCase().indexOf(q) === -1
                && wsLbl.toLowerCase().indexOf(q) === -1) {
                continue
            }
            out.push(c)
        }
        out.sort(function(a, b) {
            const wa = a.workspace ? Number(a.workspace.id) : 999
            const wb = b.workspace ? Number(b.workspace.id) : 999
            if (wa !== wb) return wa - wb
            const ax = (a.at && a.at.length > 0) ? Number(a.at[0]) : 0
            const bx = (b.at && b.at.length > 0) ? Number(b.at[0]) : 0
            return ax - bx
        })
        return out
    }

    onFilteredClientsChanged: {
        if (selectedIndex >= filteredClients.length) {
            selectedIndex = Math.max(0, filteredClients.length - 1)
        }
    }

    function findWaylandToplevel(address) {
        const key = ShellState.cleAdresse(address)
        if (!key) return null
        const tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (t && t.address && ShellState.cleAdresse(t.address) === key) {
                return t.wayland || null
            }
        }
        return null
    }

    function wsLabel(c) {
        if (!c || !c.workspace) return "?"
        const id = Number(c.workspace.id)
        const name = String(c.workspace.name || "")
        if (name === "special:scratchpad") return "Scratchpad"
        if (name === "special:minimized") return "Minimisée"
        if (id < 0) return name.replace("special:", "")
        return "Bureau " + id
    }

    function focusWindow(c) {
        if (!c || !c.address) return
        const addr = String(c.address)
        const wsName = (c.workspace && c.workspace.name) ? String(c.workspace.name) : ""
        const wsId = (c.workspace && c.workspace.id !== undefined) ? Number(c.workspace.id) : 0
        if (Hyprland.usingLua) {
            if (wsName === "special:scratchpad") {
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
            } else if (wsId > 0) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })")
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
            } else {
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
            }
        } else {
            if (wsName === "special:scratchpad") {
                Hyprland.dispatch("togglespecialworkspace scratchpad")
                Hyprland.dispatch("focuswindow address:" + addr)
            } else if (wsId > 0) {
                Hyprland.dispatch("workspace " + wsId)
                Hyprland.dispatch("focuswindow address:" + addr)
            } else {
                Hyprland.dispatch("focuswindow address:" + addr)
            }
        }
        root.closeRequested()
    }

    function closeWindow(c) {
        if (!c || !c.address) return
        const addr = String(c.address)
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + addr + '" })')
        } else {
            Hyprland.dispatch("closewindow address:" + addr)
        }
        refreshDelay.restart()
    }

    Timer {
        id: refreshDelay
        interval: 80
        repeat: false
        onTriggered: root.refreshRequested()
    }

    Keys.onEscapePressed: root.closeRequested()

    Component.onCompleted: {
        opacity = 1.0
        searchInput.forceActiveFocus()
    }

    opacity: 0.0
    Behavior on opacity { NumberAnimation { duration: Theme.panelAnimDuration; easing.type: Easing.OutCubic } }

    // Fond assombri — clic extérieur ferme l'overview
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.48)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    // Panneau central
    Item {
        id: cardContainer
        width: Math.min(parent.width - 80, 1080)
        height: Math.min(parent.height - 80, 720)
        anchors.centerIn: parent

        MouseArea {
            anchors.fill: parent
            // Absorbe les clics dans le panneau pour ne pas fermer via le fond
        }

        SurfaceFloutee {
            anchors.fill: parent
            rayon: Math.max(Theme.globalRadius, 18)
            teinte: Theme.surfaceBg
            bordureCouleur: Qt.alpha(Theme.accent, 0.45)
            bordureLargeur: 1
            actif: true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // En-tête + barre de recherche
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Icon {
                    glyph: "widgets"
                    size: Theme.iconMd
                    color: Theme.accent
                }

                Text {
                    text: "VUE D'ENSEMBLE"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textMd
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
                    color: Qt.alpha(Theme.surfaceVariant, 0.45)
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Icon {
                            glyph: "search"
                            size: Theme.iconSm
                            color: Qt.alpha(Theme.fg, 0.6)
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textSm
                            color: Theme.fg
                            selectByMouse: true
                            clip: true
                            onTextChanged: {
                                root.query = text
                                root.selectedIndex = 0
                            }
                            Keys.onEscapePressed: root.closeRequested()
                            Keys.onReturnPressed: {
                                if (root.filteredClients.length > 0) {
                                    root.focusWindow(root.filteredClients[root.selectedIndex])
                                }
                            }
                            Keys.onRightPressed: if (root.filteredClients.length > 0) root.selectedIndex = (root.selectedIndex + 1) % root.filteredClients.length
                            Keys.onLeftPressed: if (root.filteredClients.length > 0) root.selectedIndex = (root.selectedIndex - 1 + root.filteredClients.length) % root.filteredClients.length
                            Keys.onDownPressed: if (root.filteredClients.length > 0) root.selectedIndex = Math.min(root.filteredClients.length - 1, root.selectedIndex + 3)
                            Keys.onUpPressed: if (root.filteredClients.length > 0) root.selectedIndex = Math.max(0, root.selectedIndex - 3)

                            Text {
                                visible: searchInput.text === ""
                                text: "Filtrer par titre, application ou bureau…"
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textSm
                                color: Qt.alpha(Theme.fg, 0.42)
                            }
                        }
                    }
                }

                Text {
                    text: root.filteredClients.length + " fenêtre" + (root.filteredClients.length > 1 ? "s" : "")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Qt.alpha(Theme.fg, 0.6)
                }

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: closeBtnMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: closeBtnMa.containsMouse ? Theme.error : Theme.fg
                    }

                    MouseArea {
                        id: closeBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(Theme.fg, 0.1)
            }

            // Grille des fenêtres
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    visible: root.filteredClients.length === 0
                    anchors.centerIn: parent
                    text: "Aucune fenêtre correspondante"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    color: Qt.alpha(Theme.fg, 0.5)
                }

                Flickable {
                    id: gridFlick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: winGrid.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: winGrid
                    width: gridFlick.width
                    columns: Math.max(1, Math.floor((width + 12) / 320))
                    spacing: 12

                    Repeater {
                        model: root.filteredClients

                        delegate: Rectangle {
                            id: cardDelegate
                            required property var modelData
                            required property int index
                            readonly property bool selected: index === root.selectedIndex
                            readonly property var waylandToplevel: root.findWaylandToplevel(modelData.address)
                            width: (winGrid.width - (winGrid.columns - 1) * winGrid.spacing) / winGrid.columns
                            height: 236
                            radius: Math.max(10, Math.round(Theme.globalRadius * 0.7))
                            color: selected
                                ? Qt.alpha(Theme.accent, cardMa.containsMouse ? 0.24 : 0.16)
                                : (cardMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.6) : Qt.alpha(Theme.surfaceVariant, 0.36))
                            border.width: selected ? 1.5 : 1
                            border.color: selected ? Theme.accent : Qt.alpha(Theme.fg, 0.1)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = index
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) {
                                        root.closeWindow(modelData)
                                    } else {
                                        root.focusWindow(modelData)
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredWidth: wsBadgeTxt.implicitWidth + 12
                                        Layout.preferredHeight: 20
                                        radius: 6
                                        color: Qt.alpha(Theme.accent, 0.18)

                                        Text {
                                            id: wsBadgeTxt
                                            anchors.centerIn: parent
                                            text: root.wsLabel(modelData)
                                            font.family: Theme.fontUi
                                            font.pixelSize: Theme.text2xs
                                            font.weight: Font.Bold
                                            color: Theme.accent
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: String(modelData["class"] || modelData.initialClass || "Application")
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.textXs
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: 6
                                        color: winCloseMa.containsMouse ? Qt.alpha(Theme.error, 0.25) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: winCloseMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                                        }

                                        MouseArea {
                                            id: winCloseMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeWindow(modelData)
                                        }
                                    }
                                }

                                // Miniature en direct de la fenêtre (Wayland screencopy)
                                Rectangle {
                                    id: thumbBox
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 8
                                    clip: true
                                    color: Qt.alpha(Theme.bg, 0.58)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.fg, 0.08)

                                    ScreencopyView {
                                        id: thumbView
                                        anchors.centerIn: parent
                                        readonly property real maxW: Math.max(1, thumbBox.width - 4)
                                        readonly property real maxH: Math.max(1, thumbBox.height - 4)
                                        readonly property bool hasDim: hasContent && sourceSize.width > 0 && sourceSize.height > 0
                                        width: hasDim ? Math.min(maxW, maxH * sourceSize.width / sourceSize.height) : maxW
                                        height: hasDim ? Math.min(maxH, maxW * sourceSize.height / sourceSize.width) : maxH
                                        captureSource: cardDelegate.waylandToplevel
                                        live: true
                                        paintCursor: false
                                        constraintSize: Qt.size(Math.max(1, thumbBox.width), Math.max(1, thumbBox.height))
                                        visible: captureSource !== null && hasContent
                                    }

                                    Icon {
                                        visible: !thumbView.visible
                                        anchors.centerIn: parent
                                        glyph: "widgets"
                                        size: 28
                                        color: Qt.alpha(Theme.fg, 0.28)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: String(modelData.title || "")
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.textXs
                                        color: Qt.alpha(Theme.fg, 0.82)
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: Boolean(modelData.floating) || Number(modelData.fullscreen || 0) > 0
                                        text: (Number(modelData.fullscreen || 0) > 0 ? "Plein écran" : "Flottante")
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.text2xs
                                        color: Qt.alpha(Theme.fg, 0.5)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
