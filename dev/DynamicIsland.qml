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
    readonly property bool themeExpanded: Theme.barStyle === "island"
        && Theme.themePickerOpen
        && !panelOpen
        && !notifToastActive
        && !meteoExpanded
        && !wallpaperExpanded
        && !launcherExpanded
        && !notesExpanded
    readonly property bool liveActivityExpanded: Theme.barStyle === "island"
        && Theme.islandLiveActivityOpen
        && !panelOpen
        && !notifToastActive
        && !meteoExpanded
        && !wallpaperExpanded
        && !launcherExpanded
        && !notesExpanded
        && !themeExpanded
    readonly property string etat: panelOpen ? "panneau" : (notifToastActive ? "toast" : (liveActivityExpanded ? "live" : (themeExpanded ? "theme" : (notesExpanded ? "notes" : (launcherExpanded ? "launcher" : (wallpaperExpanded ? "wallpaper" : (meteoExpanded ? "meteo" : (expanded ? "etendu_barre" : "compact"))))))))

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
        Theme.setWallpaperCourant(String(path))
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
        Theme.themeNavHook = root.handleThemeNav
    }

    // ── Sélecteur de jeu de couleurs inline (SUPER + C) ──────────────────
    property int themeSelectedIdx: 0

    Process {
        id: islandThemesScanProc
        command: ["python3", Quickshell.shellPath("core/themes_scan.py"), "--sync"]
    }

    function applyThemeScheme(nom) {
        if (!nom) return
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/theme_manager.py"), String(nom)])
        Theme.themePickerOpen = false
    }

    function handleThemeNav(action) {
        const list = Theme.paletteNoms || []
        const n = list.length
        if (action === "prev" || action === "left" || action === "gauche") {
            if (n > 0) {
                root.themeSelectedIdx = (root.themeSelectedIdx - 1 + n) % n
                themeListView.positionViewAtIndex(root.themeSelectedIdx, ListView.Center)
            }
        } else if (action === "next" || action === "right" || action === "droite") {
            if (n > 0) {
                root.themeSelectedIdx = (root.themeSelectedIdx + 1) % n
                themeListView.positionViewAtIndex(root.themeSelectedIdx, ListView.Center)
            }
        } else if (action === "apply" || action === "valider") {
            if (n > 0) {
                const idx = Math.max(0, Math.min(n - 1, root.themeSelectedIdx))
                root.applyThemeScheme(list[idx])
            }
        }
    }

    property bool pretGrabTheme: false
    onThemeExpandedChanged: {
        if (themeExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabTheme = false
            delaiGrabTheme.restart()
            if (!islandThemesScanProc.running) islandThemesScanProc.running = true
            const list = Theme.paletteNoms || []
            const cur = list.indexOf(Theme.activeTheme)
            root.themeSelectedIdx = cur >= 0 ? cur : 0
            themeListView.positionViewAtIndex(root.themeSelectedIdx, ListView.Center)
            themeContainer.forceActiveFocus()
        } else {
            delaiGrabTheme.stop()
            pretGrabTheme = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabTheme
        interval: 150
        repeat: false
        onTriggered: if (root.themeExpanded) root.pretGrabTheme = true
    }

    HyprlandFocusGrab {
        active: root.themeExpanded && root.pretGrabTheme
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.themePickerOpen) Theme.themePickerOpen = false
        }
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

    function asCommands(rest) {
        const r = String(rest || "").trim()
        const rl = r.toLowerCase()
        const out = []

        if (rl === "theme" || rl.indexOf("theme ") === 0) {
            const qTheme = rl.slice(5).trim()
            if (qTheme === "") {
                out.push({ name: "as theme", desc: "Ouvrir le sélecteur de jeu de couleurs", icon: "palette", kind: "as", asAction: "theme_picker" })
            }
            const noms = Theme.paletteNoms || []
            for (let i = 0; i < noms.length; i++) {
                const cle = String(noms[i])
                const label = String((Theme.paletteEtiquettes && Theme.paletteEtiquettes[cle]) || cle)
                if (qTheme === "" || cle.toLowerCase().indexOf(qTheme) !== -1 || label.toLowerCase().indexOf(qTheme) !== -1) {
                    out.push({
                        name: "as theme " + label,
                        desc: (cle === Theme.activeTheme ? "Thème actif · " : "Appliquer ") + cle,
                        icon: "palette",
                        kind: "as",
                        asAction: "theme_apply",
                        asArg: cle
                    })
                }
            }
            return out
        }

        if (rl === "energie" || rl.indexOf("energie ") === 0) {
            const qProf = rl.slice(7).trim()
            const profs = [
                { key: "performance", alias: "perf", label: "Performance", desc: "Puissance maximale (powerprofilesctl)" },
                { key: "balanced", alias: "equilibre", label: "Équilibré", desc: "Profil standard (powerprofilesctl)" },
                { key: "power-saver", alias: "eco", label: "Économie", desc: "Économie d'énergie (powerprofilesctl)" }
            ]
            for (let i = 0; i < profs.length; i++) {
                const p = profs[i]
                if (qProf === "" || p.alias.indexOf(qProf) !== -1 || p.key.indexOf(qProf) !== -1 || p.label.toLowerCase().indexOf(qProf) !== -1) {
                    out.push({
                        name: "as energie " + p.alias,
                        desc: p.label + " — " + p.desc,
                        icon: "battery",
                        kind: "as",
                        asAction: "energie",
                        asArg: p.key
                    })
                }
            }
            return out
        }

        if (rl.indexOf("nuit ") === 0) {
            const num = parseInt(r.slice(5).trim(), 10)
            if (!isNaN(num) && num >= 2200 && num <= 6500) {
                return [{ name: "as nuit " + num + " K", desc: "Régler la température du mode nuit", icon: "weather-night", kind: "as", asAction: "nuit_temp", asArg: num }]
            }
        }

        if (rl.indexOf("timer ") === 0) {
            const mins = parseInt(r.slice(6).trim(), 10)
            if (!isNaN(mins) && mins > 0) {
                return [{ name: "as timer " + mins, desc: "Démarrer un minuteur de " + mins + " min", icon: "clock", kind: "as", asAction: "timer", asArg: mins }]
            }
        }

        if (rl === "contexte" || rl.indexOf("contexte ") === 0) {
            const qCtx = rl.slice(8).trim()
            const ctxs = Theme.workContexts || []
            for (let i = 0; i < ctxs.length; i++) {
                const c = ctxs[i]
                if (qCtx === "" || c.id.indexOf(qCtx) !== -1 || c.label.toLowerCase().indexOf(qCtx) !== -1) {
                    out.push({
                        name: "as contexte " + c.id,
                        desc: (c.id === Theme.activeContext ? "Actif · " : "") + c.label + " — " + c.desc,
                        icon: c.icon,
                        kind: "as",
                        asAction: "contexte",
                        asArg: c.id
                    })
                }
            }
            return out
        }

        const catalog = [
            { name: "as dnd", desc: Theme.doNotDisturb ? "Désactiver Ne Pas Déranger" : "Activer Ne Pas Déranger", icon: Theme.doNotDisturb ? "bell" : "bell-off", kind: "as", asAction: "dnd" },
            { name: "as caffeine", desc: Theme.caffeineActif ? "Désactiver Caffeine" : "Activer Caffeine (empêche la veille)", icon: "coffee", kind: "as", asAction: "caffeine" },
            { name: "as nuit", desc: "Basculer le mode nuit (ou « as nuit 3500 »)", icon: "weather-night", kind: "as", asAction: "nuit" },
            { name: "as theme", desc: "Choisir un jeu de couleurs (ou « as theme <nom> »)", icon: "palette", kind: "as", asAction: "theme_picker" },
            { name: "as fond", desc: "Ouvrir le sélecteur de fond d'écran", icon: "image", kind: "as", asAction: "fond" },
            { name: "as barre", desc: Theme.barStyle === "island" ? "Passer en barre classique" : "Passer en Îlot dynamique", icon: "widgets", kind: "as", asAction: "barre" },
            { name: "as widgets", desc: Theme.widgetsBureauVisibles ? "Masquer les widgets du bureau" : "Afficher les widgets du bureau", icon: "widgets", kind: "as", asAction: "widgets" },
            { name: "as energie", desc: "Profil d'énergie (perf / equilibre / eco)", icon: "battery", kind: "as", asAction: "prefill_as", asArg: "as energie " },
            { name: "as timer", desc: "Lancer un minuteur (ex. « as timer 25 »)", icon: "clock", kind: "as", asAction: "prefill_as", asArg: "as timer 25" },
            { name: "as contexte", desc: "Activer un contexte de travail", icon: "cog", kind: "as", asAction: "prefill_as", asArg: "as contexte " },
            { name: "as reload", desc: "Recharger Hyprland et redémarrer Quickshell", icon: "refresh", kind: "as", asAction: "reload" },
            { name: "as verrouiller", desc: "Verrouiller la session (hyprlock)", icon: "lock", kind: "as", asAction: "verrouiller" },
            { name: "as veille", desc: "Mettre le système en veille", icon: "sleep", kind: "as", asAction: "veille" },
            { name: "as redemarrer", desc: "Redémarrer l'ordinateur", icon: "restart", kind: "as", asAction: "redemarrer" },
            { name: "as eteindre", desc: "Éteindre l'ordinateur", icon: "power", kind: "as", asAction: "eteindre" }
        ]

        if (rl === "") return catalog
        for (let i = 0; i < catalog.length; i++) {
            const item = catalog[i]
            if (item.name.toLowerCase().indexOf(rl) !== -1 || item.desc.toLowerCase().indexOf(rl) !== -1) {
                out.push(item)
            }
        }
        return out
    }

    function runAsCommand(entry) {
        if (!entry || !entry.asAction) return
        const act = entry.asAction
        if (act === "prefill_as" && entry.asArg) {
            launcherInput.text = String(entry.asArg)
            launcherInput.cursorPosition = launcherInput.text.length
            return
        }
        Theme.islandLauncherOpen = false
        if (act === "dnd") {
            Theme.doNotDisturb = !Theme.doNotDisturb
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "style", "do_not_disturb", Theme.doNotDisturb ? "true" : "false"])
        } else if (act === "caffeine") {
            Theme.caffeineActif = !Theme.caffeineActif
        } else if (act === "nuit") {
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/nuit_service.py"), "basculer"])
        } else if (act === "nuit_temp") {
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/nuit_service.py"), "temperature", String(entry.asArg)])
        } else if (act === "barre") {
            const next = Theme.barStyle === "island" ? "classic" : "island"
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "style", "bar_style", next])
        } else if (act === "widgets") {
            Theme.widgetsBureauVisibles = !Theme.widgetsBureauVisibles
        } else if (act === "theme_picker") {
            Theme.themePickerOpen = true
        } else if (act === "theme_apply" && entry.asArg) {
            root.applyThemeScheme(String(entry.asArg))
        } else if (act === "fond") {
            Theme.wallpaperPickerOpen = true
        } else if (act === "energie" && entry.asArg) {
            Quickshell.execDetached(["powerprofilesctl", "set", String(entry.asArg)])
        } else if (act === "reload") {
            Quickshell.execDetached(["sh", "-c", "hyprctl reload && systemctl --user restart quickshell.service"])
        } else if (act === "verrouiller") {
            Quickshell.execDetached(["sh", "-c", "hyprlock || loginctl lock-session"])
        } else if (act === "veille") {
            Quickshell.execDetached(["systemctl", "suspend"])
        } else if (act === "redemarrer") {
            Quickshell.execDetached(["systemctl", "reboot"])
        } else if (act === "eteindre") {
            Quickshell.execDetached(["systemctl", "poweroff"])
        } else if (act === "timer" && entry.asArg) {
            Theme.startTimer(entry.asArg, "")
        } else if (act === "contexte" && entry.asArg) {
            Theme.applyContext(String(entry.asArg))
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // LIVE ACTIVITY (wf-recorder, minuteur, téléchargements navigateurs, IPC)
    // ──────────────────────────────────────────────────────────────────────
    property var liveRecording: ({ active: false, elapsedSec: 0, pid: 0 })
    property var liveUpdate: ({ active: false, elapsedSec: 0, pid: 0, tool: "" })
    property var liveDownloads: []

    Process {
        id: liveActivityProbeProc
        command: ["python3", Quickshell.shellPath("core/live_activity_probe.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim() || "{}")
                    if (parsed.recording) root.liveRecording = parsed.recording
                    if (parsed.pkgUpdate) root.liveUpdate = parsed.pkgUpdate
                    else if (parsed.archUpdate) root.liveUpdate = parsed.archUpdate
                    root.liveDownloads = Array.isArray(parsed.downloads) ? parsed.downloads : []
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: Theme.barStyle === "island"
        triggeredOnStart: true
        onTriggered: if (!liveActivityProbeProc.running) liveActivityProbeProc.running = true
    }

    function formatLiveDuration(sec) {
        const s = Math.max(0, Math.round(Number(sec) || 0))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(r)) : (pad(m) + ":" + pad(r))
    }

    readonly property var liveActivities: {
        const list = []
        if (root.liveRecording && root.liveRecording.active) {
            list.push({
                id: "wf-recorder",
                kind: "record",
                title: "REC " + root.formatLiveDuration(root.liveRecording.elapsedSec),
                subtitle: "Enregistrement écran en cours",
                etaText: "Écoulé " + root.formatLiveDuration(root.liveRecording.elapsedSec),
                progress: -1,
                color: "#ef4444"
            })
        }
        if (Theme.timerRunning) {
            const pct = Theme.timerTotalSec > 0
                ? Math.max(0, Math.min(100, Math.round(100 * (Theme.timerTotalSec - Theme.timerRemainingSec) / Theme.timerTotalSec)))
                : 0
            list.push({
                id: "timer",
                kind: "timer",
                title: (Theme.timerPaused ? "⏸ " : "") + root.formatLiveDuration(Theme.timerRemainingSec),
                subtitle: Theme.timerLabel,
                etaText: "Reste ~ " + root.formatLiveDuration(Theme.timerRemainingSec),
                progress: pct,
                paused: Theme.timerPaused,
                color: Theme.accent
            })
        }
        if (root.liveUpdate && root.liveUpdate.active) {
            const u = root.liveUpdate
            const tool = u.tool || "paquets"
            const rem = (u.remainingPkgs !== undefined && u.remainingPkgs !== null) ? Number(u.remainingPkgs) : -1
            const p = (u.progress !== undefined && u.progress !== null) ? Number(u.progress) : -1
            const etaS = (u.etaSec !== undefined && u.etaSec !== null) ? Number(u.etaSec) : -1
            const needIn = Boolean(u.needsInput)
            const etaParts = []
            if (p >= 0) etaParts.push(p + "%")
            if (rem >= 0) etaParts.push(rem + " paq.")
            if (etaS > 0) etaParts.push("~ " + root.formatLiveDuration(etaS))
            else etaParts.push(root.formatLiveDuration(u.elapsedSec))

            list.push({
                id: "arch-update",
                kind: "update",
                pid: u.pid || 0,
                title: needIn ? ("MàJ · Action! " + root.formatLiveDuration(u.elapsedSec)) : ("MàJ " + root.formatLiveDuration(u.elapsedSec)),
                subtitle: needIn
                    ? ("Intervention requise dans le terminal (" + tool + ")")
                    : ("Mise à jour (" + tool + ")" + (rem >= 0 ? (" · " + rem + " paquet" + (rem > 1 ? "s" : "") + " restant" + (rem > 1 ? "s" : "")) : "")),
                etaText: etaParts.join(" · "),
                progress: p,
                color: needIn ? "#ef4444" : Theme.warn
            })
        }
        const dls = Array.isArray(root.liveDownloads) ? root.liveDownloads : []
        for (let i = 0; i < dls.length; i++) {
            const d = dls[i]
            if (!d || !d.name) continue
            const p = (d.progress !== undefined && d.progress !== null) ? Number(d.progress) : -1
            const sizeInfo = d.totalStr ? (d.sizeStr + " / " + d.totalStr) : (d.sizeStr || "")
            const parts = []
            if (p >= 0) parts.push(p + "%")
            if (d.speedStr) parts.push(d.speedStr)
            if (d.etaSec !== undefined && Number(d.etaSec) > 0) parts.push("~ " + root.formatLiveDuration(d.etaSec))
            const eta = parts.length > 0 ? parts.join(" · ") : (sizeInfo || "En cours")
            list.push({
                id: "dl:" + d.name,
                kind: "download",
                title: d.name + (p >= 0 ? (" · " + p + "%") : ""),
                subtitle: "Téléchargement · " + (sizeInfo || "en cours") + (d.speedStr ? (" · " + d.speedStr) : ""),
                etaText: eta,
                progress: p,
                color: Theme.info
            })
        }
        const ipcs = Array.isArray(Theme.ipcActivities) ? Theme.ipcActivities : []
        for (let j = 0; j < ipcs.length; j++) {
            const x = ipcs[j]
            if (!x || !x.id) continue
            const p = Number(x.progress)
            let eta = p >= 0 ? (p + "%") : "En cours"
            if (p > 0 && p < 100 && x.startedAt > 0) {
                const el = Math.max(1, (Date.now() - Number(x.startedAt)) / 1000.0)
                const rem = Math.round(el * (100 - p) / p)
                eta = p + "% · ~ " + root.formatLiveDuration(rem)
            }
            list.push({
                id: x.id,
                kind: "ipc",
                title: String(x.title || x.id) + (p >= 0 ? (" · " + p + "%") : ""),
                subtitle: "Tâche en arrière-plan",
                etaText: eta,
                progress: p,
                color: Theme.accent
            })
        }
        return list
    }

    readonly property var compactBarsList: root.liveActivities.slice(0, 3)
    readonly property real compactExtraHeight: (!Theme.osdVisible && root.compactBarsList.length > 1)
        ? (root.compactBarsList.length * 3 + 2)
        : 0

    property bool pretGrabLiveActivity: false
    onLiveActivityExpandedChanged: {
        if (liveActivityExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabLiveActivity = false
            delaiGrabLiveActivity.restart()
            liveActivityContainer.forceActiveFocus()
        } else {
            delaiGrabLiveActivity.stop()
            pretGrabLiveActivity = false
            if (!isHovered && !isPopupOpen && !panelOpen) retractTimer.restart()
        }
    }

    Timer {
        id: delaiGrabLiveActivity
        interval: 150
        repeat: false
        onTriggered: if (root.liveActivityExpanded) root.pretGrabLiveActivity = true
    }

    HyprlandFocusGrab {
        active: root.liveActivityExpanded && root.pretGrabLiveActivity
        windows: (root.QsWindow && root.QsWindow.window) ? [root.QsWindow.window] : []
        onCleared: {
            if (Theme.islandLiveActivityOpen) Theme.islandLiveActivityOpen = false
        }
    }

    readonly property var launcherResults: {
        const q = root.launcherQuery.trim()
        const qlRaw = q.toLowerCase()
        if (qlRaw === "as" || qlRaw.indexOf("as ") === 0) {
            return root.asCommands(q.slice(2)).slice(0, 8)
        }
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
        if (entry.kind === "as") {
            root.runAsCommand(entry)
            return
        }
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
        Theme.themePickerOpen = false
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
    readonly property real themePickerHeight: 164
    readonly property real liveActivityWidth: 480
    readonly property real liveActivityHeight: Math.min(380, 74 + Math.max(1, root.liveActivities.length) * 68 + 14)
    readonly property real compactTotalHeight: Theme.barHeight + (root.expanded ? 0 : root.compactExtraHeight)
    implicitHeight: panelOpen ? 420 : (notifToastActive ? toastHeight : (liveActivityExpanded ? liveActivityHeight : (themeExpanded ? themePickerHeight : (notesExpanded ? notesHeight : (launcherExpanded ? launcherHeight : (wallpaperExpanded ? wallpaperHeight : (meteoExpanded ? meteoHeight : compactTotalHeight)))))))
    height: panelOpen ? 420 : (notifToastActive ? toastHeight : (liveActivityExpanded ? liveActivityHeight : (themeExpanded ? themePickerHeight : (notesExpanded ? notesHeight : (launcherExpanded ? launcherHeight : (wallpaperExpanded ? wallpaperHeight : (meteoExpanded ? meteoHeight : compactTotalHeight)))))))
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
    readonly property real themePickerWidth: 780
    readonly property real expandedWidth: Math.max(
        compactRestWidth,
        fullContentRow.implicitWidth + Theme.padH * 2
    )

    readonly property int sidePanelWidth: (panelOpen && Theme.islandSidePanel !== "") ? 340 : 0
    width: panelOpen ? (680 + sidePanelWidth) : (notifToastActive ? 400 : (liveActivityExpanded ? liveActivityWidth : (themeExpanded ? themePickerWidth : (notesExpanded ? notesWidth : (launcherExpanded ? launcherWidth : (wallpaperExpanded ? wallpaperWidth : (meteoExpanded ? meteoWidth : (expanded ? expandedWidth : compactWidth))))))))

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
        rayon: root.panelOpen ? Math.max(Theme.pillRadius, 18) : ((root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded || root.themeExpanded) ? Math.max(Theme.globalRadius, 16) : Theme.pillRadius)
        Behavior on rayon { NumberAnimation { duration: Math.max(80, Theme.panelAnimDuration - 20); easing.type: Easing.OutCubic } }
        teinte: (root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded || root.themeExpanded) ? Theme.surfaceBg : Theme.barBg
        bordureCouleur: (root.isCalendarOpen || root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded || root.themeExpanded) ? Theme.accentMuted : Theme.accent
        bordureLargeur: Theme.barBorder ? 1 : 0
        actif: root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded || root.themeExpanded || root.liveActivityExpanded
    }

    // ──────────────────────────────────────────────────────────────────────
    // CONTENU COMPACT (AU REPOS)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: compactContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.compactTotalHeight
        clip: true
        opacity: (root.expanded || root.panelOpen || root.notifToastActive || root.meteoExpanded || root.wallpaperExpanded || root.launcherExpanded || root.notesExpanded || root.themeExpanded || root.liveActivityExpanded) ? 0.0 : 1.0
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
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            height: Theme.barHeight
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

            // Badge contexte actif (si différent de « normal »)
            Rectangle {
                visible: Theme.activeContext !== "" && Theme.activeContext !== "normal"
                height: Math.max(18, Theme.barHeight - 8)
                width: ctxPillTxt.implicitWidth + 12
                radius: Math.round(height / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.alpha(Theme.accent, 0.16)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.4)

                Text {
                    id: ctxPillTxt
                    anchors.centerIn: parent
                    text: {
                        const ctxs = Theme.workContexts || []
                        for (let i = 0; i < ctxs.length; i++) {
                            if (ctxs[i].id === Theme.activeContext) return ctxs[i].label
                        }
                        return Theme.activeContext
                    }
                    font.family: Theme.fontUi
                    font.pixelSize: Math.max(8, Math.round(10 * Theme.barScale))
                    font.weight: Font.Bold
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            // Live Activity (enregistrement, minuteur, téléchargements, tâches IPC)
            Rectangle {
                id: liveActivityPill
                visible: root.liveActivities.length > 0
                readonly property var primary: root.liveActivities.length > 0 ? root.liveActivities[0] : null
                height: Math.max(18, Theme.barHeight - 8)
                width: liveActRow.implicitWidth + 12
                radius: Math.round(height / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: primary ? Qt.alpha(primary.color, 0.16) : "transparent"
                border.width: 1
                border.color: primary ? Qt.alpha(primary.color, 0.45) : "transparent"

                Row {
                    id: liveActRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        id: livePulseDot
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: liveActivityPill.primary ? liveActivityPill.primary.color : Theme.accent
                        SequentialAnimation on opacity {
                            running: liveActivityPill.visible && !(liveActivityPill.primary && liveActivityPill.primary.paused)
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const p = liveActivityPill.primary
                            if (!p) return ""
                            const t = String(p.title || "")
                            return t.length > 16 ? (t.substring(0, 15) + "…") : t
                        }
                        font.family: Theme.fontUi
                        font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                        font.weight: Font.Bold
                        color: liveActivityPill.primary ? liveActivityPill.primary.color : Theme.fg
                    }

                    Rectangle {
                        visible: root.liveActivities.length > 1
                        width: liveCountTxt.implicitWidth + 8
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: liveActivityPill.primary ? liveActivityPill.primary.color : Theme.accent

                        Text {
                            id: liveCountTxt
                            anchors.centerIn: parent
                            text: "+" + (root.liveActivities.length - 1)
                            font.family: Theme.fontUi
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.bg
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.toggleLiveActivity()
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

        // Seconde barre (et +) vers le bas pour les téléchargements / activités secondaires
        // Barres de progression fines (2px, espacées de 1px) collées en bas de la pilule
        // Barres de progression fines (2px, espacées de 1px) collées en bas de la pilule
        Column {
            id: compactBarsCol
            visible: root.compactBarsList.length > 0 && !Theme.osdVisible
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.max(12, Math.round(Theme.globalRadius * 0.7))
            anchors.rightMargin: Math.max(12, Math.round(Theme.globalRadius * 0.7))
            spacing: 1

            Repeater {
                model: root.compactBarsList
                delegate: Rectangle {
                    required property var modelData
                    width: compactBarsCol.width
                    height: 2
                    radius: 1
                    color: Qt.alpha(Theme.fg, 0.14)
                    clip: true

                    Rectangle {
                        height: parent.height
                        radius: 1
                        color: modelData.color || Theme.accent
                        readonly property real p: Number(modelData.progress)
                        width: p >= 0 ? Math.round(parent.width * Math.max(0, Math.min(100, p)) / 100.0) : Math.round(parent.width * 0.34)
                        x: p >= 0 ? 0 : indOff
                        property real indOff: 0
                        SequentialAnimation on indOff {
                            running: compactBarsCol.visible && Number(modelData.progress) < 0
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: Math.max(0, compactBarsCol.width * 0.66); duration: 1050; easing.type: Easing.InOutSine }
                            NumberAnimation { from: Math.max(0, compactBarsCol.width * 0.66); to: 0; duration: 1050; easing.type: Easing.InOutSine }
                        }
                    }
                }
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
        opacity: (root.expanded && !root.panelOpen && !root.notifToastActive && !root.meteoExpanded && !root.wallpaperExpanded && !root.launcherExpanded && !root.notesExpanded && !root.themeExpanded && !root.liveActivityExpanded && root.width >= root.expandedWidth - 16) ? 1.0 : 0.0
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

            // Live Activity visible aussi en mode étendu (au survol)
            Rectangle {
                id: expandedLiveActivityPill
                visible: root.liveActivities.length > 0
                readonly property var primary: root.liveActivities.length > 0 ? root.liveActivities[0] : null
                height: Math.max(18, Theme.barHeight - 8)
                width: expLiveRow.implicitWidth + 12
                radius: Math.round(height / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: primary ? Qt.alpha(primary.color, 0.16) : "transparent"
                border.width: 1
                border.color: primary ? Qt.alpha(primary.color, 0.45) : "transparent"

                Row {
                    id: expLiveRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: expandedLiveActivityPill.primary ? expandedLiveActivityPill.primary.color : Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const p = expandedLiveActivityPill.primary
                            if (!p) return ""
                            const t = String(p.title || "")
                            return t.length > 16 ? (t.substring(0, 15) + "…") : t
                        }
                        font.family: Theme.fontUi
                        font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                        font.weight: Font.Bold
                        color: expandedLiveActivityPill.primary ? expandedLiveActivityPill.primary.color : Theme.fg
                    }

                    Rectangle {
                        visible: root.liveActivities.length > 1
                        width: expLiveCnt.implicitWidth + 8
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: expandedLiveActivityPill.primary ? expandedLiveActivityPill.primary.color : Theme.accent

                        Text {
                            id: expLiveCnt
                            anchors.centerIn: parent
                            text: "+" + (root.liveActivities.length - 1)
                            font.family: Theme.fontUi
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.bg
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.toggleLiveActivity()
                }
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
    // SÉLECTEUR DE JEU DE COULEURS INLINE (SUPER + C)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: themeContainer
        anchors.fill: parent
        clip: true
        focus: root.themeExpanded
        Keys.onEscapePressed: Theme.themePickerOpen = false
        Keys.onLeftPressed: root.handleThemeNav("prev")
        Keys.onRightPressed: root.handleThemeNav("next")
        Keys.onReturnPressed: root.handleThemeNav("apply")
        opacity: root.themeExpanded ? 1.0 : 0.0
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
                    readonly property bool isSelected: index === root.themeSelectedIdx

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
                        onEntered: root.themeSelectedIdx = index
                        onClicked: {
                            root.themeSelectedIdx = index
                            root.applyThemeScheme(modelData)
                        }
                    }
                }
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // EXTENSION INLINE LIVE ACTIVITY (TÂCHES LONGUES, MINUTEUR, REC, DL)
    // ──────────────────────────────────────────────────────────────────────
    Item {
        id: liveActivityContainer
        anchors.fill: parent
        clip: true
        focus: root.liveActivityExpanded
        Keys.onEscapePressed: Theme.islandLiveActivityOpen = false
        opacity: root.liveActivityExpanded ? 1.0 : 0.0
        visible: opacity > 0.05
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Icon {
                    glyph: "clock"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: "Activités en cours (" + root.liveActivities.length + ")"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.bold: true
                    color: Theme.fg
                }

                Rectangle {
                    id: p5Btn
                    property bool hovered: false
                    width: 40
                    height: 22
                    radius: 6
                    color: (root.liveActivityExpanded && hovered) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.55)
                    Text { anchors.centerIn: parent; text: "+5m"; font.family: Theme.fontUi; font.pixelSize: Theme.text2xs; font.bold: true; color: Theme.accent }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: root.liveActivityExpanded
                        cursorShape: Qt.PointingHandCursor
                        onEntered: p5Btn.hovered = true
                        onExited: p5Btn.hovered = false
                        onClicked: { p5Btn.hovered = false; Theme.startTimer(5, "Minuteur 5m") }
                    }
                }

                Rectangle {
                    id: p25Btn
                    property bool hovered: false
                    width: 46
                    height: 22
                    radius: 6
                    color: (root.liveActivityExpanded && hovered) ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.55)
                    Text { anchors.centerIn: parent; text: "+25m"; font.family: Theme.fontUi; font.pixelSize: Theme.text2xs; font.bold: true; color: Theme.accent }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: root.liveActivityExpanded
                        cursorShape: Qt.PointingHandCursor
                        onEntered: p25Btn.hovered = true
                        onExited: p25Btn.hovered = false
                        onClicked: { p25Btn.hovered = false; Theme.startTimer(25, "Pomodoro 25m") }
                    }
                }

                // Timer personnalisé (minutes)
                Rectangle {
                    width: 68
                    height: 22
                    radius: 6
                    color: Qt.alpha(Theme.bg, 0.55)
                    border.width: 1
                    border.color: customTimerInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.16)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 2
                        spacing: 2

                        TextInput {
                            id: customTimerInput
                            Layout.fillWidth: true
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            color: Theme.fg
                            horizontalAlignment: TextInput.AlignHCenter
                            validator: IntValidator { bottom: 1; top: 999 }
                            maximumLength: 3
                            selectByMouse: true
                            Keys.onEscapePressed: Theme.islandLiveActivityOpen = false
                            onAccepted: {
                                const m = parseInt(text, 10)
                                if (!isNaN(m) && m > 0) {
                                    Theme.startTimer(m, "Minuteur " + m + "m")
                                    text = ""
                                }
                            }

                            Text {
                                visible: customTimerInput.text === ""
                                anchors.centerIn: parent
                                text: "min"
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                color: Qt.alpha(Theme.fg, 0.42)
                            }
                        }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 5
                            color: customGoMa.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)
                            Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 8; color: Theme.accent }
                            MouseArea {
                                id: customGoMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const m = parseInt(customTimerInput.text, 10)
                                    if (!isNaN(m) && m > 0) {
                                        Theme.startTimer(m, "Minuteur " + m + "m")
                                        customTimerInput.text = ""
                                    } else {
                                        customTimerInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: 22
                    height: 22
                    radius: 6
                    color: laCloseMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.surfaceVariant, 0.45)
                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 10; font.bold: true; color: laCloseMa.containsMouse ? Theme.error : Theme.fg }
                    MouseArea { id: laCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Theme.islandLiveActivityOpen = false }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.fg, 0.1) }

            Text {
                visible: root.liveActivities.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "Aucune activité longue en cours"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.5)
            }

            ListView {
                visible: root.liveActivities.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                clip: true
                model: root.liveActivities

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool canFocusWindow: modelData.kind === "update" || modelData.kind === "download"
                    width: ListView.view.width
                    height: 62
                    radius: Math.max(8, Math.round(Theme.globalRadius * 0.55))
                    color: (canFocusWindow && laCardMa.containsMouse)
                        ? Qt.alpha(Theme.surfaceVariant, 0.72)
                        : Qt.alpha(Theme.surfaceVariant, 0.42)
                    border.width: 1
                    border.color: Qt.alpha(modelData.color || Theme.accent, (canFocusWindow && laCardMa.containsMouse) ? 0.65 : 0.32)

                    MouseArea {
                        id: laCardMa
                        anchors.fill: parent
                        enabled: canFocusWindow
                        hoverEnabled: canFocusWindow
                        cursorShape: canFocusWindow ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            Theme.islandLiveActivityOpen = false
                            Quickshell.execDetached([
                                "python3", Quickshell.shellPath("core/live_activity_probe.py"),
                                "--focus", String(modelData.kind), String(modelData.pid || 0)
                            ])
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.color || Theme.accent
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.title || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.subtitle || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.text2xs
                                    color: Qt.alpha(Theme.fg, 0.65)
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: String(modelData.etaText || "") !== ""
                                Layout.preferredWidth: etaBadgeTxt.implicitWidth + 12
                                Layout.preferredHeight: 20
                                radius: 6
                                color: Qt.alpha(modelData.color || Theme.accent, 0.16)

                                Text {
                                    id: etaBadgeTxt
                                    anchors.centerIn: parent
                                    text: String(modelData.etaText || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.text2xs
                                    font.bold: true
                                    color: modelData.color || Theme.accent
                                }
                            }

                            Rectangle {
                                visible: modelData.kind === "timer"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                radius: 6
                                color: pauseMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.65)
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.paused ? "▶" : "⏸"
                                    font.pixelSize: 10
                                    color: Theme.fg
                                }
                                MouseArea {
                                    id: pauseMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Theme.togglePauseTimer()
                                }
                            }

                            Rectangle {
                                visible: modelData.kind === "record" || modelData.kind === "timer" || modelData.kind === "ipc"
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 22
                                Layout.alignment: Qt.AlignVCenter
                                radius: 6
                                color: stopMa.containsMouse ? Qt.alpha(Theme.error, 0.28) : Qt.alpha(Theme.surfaceVariant, 0.65)
                                Text {
                                    anchors.centerIn: parent
                                    text: "■"
                                    font.pixelSize: 10
                                    color: stopMa.containsMouse ? Theme.error : Theme.fg
                                }
                                MouseArea {
                                    id: stopMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.kind === "record") {
                                            Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"])
                                        } else if (modelData.kind === "timer") {
                                            Theme.stopTimer()
                                        } else if (modelData.kind === "ipc") {
                                            Theme.handleLiveActivity("stop", modelData.id, "", -1)
                                        }
                                    }
                                }
                            }
                        }

                        // Barre de chargement agrandie (6px) avec animation si indéterminée
                        Rectangle {
                            id: laBarTrack
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Qt.alpha(Theme.fg, 0.14)
                            clip: true

                            Rectangle {
                                height: parent.height
                                radius: 3
                                color: modelData.color || Theme.accent
                                readonly property real p: Number(modelData.progress)
                                width: p >= 0 ? Math.round(parent.width * Math.max(0, Math.min(100, p)) / 100.0) : Math.round(parent.width * 0.32)
                                x: p >= 0 ? 0 : laIndOff
                                property real laIndOff: 0
                                SequentialAnimation on laIndOff {
                                    running: root.liveActivityExpanded && Number(modelData.progress) < 0
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: Math.max(0, laBarTrack.width * 0.68); duration: 1050; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: Math.max(0, laBarTrack.width * 0.68); to: 0; duration: 1050; easing.type: Easing.InOutSine }
                                }
                            }
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