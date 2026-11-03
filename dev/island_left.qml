import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// ════════════════════════════════════════════════════════════════════════════
// LEFT ISLAND: APPLICATION LAUNCHER & HYPRLAND WORKSPACES (island_left.qml)
// ════════════════════════════════════════════════════════════════════════════
// Features:
//   • Application launcher shortcut (Fuzzel toggle)
//   • Permanent kanji workspaces 1..5 ("一", "二", "三", "四", "五")
//   • Dynamic workspace display for workspaces > 5 (when occupied or active)
//   • Visual occupation dot when windows exist on non-active workspaces
//   • Urgency indicator on alerts
//   • Mouse wheel scroll over island to cycle workspaces
//   • Dual Hyprland dispatch support (Lua hl.dsp.focus and legacy dispatch)
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandLeft
    implicitWidth: contentRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: WORKSPACE MODEL & STATE PROPERTIES
    // ────────────────────────────────────────────────────────────────────────
    // Permanent workspaces defined in ~/.config/hypr/hyprland.lua
    readonly property var permanentNames: ["一", "二", "三", "四", "五"]

    // Active workspace tracked live via Quickshell.Hyprland (with fallback to workspace_service.py)
    property int fallbackActiveId: 1
    readonly property int activeWorkspaceId: (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0)
        ? Hyprland.focusedWorkspace.id
        : fallbackActiveId

    // Map of workspaceId -> { windows: count, urgent: bool, occupied: bool, active: bool }
    property var wsStateMap: ({})

    // Visible workspaces: permanent 1..5 always shown + dynamic > 5 when active or occupied
    readonly property var visibleWorkspaces: {
        const list = [1, 2, 3, 4, 5]
        const extraIds = []
        const m = islandLeft.wsStateMap || ({})
        for (const k in m) {
            const id = parseInt(k, 10)
            if (id > 5 && (m[k].occupied || m[k].active || id === islandLeft.activeWorkspaceId)) {
                extraIds.push(id)
            }
        }
        if (islandLeft.activeWorkspaceId > 5 && extraIds.indexOf(islandLeft.activeWorkspaceId) < 0) {
            extraIds.push(islandLeft.activeWorkspaceId)
        }
        extraIds.sort((a, b) => a - b)
        return list.concat(extraIds)
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HELPER FUNCTIONS & HYPRLAND DISPATCH
    // ────────────────────────────────────────────────────────────────────────
    function wsLabel(wsId) {
        if (wsId >= 1 && wsId <= 5) return islandLeft.permanentNames[wsId - 1]
        if (wsId === 10) return "0"
        return String(wsId)
    }

    // Focus a workspace compatible with both Hyprland Lua (>=0.55) and legacy syntax
    function focusWorkspace(target) {
        if (Hyprland.usingLua) {
            const luaArg = (typeof target === "number") ? String(target) : ('"' + String(target) + '"')
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + luaArg + " })")
        } else {
            Hyprland.dispatch("workspace " + target)
        }
    }

    function refreshWorkspacesFromHyprland() {
        const nextMap = {}
        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            const list = Hyprland.workspaces.values
            for (let i = 0; i < list.length; i++) {
                const w = list[i]
                if (!w || w.id <= 0) continue
                nextMap[w.id] = {
                    active: w.active || w.focused || (w.id === activeWorkspaceId),
                    urgent: Boolean(w.urgent),
                    occupied: true
                }
            }
        }
        wsStateMap = nextMap
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: IPC & BACKGROUND WORKSPACE WATCHERS
    // ────────────────────────────────────────────────────────────────────────
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const ev = event.name
            if (ev.indexOf("workspace") >= 0 || ev.indexOf("window") >= 0 || ev === "urgent") {
                islandLeft.refreshWorkspacesFromHyprland()
                wsServiceProc.running = true
            }
        }
    }

    Process {
        id: wsServiceProc
        command: ["python3", Quickshell.shellPath("core/workspace_service.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text.trim())
                    if (typeof res.active === "number") {
                        islandLeft.fallbackActiveId = res.active
                    }
                    if (Array.isArray(res.details)) {
                        const m = Object.assign({}, islandLeft.wsStateMap)
                        for (let i = 0; i < res.details.length; i++) {
                            const d = res.details[i]
                            const prev = m[d.id] || {}
                            m[d.id] = {
                                active: d.active,
                                urgent: Boolean(prev.urgent),
                                occupied: (d.windows > 0),
                                windows: d.windows
                            }
                        }
                        islandLeft.wsStateMap = m
                    }
                } catch (e) {
                    // Ignore parse error if hyprctl is not running
                }
            }
        }
    }

    Component.onCompleted: {
        refreshWorkspacesFromHyprland()
        wsServiceProc.running = true
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: MAIN ISLAND VISUAL CONTAINER & CONTROLS
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.surfaceBg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: Theme.barMerged ? 0 : 1

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        // Scroll anywhere on the left island to switch to previous/next workspace
        WheelHandler {
            onWheel: event => {
                if (event.angleDelta.y > 0) {
                    islandLeft.focusWorkspace("e-1")
                } else if (event.angleDelta.y < 0) {
                    islandLeft.focusWorkspace("e+1")
                }
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Theme.space2

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 4.1: FUZZEL APPLICATION LAUNCHER BUTTON
            // ────────────────────────────────────────────────────────────────
            Rectangle {
                id: launcherBtn
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: launcherMa.containsMouse ? Theme.accentMuted : Theme.accent

                Behavior on color { ColorAnimation { duration: 150 } }

                Icon {
                    anchors.centerIn: parent
                    glyph: "arch"
                    size: Theme.iconSm
                    color: Theme.bg
                }

                MouseArea {
                    id: launcherMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "pkill fuzzel || fuzzel"])
                }
            }

            // Separator between launcher and workspaces
            Rectangle {
                width: 1
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceVariant
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 4.2: WORKSPACES REPEATER (Permanent + Dynamic)
            // ────────────────────────────────────────────────────────────────
            Row {
                id: workspaceRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: islandLeft.visibleWorkspaces

                    Rectangle {
                        id: wsDelegate
                        required property int modelData
                        readonly property int wsId: modelData
                        readonly property var st: islandLeft.wsStateMap[wsId] || ({})
                        readonly property bool isActive: islandLeft.activeWorkspaceId === wsId
                        readonly property bool isUrgent: Boolean(st.urgent)
                        readonly property bool isOccupied: Boolean(st.occupied) && (st.windows === undefined || st.windows > 0)

                        width: isActive ? 30 : 24
                        height: 24
                        radius: Theme.globalRadius

                        color: isUrgent
                            ? Theme.error
                            : isActive
                                ? Theme.accent
                                : wsMa.containsMouse
                                    ? Theme.surfaceVariant
                                    : isOccupied
                                        ? Qt.alpha(Theme.surfaceVariant, 0.75)
                                        : "transparent"

                        border.color: isUrgent
                            ? Theme.error
                            : isActive
                                ? Theme.accent
                                : isOccupied
                                    ? Theme.accentMuted
                                    : Theme.surfaceVariant
                        border.width: 1

                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: (wsDelegate.isOccupied && !wsDelegate.isActive) ? -2 : 0
                            text: islandLeft.wsLabel(wsDelegate.wsId)
                            color: (wsDelegate.isActive || wsDelegate.isUrgent)
                                ? Theme.bg
                                : wsDelegate.isOccupied
                                    ? Theme.fg
                                    : Qt.alpha(Theme.fg, 0.65)
                            font.pixelSize: Theme.textXs
                            font.bold: wsDelegate.isActive || wsDelegate.isOccupied
                        }

                        // Small occupation dot under kanji when workspace has windows but is not focused
                        Rectangle {
                            visible: wsDelegate.isOccupied && !wsDelegate.isActive
                            width: 4
                            height: 4
                            radius: 2
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Theme.accentMuted
                        }

                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandLeft.focusWorkspace(wsDelegate.wsId)
                        }
                    }
                }
            }
        }
    }
}
