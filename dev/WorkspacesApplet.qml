import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET WORKSPACES — les bureaux Hyprland, leur occupation, leur urgence.
//
// Composant QML (`genre: "qml"`). Il emporte avec lui tout ce qui le faisait
// vivre : le modèle des bureaux, les envois à Hyprland, l'écoute des événements,
// le repli sur `workspace_service.py` et la molette. Déplacé dans ce fichier,
// il garde exactement le même rendu — mais l'îlot gauche n'est plus qu'un
// conteneur, et l'applet peut être posé dans n'importe quel îlot.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    implicitWidth: workspaceRow.implicitWidth
    implicitHeight: workspaceRow.implicitHeight

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
        const m = root.wsStateMap || ({})
        for (const k in m) {
            const id = parseInt(k, 10)
            if (id > 5 && (m[k].occupied || m[k].active || id === root.activeWorkspaceId)) {
                extraIds.push(id)
            }
        }
        if (root.activeWorkspaceId > 5 && extraIds.indexOf(root.activeWorkspaceId) < 0) {
            extraIds.push(root.activeWorkspaceId)
        }
        extraIds.sort((a, b) => a - b)
        return list.concat(extraIds)
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HELPER FUNCTIONS & HYPRLAND DISPATCH
    // ────────────────────────────────────────────────────────────────────────
    function wsLabel(wsId) {
        if (wsId >= 1 && wsId <= 5) return root.permanentNames[wsId - 1]
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
        // Occupation réelle : le nombre de toplevels par workspace. La version
        // précédente marquait `occupied: true` pour tout workspace présent dans
        // Hyprland.workspaces, sans clé `windows` — or le délégué considère
        // « occupé » dès que `windows` est absent. Hyprland liste brièvement les
        // workspaces qu'il vient de créer ou de quitter : d'où le point qui
        // clignotait sous un bureau vide pendant un changement de workspace.
        const counts = {}
        if (Hyprland.toplevels && Hyprland.toplevels.values) {
            const tops = Hyprland.toplevels.values
            for (let i = 0; i < tops.length; i++) {
                const t = tops[i]
                const wid = (t && t.workspace) ? t.workspace.id : -1
                if (wid > 0)
                    counts[wid] = (counts[wid] || 0) + 1
            }
        }

        const nextMap = {}
        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            const list = Hyprland.workspaces.values
            for (let i = 0; i < list.length; i++) {
                const w = list[i]
                if (!w || w.id <= 0) continue
                const prev = (wsStateMap || {})[w.id]
                // Le modèle des toplevels est la source fiable ; à défaut on garde
                // le dernier compte connu plutôt que d'inventer « occupé ».
                const n = (counts[w.id] !== undefined)
                    ? counts[w.id]
                    : (prev && prev.windows !== undefined ? prev.windows : 0)
                nextMap[w.id] = {
                    active: w.active || w.focused || (w.id === activeWorkspaceId),
                    urgent: Boolean(w.urgent),
                    occupied: n > 0,
                    windows: n
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
                root.refreshWorkspacesFromHyprland()
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
                        root.fallbackActiveId = res.active
                    }
                    if (Array.isArray(res.details)) {
                        const m = Object.assign({}, root.wsStateMap)
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
                        root.wsStateMap = m
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


            Row {
                id: workspaceRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: root.visibleWorkspaces

                    Rectangle {
                        id: wsDelegate
                        required property int modelData
                        readonly property int wsId: modelData
                        readonly property var st: root.wsStateMap[wsId] || ({})
                        readonly property bool isActive: root.activeWorkspaceId === wsId
                        readonly property bool isUrgent: Boolean(st.urgent)
                        readonly property bool isOccupied: Boolean(st.occupied) && (st.windows === undefined || st.windows > 0)

                        width: isActive ? 30 : 24
                        height: 24
                        radius: Theme.globalRadius

                        readonly property bool outlineActive: isActive && Theme.wsActiveOutline

                        color: isUrgent
                            ? Theme.error
                            : outlineActive
                                ? "transparent"
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
                        border.width: outlineActive ? 0 : 1

                        // Liseré dégradé du workspace actif : trait de 1,5 px accent → transparent.
                        // Un Canvas plutôt que deux Rectangles imbriqués, pour ne pas superposer
                        // deux surfaces translucides (l'intérieur doublerait l'opacité).
                        Canvas {
                            id: wsOutline
                            anchors.fill: parent
                            visible: wsDelegate.outlineActive
                            antialiasing: true

                            onPaint: {
                                const ctx = getContext("2d")
                                const w = width
                                const h = height
                                const i = 0.75
                                // Rayon borné par les DEUX dimensions, sinon les côtés
                                // droits deviennent des segments de longueur négative et
                                // QML dessine deux ergots verticaux de chaque côté.
                                const r = Math.max(0.5, Math.min(wsDelegate.radius, (w - 2 * i) / 2, (h - 2 * i) / 2))
                                ctx.reset()
                                const grad = ctx.createLinearGradient(0, 0, w, 0)
                                grad.addColorStop(0, Qt.alpha(Theme.accent, 0.95))
                                grad.addColorStop(1, Qt.alpha(Theme.accent, 0.30))
                                ctx.strokeStyle = grad
                                ctx.lineWidth = 1.5
                                ctx.beginPath()
                                ctx.moveTo(i + r, i)
                                ctx.lineTo(w - i - r, i)
                                ctx.quadraticCurveTo(w - i, i, w - i, i + r)
                                ctx.lineTo(w - i, h - i - r)
                                ctx.quadraticCurveTo(w - i, h - i, w - i - r, h - i)
                                ctx.lineTo(i + r, h - i)
                                ctx.quadraticCurveTo(i, h - i, i, h - i - r)
                                ctx.lineTo(i, i + r)
                                ctx.quadraticCurveTo(i, i, i + r, i)
                                ctx.closePath()
                                ctx.stroke()
                            }

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            Connections {
                                target: Theme
                                function onAccentChanged() { wsOutline.requestPaint() }
                            }
                        }

                        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: (wsDelegate.isOccupied && !wsDelegate.isActive) ? -2 : 0
                            text: root.wsLabel(wsDelegate.wsId)
                            color: (wsDelegate.isUrgent || (wsDelegate.isActive && !wsDelegate.outlineActive))
                                ? Theme.bg
                                : wsDelegate.isActive
                                    ? Theme.accent
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
                            onClicked: {
                                root.focusWorkspace(wsDelegate.wsId)
                            }
                        }
                    }
                }
            }

    // La molette sur l'applet passe d'un bureau à l'autre (elle était sur l'îlot).
    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y > 0) root.focusWorkspace("e-1")
            else if (event.angleDelta.y < 0) root.focusWorkspace("e+1")
        }
    }
}
