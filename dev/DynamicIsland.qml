import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "."

// ══════════════════════════════════════════════════════════════════════
// DYNAMIC ISLAND (DynamicIsland.qml)
// ══════════════════════════════════════════════════════════════════════
// Îlot central dynamique style macOS / iOS / r/unixporn :
// - Compact au repos : Heure par défaut + mini lecteur audio avec contrôles
// - Morphing fluide et extension au survol de la souris
// - Révélation progressive des applets système, réseau, tray et batterie
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    readonly property string ile: "haut:milieu"

    // Panneau calendrier interactif rattaché à l'îlot dynamique
    Loader {
        id: calPanneauLoader
        active: Theme.barStyle === "island"
        source: "CalendrierPanneau.qml"
        onLoaded: {
            if (!item) return
            item.ancre = Qt.binding(() => root)
            item.ouvert = Qt.binding(() => Theme.barStyle === "island" && Theme.activePopup === "calendar")
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    property bool isHovered: islandMouseArea.containsMouse || extraMouseArea.containsMouse

    // Indicateurs VPN (droite) et capture vidéo/audio (gauche avant les ws)
    property string vpnState: "disconnected" // "connected" | "disconnected" | "error"
    property string captureState: "none"     // "video" | "audio" | "none"
    property bool plankaEcheanceProche: false
    property string plankaUrgence: "none"    // "none" | "orange" | "rouge"

    Process {
        id: plankaStatutProc
        command: ["python3", Quickshell.shellPath("core/planka_service.py"), "statut"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.plankaEcheanceProche = Boolean(d && d.echeance_proche)
                    root.plankaUrgence = String((d && d.urgence) || "none")
                } catch (e) {}
            }
        }
    }

    Timer {
        id: plankaStatutTimer
        interval: 60000
        repeat: true
        running: Theme.barStyle === "island" && Theme.ilotProjetsActif
        triggeredOnStart: true
        onTriggered: if (!plankaStatutProc.running) plankaStatutProc.running = true
    }

    Process {
        id: indicateursProc
        command: ["python3", Quickshell.shellPath("core/indicateurs_service.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && typeof d.vpn === "string") root.vpnState = d.vpn
                    if (d && typeof d.capture === "string") root.captureState = d.capture
                } catch (e) {}
            }
        }
    }

    Timer {
        id: indicateursTimer
        interval: 3000
        repeat: true
        running: Theme.barStyle === "island"
        triggeredOnStart: true
        onTriggered: if (!indicateursProc.running) indicateursProc.running = true
    }

    // Service MPRIS direct pour la réactivité instantanée
    readonly property var players: Mpris.players.values

    // Respecte le filtre navigateur activé dans les réglages de l'applet musique
    readonly property bool ignorerNavigateurs: {
        let a = (Theme.barAppletsActifs && Theme.barAppletsActifs["musique"]) ? Theme.barAppletsActifs["musique"].options : null
        return (a && a.ignorer_navigateurs !== undefined) ? Boolean(a.ignorer_navigateurs) : true
    }

    function isBrowserPlayer(p) {
        if (!p) return false
        let id = (p.identity || "").toLowerCase()
        let entry = (p.desktopEntry || "").toLowerCase()
        let bus = (p.busName || "").toLowerCase()
        const navs = ["firefox", "chromium", "chrome", "brave", "vivaldi", "epiphany", "zen", "edge", "opera"]
        return navs.some(n => id.indexOf(n) !== -1 || entry.indexOf(n) !== -1 || bus.indexOf(n) !== -1)
    }

    readonly property var validPlayers: {
        if (!players || players.length === 0) return []
        let res = []
        for (let i = 0; i < players.length; i++) {
            let p = players[i]
            if (!p) continue
            if (root.ignorerNavigateurs && isBrowserPlayer(p)) continue
            res.push(p)
        }
        return res
    }

    readonly property var activePlayer: {
        let list = validPlayers
        if (!list || list.length === 0) return null
        // 1. Cherche en priorité un lecteur en cours de lecture avec titre
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.playbackState === MprisPlaybackState.Playing && p.trackTitle && p.trackTitle.trim().length > 0) {
                return p
            }
        }
        // 2. Cherche un lecteur avec titre valide (même en pause)
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.trackTitle && p.trackTitle.trim().length > 0) {
                return p
            }
        }
        // 3. Lecteur en cours de lecture quelconque
        for (let i = 0; i < list.length; i++) {
            let p = list[i]
            if (p.playbackState === MprisPlaybackState.Playing) return p
        }
        return list[0] || null
    }

    readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property string mediaTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string mediaArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property bool isMediaActive: (mediaTitle.trim() !== "")

    // Synchronise Theme.mediaPlaying si nécessaire
    onIsPlayingChanged: Theme.mediaPlaying = isPlaying
    onMediaTitleChanged: Theme.mediaTitle = mediaTitle
    onMediaArtistChanged: Theme.mediaArtist = mediaArtist

    readonly property bool isCalendarOpen: Theme.activePopup === "calendar"
    readonly property bool isPopupOpen: Theme.activePopup !== ""
    readonly property bool panelOpen: Theme.islandPanelOpen
    readonly property bool notifToastActive: Theme.barStyle === "island"
        && Theme.notifToastVisible
        && Theme.notifToast !== null
        && !panelOpen
    readonly property bool meteoExpanded: Theme.barStyle === "island"
        && Theme.activePopup === "applet:meteo"
        && !panelOpen
        && !notifToastActive
    readonly property bool wallpaperExpanded: Theme.barStyle === "island"
        && Theme.wallpaperPickerOpen
        && !panelOpen
        && !notifToastActive
        && !meteoExpanded
    readonly property bool launcherExpanded: Theme.barStyle === "island"
        && Theme.islandLauncherOpen
        && !panelOpen
        && !notifToastActive
        && !meteoExpanded
        && !wallpaperExpanded
    readonly property bool notesExpanded: Theme.barStyle === "island"
        && Theme.islandNotesOpen
        && !panelOpen
        && !notifToastActive
        && !meteoExpanded
        && !wallpaperExpanded
        && !launcherExpanded
    readonly property string etat: panelOpen ? "panneau" : (notifToastActive ? "toast" : (notesExpanded ? "notes" : (launcherExpanded ? "launcher" : (wallpaperExpanded ? "wallpaper" : (meteoExpanded ? "meteo" : (expanded ? "etendu_barre" : "compact"))))))

    property var wallpaperList: []
    property int wallpaperSelectedIdx: 0

    Process {
        id: wallpaperScanProc
        command: [
            "python3", "-c",
            "import os, json, pathlib\n"
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
                        if (root.wallpaperList[i].path === Theme.wallpaperCourant) {
                            curIdx = i
                            break
                        }
                    }
                    root.wallpaperSelectedIdx = curIdx
                } catch (e) {
                    root.wallpaperList = []
                }
            }
        }
    }

    function applyWallpaper(path) {
        if (!path) return
        Quickshell.execDetached(["bash", Quickshell.shellPath("hyprquickpaper/commands.sh"), String(path)])
        Theme.wallpaperPickerOpen = false
    }

    function handleWallpaperNav(action) {
        const n = root.wallpaperList.length
        if (action === "prev" || action === "left" || action === "gauche") {
            if (n > 0) {
                root.wallpaperSelectedIdx = (root.wallpaperSelectedIdx - 1 + n) % n
                wpListView.positionViewAtIndex(root.wallpaperSelectedIdx, ListView.Center)
            }
        } else if (action === "next" || action === "right" || action === "droite") {
            if (n > 0) {
                root.wallpaperSelectedIdx = (root.wallpaperSelectedIdx + 1) % n
                wpListView.positionViewAtIndex(root.wallpaperSelectedIdx, ListView.Center)
            }
        } else if (action === "apply" || action === "valider") {
            if (n > 0) {
                const idx = Math.max(0, Math.min(n - 1, root.wallpaperSelectedIdx))
                root.applyWallpaper(root.wallpaperList[idx].path)
            }
        }
    }

    Component.onCompleted: {
        Theme.wallpaperNavHook = root.handleWallpaperNav
    }

    // Attrapeur de focus Hyprland pour le sélecteur de fonds d'écran inline
    property bool pretGrabWallpaper: false
    onWallpaperExpandedChanged: {
        if (wallpaperExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabWallpaper = false
            delaiGrabWallpaper.restart()
            wallpaperScanProc.environment = ({ "QS_WP_DIR": Theme.wallpaperDir || "" })
            if (!wallpaperScanProc.running) wallpaperScanProc.running = true
            wallpaperContainer.forceActiveFocus()
        } else {
            delaiGrabWallpaper.stop()
            pretGrabWallpaper = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabWallpaper
        interval: 150
        repeat: false
        onTriggered: if (root.wallpaperExpanded) root.pretGrabWallpaper = true
    }

    HyprlandFocusGrab {
        active: root.wallpaperExpanded && root.pretGrabWallpaper
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.wallpaperPickerOpen) Theme.wallpaperPickerOpen = false
        }
    }

    // ── Lanceur d'applications inline (SUPER + R en mode îlot) ───────────
    property var launcherApps: []
    property var launcherHistory: []
    property var launcherServiceResults: []
    property string launcherQuery: ""
    property int launcherSelectedIdx: 0
    property bool launcherSearching: false

    FileView {
        id: launcherAppsFile
        path: Quickshell.shellPath("core/app_index.json")
        watchChanges: root.launcherExpanded
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.launcherApps = Array.isArray(d) ? d : []
            } catch (e) { root.launcherApps = [] }
        }
    }

    FileView {
        id: launcherHistoryFile
        path: Quickshell.shellPath("core/launch_history.json")
        watchChanges: root.launcherExpanded
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.launcherHistory = Array.isArray(d) ? d : []
            } catch (e) { root.launcherHistory = [] }
        }
    }

    Process {
        id: launcherServiceProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.launcherServiceResults = (d && Array.isArray(d.results)) ? d.results : []
                } catch (e) {
                    root.launcherServiceResults = []
                }
                root.launcherSearching = false
            }
        }
        onExited: root.launcherSearching = false
    }

    readonly property var launcherResults: {
        const q = root.launcherQuery.trim()
        if (q.startsWith(">")) {
            const cmd = q.slice(1).trim()
            if (cmd === "") return []
            return [{ name: cmd, desc: "Exécuter dans sh", exec: cmd, icon: "terminal", kind: "cmd" }]
        }
        if (/^[^a-zA-Z0-9\s>]/.test(q)) {
            return root.launcherServiceResults.slice(0, 8)
        }
        if (q === "") {
            if (Theme.launchHistory && root.launcherHistory.length > 0) {
                return root.launcherHistory.slice(0, 7)
            }
            return root.launcherApps.slice(0, 7)
        }
        const ql = q.toLowerCase()
        const exact = []
        const sub = []
        for (let i = 0; i < root.launcherApps.length; i++) {
            const a = root.launcherApps[i]
            if (!a || !a.name) continue
            const name = String(a.name).toLowerCase()
            const gen = String(a.generic || "").toLowerCase()
            const ex = String(a.exec || "").toLowerCase()
            if (name.indexOf(ql) === 0) exact.push(a)
            else if (name.indexOf(ql) !== -1 || gen.indexOf(ql) !== -1 || ex.indexOf(ql) !== -1) sub.push(a)
        }
        return exact.concat(sub).slice(0, 8)
    }

    Timer {
        id: launcherSvcTimer
        interval: 100
        repeat: false
        onTriggered: {
            const q = root.launcherQuery.trim()
            if (!/^[^a-zA-Z0-9\s>]/.test(q)) return
            if (launcherServiceProc.running) launcherServiceProc.running = false
            launcherServiceProc.command = [
                "python3", Quickshell.shellPath("core/launcher_service.py"),
                "--query", q, "--limit", "8"
            ]
            launcherServiceProc.running = true
        }
    }

    onLauncherQueryChanged: {
        launcherSelectedIdx = 0
        const q = launcherQuery.trim()
        if (/^[^a-zA-Z0-9\s>]/.test(q)) {
            launcherSearching = true
            launcherSvcTimer.restart()
        } else {
            launcherSearching = false
            launcherSvcTimer.stop()
            if (launcherServiceProc.running) launcherServiceProc.running = false
            launcherServiceResults = []
        }
    }

    function runLauncherEntry(entry) {
        if (!entry) return
        if (entry.action === "prefill" && entry.arg !== undefined) {
            launcherInput.text = String(entry.arg)
            launcherInput.cursorPosition = launcherInput.text.length
            return
        }
        if (entry.action === "copy" && entry.arg) {
            Quickshell.execDetached(["wl-copy", String(entry.arg)])
            Theme.islandLauncherOpen = false
            return
        }
        if ((entry.action === "open" || entry.action === "open-url") && entry.arg) {
            Quickshell.execDetached(["xdg-open", String(entry.arg)])
            Theme.islandLauncherOpen = false
            return
        }
        if (entry.action === "kill" && entry.arg) {
            Quickshell.execDetached(["kill", "-TERM", String(entry.arg)])
            Theme.islandLauncherOpen = false
            return
        }
        if (!entry.exec) return
        const shell = entry.kind === "cmd"
            ? 'cd "$HOME" && ' + entry.exec
            : 'cd "$HOME" && exec ' + entry.exec
        Quickshell.execDetached(["setsid", "sh", "-c", shell])
        if (Theme.launchHistory && entry.name) {
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/launch_history.py"), "add", String(entry.name), String(entry.exec), String(entry.icon || "")])
        }
        Theme.islandLauncherOpen = false
    }

    property bool pretGrabLauncher: false
    onLauncherExpandedChanged: {
        if (launcherExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabLauncher = false
            delaiGrabLauncher.restart()
            launcherAppsFile.reload()
            launcherHistoryFile.reload()
            launcherInput.text = ""
            root.launcherQuery = ""
            root.launcherSelectedIdx = 0
            launcherInput.forceActiveFocus()
        } else {
            delaiGrabLauncher.stop()
            pretGrabLauncher = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabLauncher
        interval: 150
        repeat: false
        onTriggered: if (root.launcherExpanded) root.pretGrabLauncher = true
    }

    HyprlandFocusGrab {
        active: root.launcherExpanded && root.pretGrabLauncher
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.islandLauncherOpen) Theme.islandLauncherOpen = false
        }
    }

    // ── Notes rapides / Post-its inline (SUPER + N ou bouton Notes) ──────
    property var quickNotes: []
    property int activeNoteIdx: 0
    property bool _notesSyncing: false

    Process {
        id: notesLoadProc
        command: [
            "python3", "-c",
            "import os, json\n"
            + "p = os.path.expanduser('~/.cache/quickshell/quick_notes.json')\n"
            + "try:\n"
            + "    d = json.loads(open(p).read())\n"
            + "    print(json.dumps(d if isinstance(d, list) and d else [{'id': 1, 'text': ''}]))\n"
            + "except Exception:\n"
            + "    print(json.dumps([{'id': 1, 'text': ''}]))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text.trim())
                    root.quickNotes = (Array.isArray(arr) && arr.length > 0) ? arr : [{ id: 1, text: "" }]
                } catch (e) {
                    root.quickNotes = [{ id: 1, text: "" }]
                }
                root.activeNoteIdx = Math.max(0, Math.min(root.quickNotes.length - 1, root.activeNoteIdx))
                root._notesSyncing = true
                noteEditor.text = String((root.quickNotes[root.activeNoteIdx] && root.quickNotes[root.activeNoteIdx].text) || "")
                root._notesSyncing = false
            }
        }
    }

    Process { id: notesSaveProc }

    function saveQuickNotes() {
        notesSaveProc.environment = ({ "QS_NOTES_JSON": JSON.stringify(root.quickNotes) })
        notesSaveProc.command = [
            "python3", "-c",
            "import os, pathlib\n"
            + "p = pathlib.Path(os.path.expanduser('~/.cache/quickshell/quick_notes.json'))\n"
            + "p.parent.mkdir(parents=True, exist_ok=True)\n"
            + "p.write_text(os.environ.get('QS_NOTES_JSON', '[]'))"
        ]
        if (!notesSaveProc.running) notesSaveProc.running = true
    }

    Timer {
        id: notesSaveTimer
        interval: 300
        repeat: false
        onTriggered: root.saveQuickNotes()
    }

    function selectNote(idx) {
        if (idx < 0 || idx >= root.quickNotes.length) return
        root.activeNoteIdx = idx
        root._notesSyncing = true
        noteEditor.text = String(root.quickNotes[idx].text || "")
        root._notesSyncing = false
        noteEditor.forceActiveFocus()
    }

    function addQuickNote() {
        const list = root.quickNotes.slice()
        list.push({ id: Date.now(), text: "" })
        root.quickNotes = list
        selectNote(list.length - 1)
        root.saveQuickNotes()
    }

    function deleteQuickNote(idx) {
        if (root.quickNotes.length <= 1) {
            root.quickNotes = [{ id: 1, text: "" }]
            selectNote(0)
            root.saveQuickNotes()
            return
        }
        const list = root.quickNotes.slice()
        list.splice(idx, 1)
        root.quickNotes = list
        selectNote(Math.max(0, Math.min(list.length - 1, idx)))
        root.saveQuickNotes()
    }

    property bool pretGrabNotes: false
    onNotesExpandedChanged: {
        if (notesExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabNotes = false
            delaiGrabNotes.restart()
            if (!notesLoadProc.running) notesLoadProc.running = true
            noteEditor.forceActiveFocus()
        } else {
            delaiGrabNotes.stop()
            pretGrabNotes = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabNotes
        interval: 150
        repeat: false
        onTriggered: if (root.notesExpanded) root.pretGrabNotes = true
    }

    HyprlandFocusGrab {
        active: root.notesExpanded && root.pretGrabNotes
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.islandNotesOpen) Theme.islandNotesOpen = false
        }
    }

    // Attrapeur de focus Hyprland pour l'extension météo inline (clic extérieur -> ferme)
    property bool pretGrabMeteo: false
    onMeteoExpandedChanged: {
        if (meteoExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabMeteo = false
            delaiGrabMeteo.restart()
            Theme.rafraichirMeteo(false)
            meteoContainer.forceActiveFocus()
        } else {
            delaiGrabMeteo.stop()
            pretGrabMeteo = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabMeteo
        interval: 150
        repeat: false
        onTriggered: if (root.meteoExpanded) root.pretGrabMeteo = true
    }

    HyprlandFocusGrab {
        active: root.meteoExpanded && root.pretGrabMeteo
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.activePopup === "applet:meteo") Theme.activePopup = ""
        }
    }

    Binding {
        target: Theme
        property: "notifToastHovered"
        value: root.notifToastActive && root.isHovered
    }

    // Attrapeur de focus Hyprland armé à +150 ms à l'ouverture du panneau
    property bool pretGrab: false
    onPanelOpenChanged: {
        if (panelOpen) {
            retractTimer.stop()
            expanded = true
            pretGrab = false
            delaiGrab.restart()
            panelContainer.forceActiveFocus()
        } else {
            delaiGrab.stop()
            pretGrab = false
            Theme.islandNeedsKeyboard = false
            Theme.islandNavActive = false
            if (!isHovered && !isPopupOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrab
        interval: 150
        repeat: false
        onTriggered: if (root.panelOpen) root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.panelOpen && root.pretGrab
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (root.panelOpen) {
                Theme.islandPanelOpen = false
                Theme.islandNeedsKeyboard = false
                Theme.islandNavActive = false
            }
        }
    }

    function ouvrirPanneau(tabIdx) {
        Theme.activePopup = ""
        Theme.wallpaperPickerOpen = false
        Theme.islandLauncherOpen = false
        Theme.islandNotesOpen = false
        if (tabIdx !== undefined) Theme.islandPanelTab = tabIdx
        Theme.islandPanelOpen = true
    }

    // Délai de rétractation (160 ms) pour une navigation fluide sans sursauts
    property bool expanded: isHovered || isPopupOpen || panelOpen
    onIsHoveredChanged: {
        if (isHovered || isPopupOpen || panelOpen) {
            retractTimer.stop()
            expanded = true
        } else {
            retractTimer.restart()
        }
    }
    onIsPopupOpenChanged: {
        if (isPopupOpen || panelOpen) {
            retractTimer.stop()
            expanded = true
        } else if (!isHovered) {
            retractTimer.restart()
        }
    }

    Timer {
        id: retractTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (!root.isHovered && !root.isPopupOpen && !root.panelOpen) root.expanded = false
        }
    }

    readonly property int fadeDuration: Math.max(100, Math.round(Theme.panelAnimDuration * 0.85))
    readonly property real toastHeight: Math.max(Theme.barHeight + 24, toastContentCol.implicitHeight + 24)
    readonly property real meteoHeight: Math.max(140, meteoContentCol.implicitHeight + 28)
    readonly property real wallpaperHeight: 224
    readonly property real launcherHeight: Math.min(440, 74 + Math.max(1, root.launcherResults.length) * 44 + 14)
    readonly property real notesHeight: 270
    implicitHeight: panelOpen ? 420 : (notifToastActive ? toastHeight : (notesExpanded ? notesHeight : (launcherExpanded ? launcherHeight : (wallpaperExpanded ? wallpaperHeight : (meteoExpanded ? meteoHeight : Theme.barHeight)))))
    height: panelOpen ? 420 : (notifToastActive ? toastHeight : (notesExpanded ? notesHeight : (launcherExpanded ? launcherHeight : (wallpaperExpanded ? wallpaperHeight : (meteoExpanded ? meteoHeight : Theme.barHeight)))))
    Behavior on height {
        NumberAnimation {
            duration: Theme.panelAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // Largeur dynamique animée selon l'état
    readonly property real osdWidth: Math.max(160, osdRow.implicitWidth + Theme.padH * 2 + 16)
    readonly property real compactRestWidth: Math.max(90, compactContentRow.implicitWidth + Theme.padH * 2)
    readonly property real compactWidth: Theme.osdVisible ? osdWidth : compactRestWidth
    readonly property real meteoWidth: Math.max(410, meteoContentCol.implicitWidth + 32)
    readonly property real wallpaperWidth: 880
    readonly property real launcherWidth: 560
    readonly property real notesWidth: 520
    readonly property real expandedWidth: Math.max(
        compactRestWidth,
        fullContentRow.implicitWidth + Theme.padH * 2
    )

    readonly property int sidePanelWidth: (panelOpen && Theme.islandSidePanel !== "") ? 340 : 0
    width: panelOpen ? (680 + sidePanelWidth) : (notifToastActive ? 400 : (notesExpanded ? notesWidth : (launcherExpanded ? launcherWidth : (wallpaperExpanded ? wallpaperWidth : (meteoExpanded ? meteoWidth : (expanded ? expandedWidth : compactWidth))))))

    Behavior on width {
        NumberAnimation {
            duration: Theme.panelAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // Fond en pilule élégante avec surface floutée unifiée (identique à config_panel / PanneauSurface)
    SurfaceFloutee {
        id: bgRect
        anchors.fill: parent
        rayon: root.panelOpen ? Math.max(Theme.pillRadius, 18) : ((root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded) ? Math.max(Theme.globalRadius, 16) : Theme.pillRadius)
        Behavior on rayon { NumberAnimation { duration: Math.max(80, Theme.panelAnimDuration - 20); easing.type: Easing.OutCubic } }
        teinte: (root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded) ? Theme.surfaceBg : Theme.barBg
        bordureCouleur: (root.isCalendarOpen || root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded) ? Theme.accentMuted : Theme.accent
        bordureLargeur: Theme.barBorder ? 1 : 0
        actif: root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU COMPACT (AU REPOS)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: compactContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight
        clip: true
        opacity: (root.expanded || root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded) ? 0.0 : 1.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        // Clic sur la pilule compacte : ouvre le panneau de raccourcis (façon Android)
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.ouvrirPanneau(0)
        }

        // 1. OSD actif : affiche le volume / luminosité dans la pilule
        Row {
            id: osdRow
            anchors.centerIn: parent
            spacing: 8
            visible: Theme.osdVisible

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: Theme.osdKind === "brightness" ? "brightness"
                    : Theme.osdKind === "mute" ? "volume-off"
                    : (Theme.osdValue <= 0 ? "mute" : Theme.osdValue < 50 ? "volume-medium" : "volume-high")
                size: Theme.iconSm
                color: Theme.accent
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                height: 4
                radius: 2
                color: Theme.surfaceVariant
                Rectangle {
                    width: parent.width * (Theme.osdValue / 100)
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Theme.osdValue) + "%"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.fg
            }
        }

        // 2. Repos : Capture (si active) + Workspaces (points/tiret) à gauche + Heure + lecteur audio + VPN à droite
        Row {
            id: compactContentRow
            anchors.centerIn: parent
            spacing: 10
            visible: !Theme.osdVisible

            // Point capture vidéo (rouge) / audio seule (orange) avant les ws
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowCapture, "compact") && root.captureState !== "none"
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.captureState === "video" ? "#ef4444" : "#f97316"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            WorkspacesApplet {
                id: compactWorkspaces
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "compact")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "compact") && Theme.ilotVisibleIn(Theme.ilotShowClock, "compact")
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Horloge principale sans glyphe (clic -> panneau étendu)
            Text {
                visible: Theme.ilotVisibleIn(Theme.ilotShowClock, "compact")
                text: Qt.formatTime(clock.date, "HH:mm")
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(Theme.textSm * Theme.barScale))
                font.weight: Font.Bold
                color: Theme.fg
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            // Séparateur subtil (uniquement si média actif)
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "compact") && root.isMediaActive
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Si un média est actif : titre du morceau en cours
            Text {
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "compact") && root.isMediaActive
                text: {
                    let t = root.mediaTitle
                    if (!t) return "Audio"
                    return t.length > 16 ? (t.substring(0, 15) + "…") : t
                }
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                font.weight: Font.Medium
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            // Applets configurés en mode « Repos » ou « Les deux »
            AppletRow {
                id: compactApplets
                directModel: Theme.appletsPourIlot("compact", "all")
                visible: compactApplets.applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Icône Projets (columns-3) si échéance Planka < 24h
            Item {
                visible: Theme.ilotProjetsActif && Theme.ilotVisibleIn(Theme.ilotShowPlanka, "compact") && root.plankaEcheanceProche
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    glyph: "columns-3"
                    size: Theme.iconSm
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(4)
                }
            }

            // Point VPN à droite (bleu = connecté, blanc = déconnecté, jaune = erreur)
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowVpn, "compact")
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: root.vpnState === "connected"
                    ? "#00a3d5"
                    : (root.vpnState === "error" ? "#eab308" : "#ffffff")
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU ÉTENDU (AU SURVOL)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: expandedContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.barHeight
        clip: true
        opacity: (root.expanded && !root.panelOpen && !root.notifToastActive && !root.meteoExpanded && !root.wallpaperExpanded && !root.launcherExpanded && !root.notesExpanded && root.width >= root.expandedWidth - 16) ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
            id: fullContentRow
            anchors.centerIn: parent
            spacing: 10

            // Côté Gauche : Point capture (si actif) + Workspaces (points/tiret maintenus) + Applets gauche
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowCapture, "expanded") && root.captureState !== "none"
                width: 6
                height: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: root.captureState === "video" ? "#ef4444" : "#f97316"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            WorkspacesApplet {
                id: expandedWorkspaces
                visible: Theme.ilotVisibleIn(Theme.ilotShowWorkspaces, "expanded")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            AppletRow {
                id: leftApplets
                directModel: Theme.appletsPourIlot("expanded", "left")
                visible: applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Centre : Horloge + Date (clic -> panneau étendu)
            Item {
                visible: Theme.ilotVisibleIn(Theme.ilotShowClock, "expanded")
                width: clockDateRow.implicitWidth
                height: clockDateRow.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: clockDateRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: Qt.formatTime(clock.date, "HH:mm")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Qt.formatDate(clock.date, "ddd d MMM")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Medium
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            // Séparateur + titre média en mode étendu (si configuré dans Indicateurs de la pilule)
            Rectangle {
                id: expandedMediaSep
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "expanded") && root.isMediaActive
                width: 1
                height: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.15
            }

            Text {
                id: expandedMediaTitle
                visible: Theme.ilotVisibleIn(Theme.ilotShowMedia, "expanded") && root.isMediaActive
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    let t = root.mediaTitle
                    if (!t) return "Audio"
                    return t.length > 20 ? (t.substring(0, 19) + "…") : t
                }
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                font.weight: Font.Medium
                color: Theme.accent
            }

            // Côté Droit : Applets droite
            AppletRow {
                id: rightApplets
                directModel: Theme.appletsPourIlot("expanded", "right")
                visible: applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Bouton d'accès rapide au panneau de configuration
            Rectangle {
                visible: Theme.showConfigButton
                width: 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.configPanelVisible
                    ? Theme.accent
                    : (islandGearMa.containsMouse ? Theme.surfaceVariant : "transparent")

                Icon {
                    anchors.centerIn: parent
                    glyph: "cog"
                    size: Theme.iconMd
                    color: Theme.configPanelVisible ? Theme.bg : Theme.fg
                    opacityLevel: 1
                }

                MouseArea {
                    id: islandGearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.configPanelVisible = !Theme.configPanelVisible
                }
            }

            // Icône Projets (columns-3) maintenue au survol si échéance Planka < 24h
            Item {
                visible: Theme.ilotProjetsActif && Theme.ilotVisibleIn(Theme.ilotShowPlanka, "expanded") && root.plankaEcheanceProche
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    glyph: "columns-3"
                    size: Theme.iconSm
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.top: parent.top
                    anchors.right: parent.right
                    color: root.plankaUrgence === "rouge" ? "#ef4444" : "#f97316"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(4)
                }
            }

            // Point VPN à droite en mode étendu
            Rectangle {
                visible: Theme.ilotVisibleIn(Theme.ilotShowVpn, "expanded")
                width: 6
                height: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: root.vpnState === "connected"
                    ? "#00a3d5"
                    : (root.vpnState === "error" ? "#eab308" : "#ffffff")
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CAPSULE NOTIFICATION « DROP FROM ISLAND »
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: toastContainer
        anchors.fill: parent
        clip: true
        opacity: root.notifToastActive ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        // Clic sur le fond de la capsule : ouvre l'onglet Alertes & Tâches du panneau
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Theme.notifOps && Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                root.ouvrirPanneau(1)
            }
        }

        Column {
            id: toastContentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 5

            // En-tête : icône cloche + application + heure + sourdine + fermeture
            RowLayout {
                width: parent.width
                spacing: 6

                Icon {
                    glyph: "bell"
                    size: 11
                    color: Theme.accent
                    opacityLevel: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: Theme.notifToast ? String(Theme.notifToast.appName || "Système") : ""
                    color: Theme.accent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: Theme.notifToast ? String(Theme.notifToast.time || "") : ""
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                }

                // Mettre cette application en sourdine (toasts)
                Item {
                    width: 18
                    height: 18
                    Icon {
                        anchors.centerIn: parent
                        glyph: "bell-off"
                        size: 12
                        color: islandQuietMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: islandQuietMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.notifOps && Theme.notifOps.quietToast) Theme.notifOps.quietToast()
                        }
                    }
                }

                // Fermer la capsule sans ouvrir le panneau
                Item {
                    width: 18
                    height: 18
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 12
                        color: islandDismissMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: islandDismissMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.notifOps && Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                        }
                    }
                }
            }

            // Titre (cliquable pour ouvrir l'application / action par défaut)
            Item {
                width: parent.width
                height: islandToastTitle.implicitHeight

                Text {
                    id: islandToastTitle
                    width: parent.width
                    text: Theme.notifToast ? String(Theme.notifToast.summary || "") : ""
                    color: (islandToastTitleMa.containsMouse && islandToastTitleMa.enabled)
                        ? Theme.accent : Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: islandToastTitleMa
                    anchors.fill: parent
                    enabled: Boolean(Theme.notifToast && Theme.notifOps && Theme.notifOps.hasTarget && Theme.notifOps.hasTarget(Theme.notifToast))
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (Theme.notifToast && Theme.notifOps && Theme.notifOps.open) {
                            Theme.notifOps.open(Theme.notifToast, false)
                        }
                    }
                }
            }

            // Corps du message
            Text {
                visible: Boolean(Theme.notifToast && Theme.notifToast.body && Theme.notifToast.body !== "")
                width: parent.width
                text: Theme.notifToast ? String(Theme.notifToast.body || "") : ""
                color: Qt.alpha(Theme.fg, 0.85)
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Boutons d'actions D-Bus de la notification
            Flow {
                width: parent.width
                visible: Boolean(Theme.notifToast && Theme.notifOps && Theme.notifOps.actions && Theme.notifOps.actions(Theme.notifToast).length > 0)
                spacing: Theme.space1

                Repeater {
                    model: (Theme.notifToast && Theme.notifOps && Theme.notifOps.actions)
                        ? Theme.notifOps.actions(Theme.notifToast) : []

                    Rectangle {
                        required property var modelData
                        width: islandActionLbl.implicitWidth + Theme.space3 * 2
                        height: 22
                        radius: Theme.globalRadius
                        color: islandActionMa.containsMouse
                            ? Qt.alpha(Theme.accent, 0.22)
                            : Qt.alpha(Theme.fg, 0.08)
                        border.width: 1
                        border.color: islandActionMa.containsMouse ? Theme.accent : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            id: islandActionLbl
                            anchors.centerIn: parent
                            text: modelData.text || modelData.identifier
                            color: islandActionMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.9)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: islandActionMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.notifToast && Theme.notifOps && Theme.notifOps.invoke) {
                                    Theme.notifOps.invoke(Theme.notifToast, modelData.identifier)
                                    if (Theme.notifOps.dismissToast) Theme.notifOps.dismissToast()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // EXTENSION MÉTÉO INLINE (MÊMES INFOS QUE LE WIDGET DE BUREAU)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: meteoContainer
        anchors.fill: parent
        clip: true
        focus: root.meteoExpanded
        Keys.onEscapePressed: Theme.activePopup = ""
        opacity: root.meteoExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        readonly property var meteo: Theme.meteoData
        readonly property bool ok: Theme.meteoLoaded && meteo && meteo.ok === true
        readonly property var previsions: (meteo && meteo.previsions) ? meteo.previsions.slice(1, 6) : []

        function meteoNombre(v, suffixe) {
            return (v === undefined || v === null) ? "—" : Math.round(Number(v)) + (suffixe || "")
        }

        function meteoJourCourt(iso) {
            const d = new Date(String(iso || "") + "T12:00:00")
            if (isNaN(d.getTime())) return String(iso || "")
            return d.toLocaleDateString(Qt.locale("fr_FR"), "ddd")
        }

        readonly property string meteoGlyphe: {
            const i = String((meteo && meteo.icon) || "").toLowerCase()
            if (i === "sun" || i === "clear") return "sun"
            if (i === "moon" || i === "night") return "weather-night"
            if (i === "cloud" || i === "overcast") return "cloud"
            if (i === "fog" || i === "rain" || i === "drizzle" || i === "snow" || i === "storm")
                return "weather-cloud"
            return (meteo && meteo.day === false) ? "weather-night" : "cloud"
        }

        Column {
            id: meteoContentCol
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Relevé du jour + actions (rafraîchir / fermer)
            RowLayout {
                width: Math.max(376, meteoForecastRow.implicitWidth)
                spacing: 12

                Icon {
                    glyph: meteoContainer.meteoGlyphe
                    size: 32
                    color: Theme.accent
                    opacityLevel: meteoContainer.ok ? 1.0 : 0.45
                }

                Text {
                    text: meteoContainer.ok ? Math.round(meteoContainer.meteo.temp) + "°" : "—"
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: 28
                    font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        width: parent.width
                        text: meteoContainer.ok
                            ? String(meteoContainer.meteo.label || "")
                            : (Theme.meteoStatut !== "" ? Theme.meteoStatut : "Chargement…")
                        color: Theme.fg
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: meteoContainer.ok ? String(meteoContainer.meteo.city || "") : ""
                        color: Qt.alpha(Theme.fg, 0.65)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "refresh"
                        size: 13
                        color: meteoRefreshMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: meteoRefreshMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.rafraichirMeteo(true)
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 13
                        color: meteoCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: meteoCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.activePopup = ""
                    }
                }
            }

            // Détails du jour (identiques au widget de bureau)
            Text {
                visible: meteoContainer.ok
                text: meteoContainer.ok
                    ? ("min " + meteoContainer.meteoNombre(meteoContainer.meteo.tmin, "°")
                       + " · max " + meteoContainer.meteoNombre(meteoContainer.meteo.tmax, "°")
                       + " · ressenti " + meteoContainer.meteoNombre(meteoContainer.meteo.feels, "°")
                       + " · " + meteoContainer.meteoNombre(meteoContainer.meteo.humidite, " %")
                       + " · vent " + meteoContainer.meteoNombre(meteoContainer.meteo.vent, " km/h")
                       + (Number(meteoContainer.meteo.pluie_mm) > 0
                          ? " · pluie " + meteoContainer.meteoNombre(meteoContainer.meteo.pluie_mm, " mm") : "")
                       + ((meteoContainer.meteo.stale === true || meteoContainer.meteo.cached === true)
                          ? " · dernière valeur connue" : ""))
                    : ""
                color: Qt.alpha(Theme.fg, 0.72)
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
            }

            // Prévisions des 5 jours suivants (identiques au widget de bureau)
            Row {
                id: meteoForecastRow
                visible: meteoContainer.ok && meteoContainer.previsions.length > 0
                spacing: 10

                Repeater {
                    model: meteoContainer.previsions

                    delegate: Rectangle {
                        required property var modelData
                        width: 68
                        height: forecastCol.implicitHeight + 10
                        radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                        color: Qt.alpha(Theme.surfaceVariant, 0.35)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.08)

                        Column {
                            id: forecastCol
                            anchors.centerIn: parent
                            width: parent.width - 8
                            spacing: 1

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: meteoContainer.meteoJourCourt(modelData.date)
                                color: Qt.alpha(Theme.fg, 0.75)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.capitalization: Font.Capitalize
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: meteoContainer.meteoNombre(modelData.tmin, "°") + " / " + meteoContainer.meteoNombre(modelData.tmax, "°")
                                color: Theme.fg
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.bold: true
                                font.features: { "tnum": 1 }
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                visible: modelData.pluie !== null && modelData.pluie !== undefined
                                text: meteoContainer.meteoNombre(modelData.pluie, " %")
                                color: Theme.accent
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // SÉLECTEUR DE FOND D'ÉCRAN INLINE FAÇON IMPASTO (SUPER + W)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: wallpaperContainer
        anchors.fill: parent
        clip: true
        focus: root.wallpaperExpanded
        Keys.onEscapePressed: Theme.wallpaperPickerOpen = false
        Keys.onLeftPressed: {
            if (root.wallpaperList.length > 0) {
                root.wallpaperSelectedIdx = (root.wallpaperSelectedIdx - 1 + root.wallpaperList.length) % root.wallpaperList.length
                wpListView.positionViewAtIndex(root.wallpaperSelectedIdx, ListView.Contain)
            }
        }
        Keys.onRightPressed: {
            if (root.wallpaperList.length > 0) {
                root.wallpaperSelectedIdx = (root.wallpaperSelectedIdx + 1) % root.wallpaperList.length
                wpListView.positionViewAtIndex(root.wallpaperSelectedIdx, ListView.Contain)
            }
        }
        Keys.onReturnPressed: {
            if (root.wallpaperList.length > 0) {
                const idx = Math.max(0, Math.min(root.wallpaperList.length - 1, root.wallpaperSelectedIdx))
                root.applyWallpaper(root.wallpaperList[idx].path)
            }
        }
        opacity: root.wallpaperExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

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
                            root.wallpaperSelectedIdx = idx
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
                        readonly property bool isCurrent: modelData.path === Theme.wallpaperCourant
                        readonly property bool isSelected: index === root.wallpaperSelectedIdx
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
                            onEntered: root.wallpaperSelectedIdx = index
                            onClicked: {
                                root.wallpaperSelectedIdx = index
                                root.applyWallpaper(modelData.path)
                            }
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // LANCEUR D'APPLICATIONS INLINE FAÇON IMPASTO (SUPER + R)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: launcherContainer
        anchors.fill: parent
        clip: true
        opacity: root.launcherExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Barre de recherche
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.65))
                color: Qt.alpha(Theme.surfaceVariant, 0.45)
                border.width: 1
                border.color: launcherInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Icon {
                        glyph: "search"
                        size: Theme.iconSm
                        color: Theme.accent
                    }

                    TextInput {
                        id: launcherInput
                        Layout.fillWidth: true
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        color: Theme.fg
                        selectByMouse: true
                        clip: true
                        onTextChanged: root.launcherQuery = text
                        Keys.onEscapePressed: Theme.islandLauncherOpen = false
                        Keys.onUpPressed: {
                            if (root.launcherResults.length > 0) {
                                root.launcherSelectedIdx = (root.launcherSelectedIdx - 1 + root.launcherResults.length) % root.launcherResults.length
                                launcherListView.positionViewAtIndex(root.launcherSelectedIdx, ListView.Contain)
                            }
                        }
                        Keys.onDownPressed: {
                            if (root.launcherResults.length > 0) {
                                root.launcherSelectedIdx = (root.launcherSelectedIdx + 1) % root.launcherResults.length
                                launcherListView.positionViewAtIndex(root.launcherSelectedIdx, ListView.Contain)
                            }
                        }
                        Keys.onReturnPressed: {
                            if (root.launcherResults.length > 0) {
                                const idx = Math.max(0, Math.min(root.launcherResults.length - 1, root.launcherSelectedIdx))
                                root.runLauncherEntry(root.launcherResults[idx])
                            }
                        }

                        Text {
                            visible: launcherInput.text === ""
                            text: "Rechercher une application (> cmd, = calcul, / fichier)…"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textSm
                            color: Qt.alpha(Theme.fg, 0.45)
                        }
                    }

                    Item {
                        width: 22
                        height: 22
                        Icon {
                            anchors.centerIn: parent
                            glyph: "close"
                            size: 13
                            color: launcherCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                            opacityLevel: 1
                        }
                        MouseArea {
                            id: launcherCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.islandLauncherOpen = false
                        }
                    }
                }
            }

            // Liste des résultats
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    visible: root.launcherResults.length === 0
                    anchors.centerIn: parent
                    text: root.launcherSearching ? "Recherche…" : "Aucun résultat"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Qt.alpha(Theme.fg, 0.5)
                }

                ListView {
                    id: launcherListView
                    anchors.fill: parent
                    spacing: 4
                    clip: true
                    visible: root.launcherResults.length > 0
                    model: root.launcherResults

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.launcherSelectedIdx
                        width: launcherListView.width
                        height: 40
                        radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                        color: selected
                            ? Qt.alpha(Theme.accent, 0.22)
                            : (lItemMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.45) : "transparent")
                        border.width: selected ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.55)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Icon {
                                glyph: "rocket"
                                size: Theme.iconSm
                                color: selected ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.name || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textSm
                                    font.weight: selected ? Font.Bold : Font.Medium
                                    color: selected ? Theme.accent : Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: Boolean(modelData.desc || modelData.generic)
                                    Layout.fillWidth: true
                                    text: String(modelData.desc || modelData.generic || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.text2xs
                                    color: Qt.alpha(Theme.fg, 0.58)
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: lItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.launcherSelectedIdx = index
                            onClicked: root.runLauncherEntry(modelData)
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // NOTES RAPIDES / POST-ITS INLINE (SUPER + N)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: notesContainer
        anchors.fill: parent
        clip: true
        opacity: root.notesExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // En-tête : titre + onglets de notes + Copier + Nouvelle + Fermer
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Icon {
                    glyph: "widgets"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                Text {
                    text: "NOTES"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.weight: Font.Bold
                    color: Theme.accent
                }

                Row {
                    Layout.fillWidth: true
                    spacing: 4
                    clip: true

                    Repeater {
                        model: root.quickNotes
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool active: index === root.activeNoteIdx
                            width: noteTabLbl.implicitWidth + 14
                            height: 22
                            radius: 6
                            color: active ? Theme.accent : (noteTabMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07))

                            Text {
                                id: noteTabLbl
                                anchors.centerIn: parent
                                text: "#" + (index + 1)
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                font.bold: active
                                color: active ? Theme.bg : Theme.fg
                            }

                            MouseArea {
                                id: noteTabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectNote(index)
                            }
                        }
                    }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 6
                        color: addNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textSm
                            font.bold: true
                            color: addNoteMa.containsMouse ? Theme.accent : Theme.fg
                        }

                        MouseArea {
                            id: addNoteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.addQuickNote()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: pinNoteLbl.implicitWidth + 14
                    Layout.preferredHeight: 22
                    radius: 6
                    color: pinNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        id: pinNoteLbl
                        anchors.centerIn: parent
                        text: "Bureau"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        font.weight: Font.DemiBold
                        color: pinNoteMa.containsMouse ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: pinNoteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.saveQuickNotes()
                            const list = Theme.widgets || []
                            let existing = null
                            for (let i = 0; i < list.length; i++) {
                                if (list[i] && list[i].type === "notes") {
                                    existing = list[i]
                                    break
                                }
                            }
                            const cm = Quickshell.shellPath("core/config_manager.py")
                            if (existing && existing.id) {
                                Quickshell.execDetached([
                                    "sh", "-c",
                                    "python3 \"$1\" widget_set \"$2\" enabled true && python3 \"$1\" widget_set \"$2\" note_index \"$3\"",
                                    "sh", cm, String(existing.id), String(root.activeNoteIdx)
                                ])
                            } else {
                                const wsId = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1
                                Quickshell.execDetached([
                                    "python3", cm, "widget_add", "notes", String(wsId > 0 ? wsId : 1), "120", "160"
                                ])
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: copyNoteLbl.implicitWidth + 14
                    Layout.preferredHeight: 22
                    radius: 6
                    color: copyNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        id: copyNoteLbl
                        anchors.centerIn: parent
                        text: "Copier"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        color: copyNoteMa.containsMouse ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: copyNoteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["wl-copy", noteEditor.text])
                    }
                }

                Rectangle {
                    Layout.preferredWidth: delNoteLbl.implicitWidth + 14
                    Layout.preferredHeight: 22
                    radius: 6
                    color: delNoteMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        id: delNoteLbl
                        anchors.centerIn: parent
                        text: "Suppr."
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        color: delNoteMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.75)
                    }

                    MouseArea {
                        id: delNoteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.deleteQuickNote(root.activeNoteIdx)
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 13
                        color: notesCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: notesCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.islandNotesOpen = false
                    }
                }
            }

            // Zone d'édition libre (auto-sauvegardée)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.65))
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.width: 1
                border.color: noteEditor.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Qt.alpha(Theme.fg, 0.1)

                Flickable {
                    id: noteFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, noteEditor.implicitHeight)
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: noteEditor
                        width: noteFlick.width
                        height: Math.max(noteFlick.height, implicitHeight)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        color: Theme.fg
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        Keys.onEscapePressed: Theme.islandNotesOpen = false
                        onTextChanged: {
                            if (root._notesSyncing) return
                            if (root.activeNoteIdx >= 0 && root.activeNoteIdx < root.quickNotes.length) {
                                const list = root.quickNotes.slice()
                                list[root.activeNoteIdx] = Object.assign({}, list[root.activeNoteIdx], { text: text })
                                root.quickNotes = list
                                notesSaveTimer.restart()
                            }
                        }

                        Text {
                            visible: noteEditor.text === ""
                            text: "Écrire une note rapide… (sauvegarde automatique)"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textSm
                            color: Qt.alpha(Theme.fg, 0.42)
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU PANNEAU ÉTENDU (ÉTAT 3 : 680 × 420 px, RAIL 5 ONGLETS)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: panelContainer
        anchors.fill: parent
        clip: true
        focus: root.panelOpen
        Keys.onEscapePressed: Theme.islandPanelOpen = false
        opacity: root.panelOpen ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        Loader {
            id: islandPanelLoader
            anchors.fill: parent
            active: true
            asynchronous: true
            source: "IslandPanel.qml"
            onLoaded: {
                if (!item) return
                item.clockDate = Qt.binding(() => clock.date)
                item.activePlayer = Qt.binding(() => root.activePlayer)
                item.validPlayers = Qt.binding(() => root.validPlayers)
                item.isPlaying = Qt.binding(() => root.isPlaying)
                item.mediaTitle = Qt.binding(() => root.mediaTitle)
                item.isMediaActive = Qt.binding(() => root.isMediaActive)
            }
        }
    }

    // Capteur de survol de la pilule
    MouseArea {
        id: islandMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    // Zone de détection légèrement élargie vers le bas pour éviter les décrochages accidentels
    MouseArea {
        id: extraMouseArea
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 10
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}