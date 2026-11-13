import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "."

// ══════════════════════════════════════════════════════════════════════
// WALLPAPER FX — Transitions de fond d'écran par shader (WallpaperFx.qml)
// ══════════════════════════════════════════════════════════════════════
// Inspiré de diegoMalagrida/pocket-dots (WallpaperFx.qml / wallfx.frag) :
// - Transition « contagio » en cellules 4 px organiques avec front lumineux
// - Transition « perfil » (contour + remplissage + propagation) si carte fournie
// - Passage de relais sans accroc avec `awww` en arrière-plan
// ══════════════════════════════════════════════════════════════════════

Scope {
    id: root

    property int msContagio: 1800
    property int msPerfil: 2000
    property int msFade: 130
    property real glow: 0.9
    property real lineW: 1.5

    property string oldPath: ""
    property string newPath: ""
    property string kind: "contagio"
    property string fieldPath: ""
    property string linePath: ""
    property string pendingOld: ""
    property string pendingNew: ""
    property string phase: "idle" // idle | mapping | loading | run | held | fadeout
    property real t: 0
    property real fade: 0
    property bool swapped: false
    property int gen: 0
    property int swapGen: -1

    property color ember: "orange"
    property color ink: "white"
    property real seed: 0
    property int readyCount: 0
    readonly property int screenCount: screens.instances.length
    readonly property bool active: phase !== "idle" && phase !== "mapping"

    function lifted(c) {
        return Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.55),
                       Math.min(Math.max(c.hslLightness, 0.62), 0.82), 1)
    }

    function startTransition(o, n) {
        if (!n) return
        if (!o || o === n) {
            Quickshell.execDetached(["awww", "img", n, "--transition-type", "fade", "--transition-duration", "0.5"])
            Theme.wallpaperCourant = n
            return
        }
        if (root.phase !== "idle") root.finish()
        root.pendingOld = o
        root.pendingNew = n
        root.phase = "mapping"
        watchdog.restart()
        mapProc.command = ["python3", Quickshell.shellPath("core/wallfx_maps.py"), n]
        mapProc.running = true
    }

    function prepare(o, n, k, f, l) {
        if (root.phase !== "idle" && root.phase !== "mapping") root.finish()
        root.oldPath = o
        root.newPath = n
        root.kind = (k === "perfil") ? "perfil" : "contagio"
        root.fieldPath = f
        root.linePath = l || f
        root.t = 0
        root.fade = 0
        root.readyCount = 0
        root.swapped = false
        root.gen++
        root.phase = "loading"
        watchdog.restart()
    }

    function screenReady() {
        if (root.phase !== "loading") return
        root.readyCount++
        if (root.readyCount < root.screenCount) return
        watchdog.stop()
        root.go()
    }

    function go() {
        if (root.phase !== "loading") return
        const pal = [Theme.accent, Theme.accentMuted, Theme.success, Theme.error, Theme.fg]
        const chroma = c => c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1))
        const light = c => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        root.ember = root.lifted(pal.reduce((a, b) => chroma(b) > chroma(a) ? b : a))
        root.ink = pal.reduce((a, b) => light(b) > light(a) ? b : a)
        root.seed = Math.random() * 100
        root.phase = "run"
        runAnim.duration = (root.kind === "perfil") ? root.msPerfil : root.msContagio
        runAnim.restart()
        fadeIn.restart()
    }

    function maybeFinish() {
        if (runAnim.running) return
        if (!root.swapped) {
            root.phase = "held"
            watchdog.restart()
            return
        }
        root.phase = "fadeout"
        fadeOut.restart()
    }

    function swap() {
        root.swapGen = root.gen
        awwwProc.command = ["awww", "img", root.newPath, "--transition-type", "none"]
        awwwProc.running = true
    }

    function finish() {
        fadeIn.stop()
        runAnim.stop()
        fadeOut.stop()
        watchdog.stop()
        settle.stop()
        root.phase = "idle"
        root.fade = 0
        root.t = 0
        root.oldPath = ""
        root.newPath = ""
        root.fieldPath = ""
        root.linePath = ""
        root.pendingOld = ""
        root.pendingNew = ""
    }

    NumberAnimation {
        id: fadeIn
        target: root
        property: "fade"
        from: 0
        to: 1
        duration: root.msFade
        easing.type: Easing.OutQuad
        onFinished: root.swap()
    }

    NumberAnimation {
        id: runAnim
        target: root
        property: "t"
        from: 0
        to: 1
        easing.type: Easing.Linear
        onFinished: root.maybeFinish()
    }

    NumberAnimation {
        id: fadeOut
        target: root
        property: "fade"
        from: 1
        to: 0
        duration: root.msFade
        easing.type: Easing.OutQuad
        onFinished: root.finish()
    }

    Process {
        id: mapProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "mapping") return
                try {
                    const d = JSON.parse(text.trim())
                    if (d && d.ok && d.field && d.line) {
                        root.prepare(root.pendingOld, root.pendingNew, d.kind || "contagio", d.field, d.line)
                        return
                    }
                } catch (e) {}
                const n = root.pendingNew
                root.finish()
                if (n) {
                    Quickshell.execDetached(["awww", "img", n, "--transition-type", "fade", "--transition-duration", "0.5"])
                    Theme.wallpaperCourant = n
                }
            }
        }
    }

    Process {
        id: awwwProc
        onExited: (code) => {
            if (root.swapGen !== root.gen) return
            if (code === 0) {
                Theme.wallpaperCourant = root.newPath
                settle.restart()
                return
            }
            const n = root.newPath
            root.finish()
            if (n) {
                Quickshell.execDetached(["awww", "img", n, "--transition-type", "fade", "--transition-duration", "0.5"])
                Theme.wallpaperCourant = n
            }
        }
    }

    Timer {
        id: settle
        interval: 40
        onTriggered: {
            root.swapped = true
            root.maybeFinish()
        }
    }

    Timer {
        id: watchdog
        interval: 5000
        onTriggered: {
            const n = root.newPath || root.pendingNew
            const loading = (root.phase === "loading" || root.phase === "mapping")
            root.finish()
            if (loading && n) {
                Quickshell.execDetached(["awww", "img", n, "--transition-type", "fade", "--transition-duration", "0.5"])
                Theme.wallpaperCourant = n
            }
        }
    }

    IpcHandler {
        target: "wallfx"
        function transition(oldImg: string, newImg: string): string {
            root.startTransition(oldImg, newImg)
            return "ok"
        }
        function play(oldImg: string, newImg: string, kind: string, field: string, line: string): string {
            root.prepare(oldImg, newImg, kind, field, line)
            return "ok"
        }
        function state(): string {
            return root.phase
        }
        function stop(): string {
            root.finish()
            return "ok"
        }
    }

    Variants {
        id: screens
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:wallfx"

            readonly property bool loaded: oldImg.status === Image.Ready
                && newImg.status === Image.Ready
                && fieldImg.status === Image.Ready
                && lineImg.status === Image.Ready
            onLoadedChanged: if (loaded) root.screenReady()

            Image {
                id: oldImg
                visible: false
                asynchronous: true
                cache: false
                source: root.oldPath ? ("file://" + root.oldPath) : ""
                sourceSize: Qt.size(win.width, win.height)
                fillMode: Image.PreserveAspectCrop
            }

            Image {
                id: newImg
                visible: false
                asynchronous: true
                cache: false
                source: root.newPath ? ("file://" + root.newPath) : ""
                sourceSize: Qt.size(win.width, win.height)
                fillMode: Image.PreserveAspectCrop
            }

            Image {
                id: fieldImg
                visible: false
                asynchronous: true
                cache: false
                smooth: root.kind === "perfil"
                source: root.fieldPath ? ("file://" + root.fieldPath) : ""
            }

            Image {
                id: lineImg
                visible: false
                asynchronous: true
                cache: false
                source: root.linePath ? ("file://" + root.linePath) : ""
            }

            function crop(img) {
                const iw = Math.max(img.implicitWidth, 1)
                const ih = Math.max(img.implicitHeight, 1)
                const s = Math.max(win.width / iw, win.height / ih)
                const w = win.width / (iw * s)
                const h = win.height / (ih * s)
                return Qt.vector4d((1 - w) / 2, (1 - h) / 2, w, h)
            }

            ShaderEffect {
                anchors.fill: parent
                visible: win.loaded
                opacity: root.fade
                property var oldTex: oldImg
                property var newTex: newImg
                property var fieldTex: fieldImg
                property var lineTex: lineImg
                property real t: root.t
                property real mode: root.kind === "perfil" ? 1 : 0
                property real sw: win.width
                property real sh: win.height
                property real fw: Math.max(fieldImg.implicitWidth, 1)
                property real fh: Math.max(fieldImg.implicitHeight, 1)
                property real lw: Math.max(lineImg.implicitWidth, 1)
                property real lh: Math.max(lineImg.implicitHeight, 1)
                property real glow: root.glow
                property real lineW: root.lineW
                property real sdRange: 16
                property real seed: root.seed
                property vector4d cropOld: win.crop(oldImg)
                property vector4d cropNew: win.crop(newImg)
                property color ember: root.ember
                property color ink: root.ink
                fragmentShader: Qt.resolvedUrl("shaders/wallfx.v15.frag.qsb")
            }
        }
    }
}
