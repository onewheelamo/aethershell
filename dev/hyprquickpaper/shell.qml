import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt.labs.folderlistmodel

// HyprQuickPaper-style wallpaper selector for the shell.
// Wallpaper directory is NOT read from config.json here: it comes from the
// main shell's core/style_vars.json (single source of truth, editable from
// the config panel). config.json only provides display/thumbnail settings.
PanelWindow {
    id: main

    // UI scaling relative to a 1080p reference height
    readonly property real ui: Screen.height / 1080

    // Display settings (fallback values; config.json overrides them)
    property int tileCount: 6
    property real tileHeightRef: 500
    property string cacheDir: Quickshell.env("HOME") + "/.cache/quickshell/hyprquickpaper/"
    property color frameColor: "#b4befe"

    // Resolved at runtime from core/style_vars.json (with config.json fallback)
    property string wallpaperDir: ""
    property string fallbackDir: Quickshell.env("HOME") + "/Images/wallpapers/"
    readonly property string effectiveDir: wallpaperDir !== "" ? wallpaperDir : fallbackDir

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    implicitWidth: Screen.width
    implicitHeight: Screen.height
    color: Qt.alpha("#000000", 0.65)
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "hyprquickpaper"

    // Launch animation
    property real intro: 0
    NumberAnimation on intro {
        from: 0; to: 1
        duration: 280
        easing.type: Easing.OutCubic
        running: true
    }

    Component.onCompleted: {
        Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])
        styleFile.reload()
    }

    // Single source of truth: the main shell's style_vars.json
    FileView {
        id: styleFile
        path: Quickshell.env("HOME") + "/.config/quickshell/core/style_vars.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                const dir = parsed.wallpaper_dir || ""
                if (dir) {
                    main.wallpaperDir = dir
                        .replace("$HOME", Quickshell.env("HOME"))
                        .replace(/^~/, Quickshell.env("HOME"))
                }
            } catch (e) {
                console.warn("hyprquickpaper: could not parse style_vars.json:", e)
            }
        }
    }

    // Display settings fallback (also used for cache_path / tile count)
    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text())
                if (typeof c.wallpaper_path === "string" && c.wallpaper_path !== "")
                    main.fallbackDir = c.wallpaper_path.replace("$HOME", Quickshell.env("HOME"))
                if (typeof c.number_of_pictures === "number" && c.number_of_pictures > 0)
                    main.tileCount = c.number_of_pictures
                if (typeof c.height === "number" && c.height > 0)
                    main.tileHeightRef = c.height
                if (typeof c.cache_path === "string" && c.cache_path !== "")
                    main.cacheDir = c.cache_path
                        .replace("$HOME", Quickshell.env("HOME"))
                        .replace(/^~/, Quickshell.env("HOME")) + "/"
            } catch (e) {
                console.warn("hyprquickpaper: could not parse config.json:", e)
            }
        }
    }

    // Matugen-synced frame color (colors.json), fallback to frameColor
    FileView {
        path: Quickshell.shellPath("colors.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text())
                if (typeof c.border_color === "string"
                        && c.border_color !== "transparent" && c.border_color !== "")
                    main.frameColor = c.border_color
            } catch (e) { /* keep default */ }
        }
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + main.effectiveDir
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Name
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: Qt.quit()
    }

    // Empty-state message after a short delay (lets the model populate first)
    Timer {
        id: emptyTimer
        interval: 400
        onTriggered: emptyState.visible = folderModel.status === FolderListModel.Ready && folderModel.count === 0
    }
    Connections {
        target: folderModel
        function onStatusChanged() { if (folderModel.status === FolderListModel.Ready) emptyTimer.restart() }
    }
    Column {
        id: emptyState
        anchors.centerIn: parent
        spacing: 10 * main.ui
        z: 2
        visible: false
        opacity: main.intro
        Text {
            text: "Aucun fond d'écran trouvé"
            color: "#ffffff"
            font.pixelSize: 22 * main.ui
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "Dossier inspecté (modifiable dans le panneau de configuration) :"
            color: "#aaaaaa"
            font.pixelSize: 13 * main.ui
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: main.effectiveDir
            color: "#dddddd"
            font.pixelSize: 14 * main.ui
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    ListView {
        id: carousel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: tileH
        z: 1
        focus: true
        model: folderModel
        orientation: ListView.Horizontal
        clip: true
        cacheBuffer: 600 * main.ui
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0

        opacity: main.intro
        scale: 0.96 + 0.04 * main.intro
        transformOrigin: Item.Center

        property int selected: 0
        property bool started: false
        readonly property real tileH: main.tileHeightRef * main.ui
        readonly property real tileW: (main.width / Math.max(1, main.tileCount)) - 12 * main.ui
        readonly property real centerX: width / 2
        readonly property real falloff: width / 2

        leftMargin: Math.max(0, centerX - tileW / 2)
        rightMargin: leftMargin

        function clampIndex(i) { return Math.max(0, Math.min(i, count - 1)) }
        function xFor(i) {
            const it = itemAtIndex(i)
            return it ? it.x + it.width / 2 - width / 2 : i * tileW - leftMargin
        }
        function centerOn(i, animate) {
            if (animate === undefined) animate = true
            if (!animate) jumpGuard = true
            contentX = xFor(i)
            if (!animate) jumpGuard = false
        }
        property bool jumpGuard: false
        function pick(i) {
            selected = clampIndex(i)
            centerOn(selected)
        }
        function choose() {
            if (count <= 0) return
            const path = folderModel.get(selected, "filePath")
            Quickshell.execDetached(["bash", Quickshell.shellPath("commands.sh"), path])
            Qt.quit()
        }

        Behavior on contentX {
            enabled: carousel.started && !carousel.jumpGuard
            SmoothedAnimation { duration: 450; velocity: 4000 }
        }
        onCountChanged: if (count > 0 && !started) { started = true; centerOn(0, false) }
        onWidthChanged: if (started && count > 0) centerOn(selected, false)

        delegate: Item {
            id: tile
            width: carousel.tileW
            height: carousel.tileH

            readonly property bool active: index === carousel.selected
            readonly property real dist: Math.abs(x - carousel.contentX + width / 2 - carousel.centerX)
            readonly property real frac: Math.min(1, dist / carousel.falloff)
            readonly property real s: 1 - frac * frac * 0.35   // center full size, edges ~65%

            Item {
                id: content
                anchors.verticalCenter: parent.verticalCenter
                width: tile.width * tile.s
                height: tile.height * tile.s
                x: (tile.width - width) / 2

                Rectangle {   // frame for the selected tile
                    anchors.fill: parent
                    color: "transparent"
                    border.width: Math.max(1, Math.round(2 * main.ui))
                    border.color: main.frameColor
                    radius: 4 * main.ui
                    visible: tile.active
                    z: 10
                }
                Image {
                    id: thumb
                    anchors.fill: parent
                    source: "file://" + main.cacheDir + fileName
                    sourceSize.width: tile.width
                    sourceSize.height: tile.height
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    opacity: tile.active ? 1.0 : 0.75
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Timer {
                        id: retry
                        interval: 800
                        repeat: false
                        onTriggered: { const s = thumb.source; thumb.source = ""; thumb.source = s }
                    }
                    onStatusChanged: if (status === Image.Error) retry.restart()
                }
                Text {   // placeholder while the thumbnail is being generated
                    anchors.centerIn: parent
                    visible: thumb.status === Image.Error || thumb.status === Image.Loading
                    text: fileName
                    color: "#cccccc"
                    font.pixelSize: 12 * main.ui
                    elide: Text.ElideMiddle
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: content   // only the visible thumbnail is clickable/hoverable
                hoverEnabled: true
                // Hover only moves the highlight — never scrolls the carousel.
                // Auto-centering on hover creates a feedback loop at the screen
                // edges: scroll -> tile under mouse changes -> hover fires again.
                onPositionChanged: mouse => { carousel.selected = index }
                onClicked: carousel.choose()
                onWheel: wheel => {
                    carousel.pick(carousel.selected + (wheel.angleDelta.y < 0 ? 1 : -1))
                    wheel.accepted = true
                }
            }
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left: case Qt.Key_H: case Qt.Key_A:
                carousel.pick(carousel.selected - 1); break
            case Qt.Key_Right: case Qt.Key_L: case Qt.Key_D:
                carousel.pick(carousel.selected + 1); break
            case Qt.Key_Home: carousel.pick(0); break
            case Qt.Key_End: carousel.pick(carousel.count - 1); break
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                carousel.choose(); break
            case Qt.Key_Escape: case Qt.Key_Q: case Qt.Key_W:
                Qt.quit(); break
            default: return
            }
            event.accepted = true
        }
    }
}
