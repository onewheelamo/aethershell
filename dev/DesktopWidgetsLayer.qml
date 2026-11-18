import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Couche des widgets de bureau (`core/widgets.json`), mode placement et bandeau d'édition.
Item {
    id: root
    required property var targetScreen

    property var placingWindow: null
    property real placingX: 0
    property real placingY: 0
    property real placingGrabX: 0
    property real placingGrabY: 0
    property bool placingArmed: false
    readonly property bool placing: placingWindow !== null

    property var widgetWindows: []

    property string menuWidgetId: ""
    property real menuWidgetX: 0
    property real menuWidgetY: 0
    readonly property var menuWidget: {
        if (menuWidgetId === "") return ({})
        const l = ShellState.widgets || []
        for (let i = 0; i < l.length; ++i)
            if (String(l[i].id) === menuWidgetId) return l[i]
        return ({})
    }

    Component.onCompleted: {
        ShellState.placeWidgetHook = function() { root.startPlacementFromCursor() }
        ShellState.widgetMenuHook = function(id) {
            if (String(id) === "") { root.menuWidgetId = ""; return }
            const l = ShellState.widgets || []
            for (let i = 0; i < l.length; ++i) {
                if (String(l[i].id) !== String(id)) continue
                root.menuWidgetX = Number(l[i].x) || 0
                root.menuWidgetY = Number(l[i].y) || 0
                root.menuWidgetId = String(id)
                return
            }
        }
    }

    function widgetVisible(w) {
        if (!w || w.enabled === false) return false
        const brut = (w.workspaces && w.workspaces.length > 0)
            ? w.workspaces : [w.workspace]
        const liste = []
        for (let i = 0; i < brut.length; ++i) {
            const n = Number(brut[i])
            if (!isNaN(n)) liste.push(n)
        }
        if (liste.length === 0) return true
        if (liste.indexOf(0) >= 0) return true
        const ici = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1
        return liste.indexOf(ici) >= 0
    }

    function startPlacementFromCursor() {
        if (Theme.widgetsLocked) {
            if (placingWindow) endPlacement(false)
            return
        }
        if (placingWindow) { endPlacement(false); return }
        findWidgetProc.running = true
    }

    Process {
        id: findWidgetProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).trim().split(",")
                const cx = parseInt(parts[0], 10)
                const cy = parseInt(parts[1], 10)
                if (isNaN(cx) || isNaN(cy)) return
                for (let i = 0; i < root.widgetWindows.length; i++) {
                    const win = root.widgetWindows[i]
                    if (!win || !win.visible) continue
                    const wx = Number(win.w.x) || 0
                    const wy = Number(win.w.y) || 0
                    if (cx >= wx && cx <= wx + win.implicitWidth
                            && cy >= wy && cy <= wy + win.implicitHeight) {
                        root.beginPlacement(win, cx - wx, cy - wy)
                        return
                    }
                }
            }
        }
    }

    function beginPlacement(win, grabX, grabY) {
        placingWindow = win
        placingGrabX = grabX
        placingGrabY = grabY
        placingX = Number(win.w.x) || 0
        placingY = Number(win.w.y) || 0
        placingArmed = false
        placementArmTimer.restart()
    }

    function endPlacement(commit) {
        if (commit && placingWindow) {
            const fx = Theme.widgetsSnapGrid ? Math.round(placingX / 16) * 16 : Math.round(placingX)
            const fy = Theme.widgetsSnapGrid ? Math.round(placingY / 16) * 16 : Math.round(placingY)
            moveWidget(placingWindow.w.id, fx, fy)
        }
        placingWindow = null
    }

    Timer {
        id: placementArmTimer
        interval: 220
        onTriggered: root.placingArmed = true
    }

    Process { id: moveWidgetProc }

    function moveWidget(id, x, y) {
        if (!id) return
        moveWidgetProc.command = [
            "python3", Quickshell.shellPath("core/config_manager.py"),
            "widget_move", String(id), String(Math.round(x)), String(Math.round(y))
        ]
        moveWidgetProc.running = true
    }

    Variants {
        model: ShellState.widgets

        PanelWindow {
            id: widgetWindow
            required property var modelData
            readonly property var w: modelData || ({})

            screen: root.targetScreen
            visible: Theme.widgetsBureauVisibles && root.widgetVisible(w)
            anchors { top: true; left: true }

            property bool dragging: false
            property real dragStartX: 0
            property real dragStartY: 0
            property real liveX: Number(w.x) || 0
            property real liveY: Number(w.y) || 0
            readonly property bool isPlacing: root.placingWindow === widgetWindow
            margins.top: widgetWindow.isPlacing ? Math.round(root.placingY) : (Number(w.y) || 0)
            margins.left: widgetWindow.isPlacing ? Math.round(root.placingX) : (Number(w.x) || 0)
            readonly property int pad: 18
            readonly property bool hasOpacity: w.opacity !== undefined && w.opacity !== null
                                               && !isNaN(Number(w.opacity))
            readonly property real cardOpacity: hasOpacity
                ? Math.max(0, Math.min(1, Number(w.opacity))) : 0.35
            readonly property bool isTransparentStyle: String(w.style || "") === "transparent"
                || (!w.style && cardOpacity <= 0.01)
            readonly property bool isGlassStyle: !isTransparentStyle && cardOpacity > 0.01
            readonly property bool broken: widgetLoader.status === Loader.Error
            implicitWidth: (broken ? brokenText.implicitWidth : widgetLoader.implicitWidth) + pad * 2
            implicitHeight: (broken ? brokenText.implicitHeight : widgetLoader.implicitHeight) + pad * 2

            Component.onCompleted: {
                const list = root.widgetWindows.slice()
                list.push(widgetWindow)
                root.widgetWindows = list
            }
            Component.onDestruction: {
                const i = root.widgetWindows.indexOf(widgetWindow)
                if (i >= 0) {
                    const list = root.widgetWindows.slice()
                    list.splice(i, 1)
                    root.widgetWindows = list
                }
            }

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "shell-widget-" + (w.id || "x")

            Rectangle {
                id: carteWidget
                anchors.fill: parent
                radius: Theme.globalRadius
                color: "transparent"
                border.width: Theme.widgetsEditMode ? 2 : ((widgetWindow.isTransparentStyle || widgetWindow.w.border === false) ? 0 : 1)
                border.color: Theme.widgetsEditMode ? Theme.accent : Qt.alpha(Theme.accent, 0.16)

                SurfaceFloutee {
                    anchors.fill: parent
                    visible: widgetWindow.isGlassStyle
                    rayon: Theme.globalRadius
                    teinte: Qt.alpha(Theme.surface, widgetWindow.cardOpacity)
                    bordureLargeur: 0
                    actif: widgetWindow.isGlassStyle
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.menuWidgetX = Number(widgetWindow.w.x) || 0
                        root.menuWidgetY = Number(widgetWindow.w.y) || 0
                        root.menuWidgetId = String(widgetWindow.w.id || "")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    visible: Theme.widgetsEditMode
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.SizeAllCursor
                    onPressed: mouse => {
                        root.beginPlacement(widgetWindow,
                            (Number(widgetWindow.w.x) || 0) + mouse.x,
                            (Number(widgetWindow.w.y) || 0) + mouse.y)
                    }
                }

                Text {
                    id: brokenText
                    anchors.centerIn: parent
                    visible: widgetWindow.broken
                    text: "Widget « " + (widgetWindow.w.type || "?") + " » introuvable"
                    color: Qt.alpha(Theme.error, 0.9)
                    font.pixelSize: Theme.textXs
                }

                Loader {
                    id: widgetLoader
                    anchors.centerIn: parent
                    source: {
                        const t = widgetWindow.w.type
                        if (!t) return ""
                        const partages = ["deepseek", "ollama", "antigravity"]
                        return "widgets/" + (partages.indexOf(t) >= 0 ? "llm" : t) + ".qml"
                    }
                    onLoaded: {
                        if (item) {
                            item.options = widgetWindow.w.options || ({})
                            item.widgetId = widgetWindow.w.id || ""
                        }
                    }
                }

                Connections {
                    target: widgetWindow
                    function onWChanged() {
                        if (widgetLoader.item) {
                            widgetLoader.item.options = widgetWindow.w.options || ({})
                        }
                    }
                }

                Repeater {
                    model: Theme.widgetsEditMode ? 4 : 0
                    delegate: Rectangle {
                        required property int index
                        width: 7
                        height: 7
                        radius: 2
                        color: Theme.accent
                        anchors.top: (index < 2) ? parent.top : undefined
                        anchors.bottom: (index >= 2) ? parent.bottom : undefined
                        anchors.left: (index % 2 === 0) ? parent.left : undefined
                        anchors.right: (index % 2 === 1) ? parent.right : undefined
                        anchors.margins: -2
                    }
                }

                Rectangle {
                    visible: Theme.widgetsEditMode
                    z: 10
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    width: editToolsRow.implicitWidth + 8
                    height: 22
                    radius: 6
                    color: Qt.alpha(Theme.bg, 0.88)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, 0.55)

                    Row {
                        id: editToolsRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: decScaleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.pixelSize: 11; font.bold: true }
                            MouseArea {
                                id: decScaleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const cur = Number((widgetWindow.w.options && widgetWindow.w.options.text_scale) || 100)
                                    const nxt = Math.max(60, Math.round(cur - 10))
                                    Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "widget_set", String(widgetWindow.w.id), "text_scale", String(nxt)])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: incScaleMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 11; font.bold: true }
                            MouseArea {
                                id: incScaleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const cur = Number((widgetWindow.w.options && widgetWindow.w.options.text_scale) || 100)
                                    const nxt = Math.min(160, Math.round(cur + 10))
                                    Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "widget_set", String(widgetWindow.w.id), "text_scale", String(nxt)])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: styleTogMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                            Text { anchors.centerIn: parent; text: widgetWindow.isGlassStyle ? "◆" : "◇"; color: Theme.accent; font.pixelSize: 11 }
                            MouseArea {
                                id: styleTogMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const nxt = widgetWindow.isGlassStyle ? "transparent" : "glass"
                                    Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "widget_set", String(widgetWindow.w.id), "style", nxt])
                                }
                            }
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 4
                            color: delWidMa.containsMouse ? Qt.alpha(Theme.error, 0.28) : "transparent"
                            Text { anchors.centerIn: parent; text: "✕"; color: Theme.error; font.pixelSize: 10; font.bold: true }
                            MouseArea {
                                id: delWidMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "widget_remove", String(widgetWindow.w.id)])
                            }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: widgetsEditBanner
        screen: root.targetScreen
        visible: Theme.widgetsEditMode
        anchors { top: true }
        margins.top: Theme.barHeight + 14
        implicitWidth: editBannerRow.implicitWidth + 28
        implicitHeight: 36
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-whichkey"

        SurfaceFloutee {
            anchors.fill: parent
            rayon: Theme.pillRadius
            teinte: Theme.surfaceBg
            bordureCouleur: Theme.accent
            bordureLargeur: 1
            actif: true
        }

        Row {
            id: editBannerRow
            anchors.centerIn: parent
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ÉDITION WIDGETS"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.bold: true
                color: Theme.accent
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: bannerSnapTxt.implicitWidth + 14
                height: 22
                radius: 6
                color: Theme.widgetsSnapGrid ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)
                Text {
                    id: bannerSnapTxt
                    anchors.centerIn: parent
                    text: Theme.widgetsSnapGrid ? "Grille 16 px" : "Libre"
                    font.pixelSize: Theme.text2xs
                    color: Theme.widgetsSnapGrid ? Theme.accent : Theme.fg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.widgetsSnapGrid = !Theme.widgetsSnapGrid
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: bannerDoneTxt.implicitWidth + 16
                height: 22
                radius: 6
                color: Theme.accent
                Text {
                    id: bannerDoneTxt
                    anchors.centerIn: parent
                    text: "Terminer"
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                    color: Theme.bg
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.widgetsEditMode = false
                }
            }
        }
    }

    PanelWindow {
        id: placementCatcher
        visible: root.placing
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-widget-placement"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPositionChanged: mouse => {
                if (!root.placingWindow) return
                const maxX = parent.width - root.placingWindow.implicitWidth
                const maxY = parent.height - root.placingWindow.implicitHeight
                root.placingX = Math.max(0, Math.min(maxX, mouse.x - root.placingGrabX))
                root.placingY = Math.max(0, Math.min(maxY, mouse.y - root.placingGrabY))
            }

            onClicked: if (root.placingArmed) root.endPlacement(true)
            onWheel: if (root.placing) root.endPlacement(false)

            Keys.onEscapePressed: root.endPlacement(false)
            focus: true
        }
    }

    WidgetMenu {
        ouvert: root.menuWidgetId !== ""
        widget: root.menuWidget
        xEcran: root.menuWidgetX
        yEcran: root.menuWidgetY
        onFermer: root.menuWidgetId = ""
    }
}
