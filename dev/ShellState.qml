pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // ──────────────────────────────────────────────────────────────────────────
    // SUBMAP HYPRLAND & HOOKS SHELL/IPC
    // ──────────────────────────────────────────────────────────────────────────
    property string activeSubmap: ""

    function setSubmap(name) {
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.submap("' + name + '")')
        } else {
            Hyprland.dispatch("submap " + name)
        }
    }

    property var wallpaperNavHook: null
    property var themeNavHook: null
    property var islandNavHook: null
    property var placeWidgetHook: null
    property var widgetMenuHook: null
    property var captureHook: null

    // ──────────────────────────────────────────────────────────────────────────
    // NOTIFICATIONS (état partagé + crochets IPC)
    // ──────────────────────────────────────────────────────────────────────────
    property int notifCount: 0
    property var quietNotifApps: []
    property bool doNotDisturb: false
    property var notifList: []
    property var notifArchive: []
    property var notifOps: ({})
    property var notifToast: null
    property bool notifToastVisible: false
    property bool notifToastHovered: false
    property bool notifHistoryVisible: false
    property var notifTargetsHook: null
    property var notifOpenHook: null
    property var notifClearHook: null
    property var notifInvokeHook: null

    // ──────────────────────────────────────────────────────────────────────────
    // FOND D'ÉCRAN COURANT PARTAGÉ (awww query)
    // ──────────────────────────────────────────────────────────────────────────
    property string wallpaperCourant: ""
    property double wallpaperLockUntil: 0

    function setWallpaperCourant(path) {
        if (!path) return
        root.wallpaperLockUntil = Date.now() + 4500
        root.wallpaperCourant = String(path)
    }

    property Process wallpaperSondeProc: Process {
        command: ["awww", "query"]
        running: Theme.depthWallpaper || Theme.depthMask
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() < root.wallpaperLockUntil) return
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) root.wallpaperCourant = m[1]
            }
        }
    }

    function rafraichirWallpaper() {
        if (Date.now() < root.wallpaperLockUntil) return
        if (!wallpaperSondeProc.running) wallpaperSondeProc.running = true
    }

    property Timer wallpaperSondeTimer: Timer {
        interval: 2500
        repeat: true
        running: Theme.depthWallpaper || Theme.depthMask
        triggeredOnStart: true
        onTriggered: root.rafraichirWallpaper()
    }

    // ──────────────────────────────────────────────────────────────────────────
    // OSD (ON-SCREEN DISPLAY)
    // ──────────────────────────────────────────────────────────────────────────
    property bool osdVisible: false
    property string osdKind: ""     // "volume" | "brightness" | "mute"
    property real osdValue: 0       // 0..100
    readonly property string osdGlyph: osdKind === "brightness" ? "brightness"
        : osdKind === "mute" ? "volume-off"
        : (osdValue <= 0 ? "mute" : osdValue < 50 ? "volume-medium" : "volume-high")
    readonly property string osdLabel: osdKind === "brightness" ? "Luminosité"
        : osdKind === "mute" ? "Micro coupé"
        : (osdValue <= 0 ? "Volume coupé" : "Volume")
    readonly property string osdPercent: Math.round(osdValue) + "%"
    signal volumeUpdated()

    property Connections hyprEvents: Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (Theme.activePopup !== "") Theme.activePopup = ""
        }
        function onRawEvent(event) {
            if (event && event.name === "submap") {
                root.activeSubmap = String(event.data || "").trim()
            }
        }
    }

    property Timer osdTimer: Timer {
        interval: 1600
        repeat: false
        onTriggered: root.osdVisible = false
    }

    function showOsd(kind, value) {
        root.osdKind = kind
        root.osdValue = Math.max(0, Math.min(100, value))
        root.osdVisible = true
        root.osdTimer.restart()
        if (kind === "volume") root.volumeUpdated()
    }

    // ──────────────────────────────────────────────────────────────────────────
    // WIDGETS DE BUREAU (core/widgets.json)
    // ──────────────────────────────────────────────────────────────────────────
    property var widgets: []

    property FileView widgetsFile: FileView {
        path: Quickshell.shellPath("core/widgets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.widgets = Array.isArray(parsed.widgets) ? parsed.widgets : []
            } catch (e) {
                console.warn("ShellState.qml: Failed to parse core/widgets.json:", e)
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // REGISTRE DES APPLETS DE BARRE (bar_applets.json + applets_catalogue.json)
    // ──────────────────────────────────────────────────────────────────────────
    property var barAppletsCatalogue: []
    property var barAppletsActifs: ({})
    property int barAppletsRev: 0

    readonly property var barAnciens: ({
        "gauche": "haut:debut", "centre": "haut:milieu", "droite": "haut:fin",
        "haut-gauche": "haut:debut", "haut-centre": "haut:milieu", "haut-droite": "haut:fin",
        "bas": "bas:milieu",
        "cote-gauche": "cote-gauche:milieu",
        "cote-droite": "cote-droite:milieu"
    })

    property FileView appletsCatalogueFile: FileView {
        path: Quickshell.shellPath("core/applets_catalogue.json")
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.barAppletsCatalogue = (d && Array.isArray(d.applets)) ? d.applets : []
                root.barAppletsRev++
            } catch (e) {
                root.barAppletsCatalogue = []
            }
        }
    }

    property FileView barAppletsFile: FileView {
        path: Quickshell.shellPath("core/bar_applets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                const rawActifs = (d && typeof d.actifs === "object" && d.actifs) ? d.actifs : ({})
                const normActifs = ({})
                for (const cle in rawActifs) {
                    const item = Object.assign({}, rawActifs[cle])
                    if (item.ile && root.barAnciens[item.ile]) {
                        item.ile = root.barAnciens[item.ile]
                    }
                    normActifs[cle] = item
                }
                root.barAppletsActifs = normActifs
                root.barAppletsRev++
            } catch (e) {
                root.barAppletsActifs = ({})
            }
        }
    }

    function _buildAppletEntry(cat, choix, itemIle) {
        const entree = Object.assign({}, cat)
        entree.actif = true
        entree.ile = itemIle
        const ordre = parseInt(choix.ordre, 10)
        entree.ordre = isNaN(ordre) ? (cat.ordre || 100) : ordre
        const echelle = parseInt(choix.text_scale, 10)
        entree.text_scale = isNaN(echelle) ? 100 : Math.max(60, Math.min(160, echelle))
        entree.options = choix.options || ({})
        return entree
    }

    function _sortApplets(liste) {
        const ord = Array.isArray(Theme.ilotAppletsOrder) ? Theme.ilotAppletsOrder : []
        liste.sort(function(a, b) {
            const ia = ord.indexOf(String(a.id || ""))
            const ib = ord.indexOf(String(b.id || ""))
            if (ia !== -1 && ib !== -1) return ia - ib
            if (ia !== -1) return -1
            if (ib !== -1) return 1
            const oa = (typeof a.ordre === "number") ? a.ordre : 100
            const ob = (typeof b.ordre === "number") ? b.ordre : 100
            if (oa !== ob) return oa - ob
            return String(a.id || "").localeCompare(String(b.id || ""))
        })
        return liste
    }

    function appletsPourIle(ile) {
        const _ = root.barAppletsRev
        if (!ile || !root.barAppletsCatalogue.length) return []
        const cible = root.barAnciens[ile] || ile
        const liste = []
        for (let i = 0; i < root.barAppletsCatalogue.length; i++) {
            const cat = root.barAppletsCatalogue[i]
            if (!cat || !cat.id || cat.fixe) continue
            const choix = root.barAppletsActifs[cat.id]
            if (!choix) continue

            let itemIle = String(choix.ile || cat.ile || "haut:fin")
            itemIle = root.barAnciens[itemIle] || itemIle
            if (itemIle !== cible) continue

            liste.push(root._buildAppletEntry(cat, choix, itemIle))
        }
        return root._sortApplets(liste)
    }

    function appletsPourIlot(state, side) {
        const _ = root.barAppletsRev + Theme.ilotAppletsRev
        if (!root.barAppletsCatalogue.length) return []
        const liste = []
        for (let i = 0; i < root.barAppletsCatalogue.length; i++) {
            const cat = root.barAppletsCatalogue[i]
            if (!cat || !cat.id || cat.fixe) continue
            if (cat.id === "visualiseur" || cat.id === "workspaces" || cat.id === "horloge" || cat.id === "musique") continue
            const mode = Theme.ilotAppletModeFor(cat.id)
            if (!Theme.ilotVisibleIn(mode, state)) continue

            const choix = root.barAppletsActifs[cat.id] || ({})
            let itemIle = String(choix.ile || cat.ile || "haut:fin")
            itemIle = root.barAnciens[itemIle] || itemIle
            if (side === "left" && itemIle !== "haut:debut") continue
            if (side === "right" && itemIle === "haut:debut") continue

            liste.push(root._buildAppletEntry(cat, choix, itemIle))
        }
        return root._sortApplets(liste)
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CONTEXTES DE TRAVAIL (manuels : îlot, commande `as contexte`, IPC)
    // ──────────────────────────────────────────────────────────────────────────
    property string activeContext: "normal"
    readonly property var workContexts: [
        { id: "normal",  label: "Normal",       desc: "DND off · Équilibré · Widgets visibles",           icon: "widgets",       dnd: false, caffeine: false, power: "balanced",    night: false, nightTemp: 4500, widgets: true },
        { id: "focus",   label: "Focus / Code", desc: "DND on · Caffeine · Performance · Widgets masqués", icon: "cog",           dnd: true,  caffeine: true,  power: "performance", night: false, nightTemp: 4500, widgets: false },
        { id: "reunion", label: "Réunion",      desc: "DND on · Caffeine · Équilibré · Widgets masqués",   icon: "bell-off",      dnd: true,  caffeine: true,  power: "balanced",    night: false, nightTemp: 4500, widgets: false },
        { id: "detente", label: "Détente",      desc: "DND off · Nuit 3800K · Éco · Widgets visibles",     icon: "weather-night", dnd: false, caffeine: false, power: "power-saver", night: true,  nightTemp: 3800, widgets: true }
    ]

    function applyContext(ctxId) {
        const q = String(ctxId || "").trim().toLowerCase()
        const aliasMap = { "code": "focus", "travail": "focus", "meeting": "reunion", "relax": "detente" }
        const key = aliasMap[q] || q
        let found = null
        for (let i = 0; i < root.workContexts.length; i++) {
            if (root.workContexts[i].id === key) {
                found = root.workContexts[i]
                break
            }
        }
        if (!found) return false
        root.activeContext = found.id
        root.doNotDisturb = found.dnd
        SystemServices.caffeineActif = found.caffeine
        Theme.widgetsBureauVisibles = found.widgets
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/config_manager.py"), "style", "do_not_disturb", found.dnd ? "true" : "false"])
        Quickshell.execDetached(["powerprofilesctl", "set", found.power])
        if (found.night) {
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/nuit_service.py"), "temperature", String(found.nightTemp)])
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/nuit_service.py"), "activer"])
        } else {
            Quickshell.execDetached(["python3", Quickshell.shellPath("core/nuit_service.py"), "desactiver"])
        }
        return true
    }

    // ──────────────────────────────────────────────────────────────────────────
    // LIVE ACTIVITY (Îlot dynamique : minuteur, enregistrement, téléchargements, IPC)
    // ──────────────────────────────────────────────────────────────────────────
    property var ipcActivities: []
    property int timerTotalSec: 0
    property int timerRemainingSec: 0
    property bool timerRunning: false
    property bool timerPaused: false
    property string timerLabel: "Minuteur"

    property Timer liveTimerTick: Timer {
        interval: 1000
        repeat: true
        running: root.timerRunning && !root.timerPaused
        onTriggered: {
            if (root.timerRemainingSec > 1) {
                root.timerRemainingSec -= 1
            } else {
                const lbl = root.timerLabel || "Minuteur"
                root.timerRunning = false
                root.timerPaused = false
                root.timerRemainingSec = 0
                root.timerTotalSec = 0
                Quickshell.execDetached(["notify-send", "-a", "AetherShell", lbl + " terminé", "Le décompte est arrivé à 0."])
            }
        }
    }

    function startTimer(minutes, label) {
        const mins = Math.max(1, Math.round(Number(minutes) || 0))
        root.timerTotalSec = mins * 60
        root.timerRemainingSec = mins * 60
        root.timerLabel = (label && String(label).trim() !== "") ? String(label).trim() : ("Minuteur " + mins + "m")
        root.timerPaused = false
        root.timerRunning = true
    }

    function togglePauseTimer() {
        if (!root.timerRunning) return
        root.timerPaused = !root.timerPaused
    }

    function stopTimer() {
        root.timerRunning = false
        root.timerPaused = false
        root.timerRemainingSec = 0
        root.timerTotalSec = 0
    }

    function handleLiveActivity(action, actId, title, progress) {
        const a = String(action || "").toLowerCase()
        const id = String(actId || "").trim()
        if (a === "clear") {
            root.ipcActivities = []
            return "ok"
        }
        if (!id) return "missing_id"
        const list = root.ipcActivities.slice()
        const idx = list.findIndex(x => x && x.id === id)
        if (a === "stop" || a === "remove" || a === "done") {
            if (idx >= 0) {
                list.splice(idx, 1)
                root.ipcActivities = list
            }
            return "ok"
        }
        const p = (progress !== undefined && progress !== null) ? Number(progress) : -1
        const prog = isNaN(p) ? -1 : (p < 0 ? -1 : Math.max(0, Math.min(100, Math.round(p))))
        if (a === "start" || (a === "update" && idx < 0)) {
            const item = {
                id: id,
                title: String(title || id),
                progress: prog,
                startedAt: Date.now()
            }
            if (idx >= 0) list[idx] = item
            else list.push(item)
            root.ipcActivities = list
            return "ok"
        }
        if (a === "update" && idx >= 0) {
            const cur = list[idx]
            list[idx] = {
                id: id,
                title: (title !== undefined && String(title) !== "") ? String(title) : cur.title,
                progress: prog,
                startedAt: cur.startedAt || Date.now()
            }
            root.ipcActivities = list
            return "ok"
        }
        return "unknown_action"
    }

    // ──────────────────────────────────────────────────────────────────────────
    // FENÊTRES MINIMISÉES (Hyprland special:minimized)
    // ──────────────────────────────────────────────────────────────────────────
    readonly property string workspaceMinimise: "special:minimized"
    property var ordreMinimisees: []

    function cleAdresse(adresse) {
        let a = String(adresse || "").toLowerCase()
        if (a.indexOf("0x") === 0) a = a.substring(2)
        return a
    }

    function selecteurAdresse(adresse) {
        const a = root.cleAdresse(adresse)
        return a === "" ? "" : "address:0x" + a
    }

    function estMinimisee(fenetre) {
        if (!fenetre) return false
        const espace = fenetre.workspace
        if (espace) {
            const nom = String(espace.name || "")
            if (nom === root.workspaceMinimise || nom === "minimized") return true
            if (Number(espace.id) > 0) return false
        }
        const brut = fenetre.lastIpcObject
        const bws = brut ? brut.workspace : null
        return Boolean(bws) && String(bws.name || "") === root.workspaceMinimise
    }

    function fenetresMinimisees() {
        const out = []
        const tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (t && t.address && root.estMinimisee(t)) out.push(t)
        }
        const rang = function (adresse) {
            const i = root.ordreMinimisees.indexOf(root.cleAdresse(adresse))
            return i < 0 ? 1000 : i
        }
        out.sort(function (a, b) { return rang(a.address) - rang(b.address) })
        return out
    }

    function bureauCourant() {
        const ws = Hyprland.focusedWorkspace
        if (ws && Number(ws.id) > 0) return Number(ws.id)
        const m = Hyprland.focusedMonitor
        const actif = m ? m.activeWorkspace : null
        if (actif && Number(actif.id) > 0) return Number(actif.id)
        const liste = Hyprland.workspaces ? Hyprland.workspaces.values : []
        for (let i = 0; i < liste.length; i++) {
            if (liste[i] && Number(liste[i].id) > 0 && liste[i].active) return Number(liste[i].id)
        }
        return 0
    }

    function minimiserFenetre(adresse) {
        let cible = root.cleAdresse(adresse)
        if (cible === "" && Hyprland.activeToplevel)
            cible = root.cleAdresse(Hyprland.activeToplevel.address)
        if (Hyprland.usingLua) {
            const sel = cible !== "" ? ', window = "' + root.selecteurAdresse(cible) + '"' : ""
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + root.workspaceMinimise + '"'
                             + sel + ', follow = false })')
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + root.workspaceMinimise
                              + (cible !== "" ? "," + root.selecteurAdresse(cible) : ""))
        }
        if (cible !== "" && root.ordreMinimisees.indexOf(cible) < 0) {
            const suite = root.ordreMinimisees.slice()
            suite.push(cible)
            root.ordreMinimisees = suite
        }
        return cible !== ""
    }

    function rappelerFenetre(adresse) {
        const cible = root.cleAdresse(adresse)
        const bureau = root.bureauCourant()
        if (cible === "" || bureau <= 0) return false
        const sel = root.selecteurAdresse(cible)
        if (Hyprland.usingLua) {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + bureau
                             + ', window = "' + sel + '", follow = false })')
            Hyprland.dispatch('hl.dsp.focus({ window = "' + sel + '" })')
        } else {
            Hyprland.dispatch("movetoworkspacesilent " + bureau + "," + sel)
            Hyprland.dispatch("focuswindow " + sel)
        }
        const i = root.ordreMinimisees.indexOf(cible)
        if (i >= 0) {
            const suite = root.ordreMinimisees.slice()
            suite.splice(i, 1)
            root.ordreMinimisees = suite
        }
        return true
    }

    function rappelerDerniere() {
        const liste = root.fenetresMinimisees()
        if (liste.length === 0) return false
        return root.rappelerFenetre(String(liste[liste.length - 1].address))
    }

    // ──────────────────────────────────────────────────────────────────────────
    // IPC HANDLER ("shell")
    // ──────────────────────────────────────────────────────────────────────────
    property IpcHandler ipc: IpcHandler {
        target: "shell"
        function placeWidget() {
            if (root.placeWidgetHook)
                root.placeWidgetHook()
        }
        function openWidgetMenu(id: string) {
            if (root.widgetMenuHook)
                root.widgetMenuHook(id)
        }
        function toggleConfig() {
            Theme.configPanelVisible = !Theme.configPanelVisible
        }
        function toggleMasqueParallaxe() {
            Theme.masqueParallaxeVisible = !Theme.masqueParallaxeVisible
        }
        function openConfigSection(section: string) {
            Theme.openConfigSection(section)
        }
        function setConfigButtonVisible(visible: bool) {
            Theme.showConfigButton = visible
        }
        function toggleConfigButton() {
            Theme.showConfigButton = !Theme.showConfigButton
        }
        function reloadTheme() {
            Theme.relireStyle()
        }
        function osd(kind: string, value: real) {
            root.showOsd(kind, value)
        }
        function togglePopup(name: string) {
            Theme.togglePopup(name)
        }
        function toggleIslandPanel() {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            Theme.islandPanelOpen = !Theme.islandPanelOpen
            if (!Theme.islandPanelOpen) {
                Theme.islandSidePanel = ""
                Theme.islandNeedsKeyboard = false
            }
        }
        function openIslandPanel(tabIndex: int) {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            const maxTab = Theme.ilotProjetsActif ? 4 : 3
            Theme.islandPanelTab = Math.max(0, Math.min(maxTab, tabIndex))
            Theme.islandPanelOpen = true
        }
        function nav(action: string): string {
            if (Theme.barStyle !== "island") return "not_island"
            const a = String(action || "").toLowerCase()
            if (a === "ouvrir" || a === "open") {
                Theme.activePopup = ""
                Theme.islandNavActive = true
                Theme.islandPanelOpen = true
                return "ok"
            }
            if (a === "fermer" || a === "close") {
                Theme.islandPanelOpen = false
                Theme.islandSidePanel = ""
                Theme.islandNeedsKeyboard = false
                Theme.islandNavActive = false
                return "ok"
            }
            if (!Theme.islandPanelOpen) {
                Theme.activePopup = ""
                Theme.islandPanelOpen = true
            }
            Theme.islandNavActive = true
            const nTabs = Theme.ilotProjetsActif ? 5 : 4
            if (a === "onglet_suiv" || a === "tab_next") {
                Theme.islandPanelTab = (Theme.islandPanelTab + 1) % nTabs
                return "ok"
            }
            if (a === "onglet_prec" || a === "tab_prev") {
                Theme.islandPanelTab = (Theme.islandPanelTab + nTabs - 1) % nTabs
                return "ok"
            }
            if (root.islandNavHook) {
                root.islandNavHook(a)
                return "ok"
            }
            return "no_hook"
        }
        function navState(): bool {
            return Theme.islandNavActive
        }
        function toggleSpotlight() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.wallpaperPickerOpen = false
                Theme.themePickerOpen = false
                Theme.islandNotesOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.islandLauncherOpen = !Theme.islandLauncherOpen
            } else {
                Theme.spotlightVisible = !Theme.spotlightVisible
            }
        }
        function toggleNotes() {
            if (Theme.barStyle !== "island") return
            Theme.activePopup = ""
            Theme.islandPanelOpen = false
            Theme.wallpaperPickerOpen = false
            Theme.themePickerOpen = false
            Theme.islandLauncherOpen = false
            Theme.islandLiveActivityOpen = false
            Theme.islandNotesOpen = !Theme.islandNotesOpen
        }
        function toggleLiveActivity() {
            Theme.toggleLiveActivity()
        }
        function liveActivity(action: string, actId: string, title: string, progress: int): string {
            return root.handleLiveActivity(action, actId, title, progress)
        }
        function liveActivityStart(actId: string, title: string, progress: int): string {
            return root.handleLiveActivity("start", actId, title, progress)
        }
        function liveActivityUpdate(actId: string, progress: int, title: string): string {
            return root.handleLiveActivity("update", actId, title, progress)
        }
        function liveActivityStop(actId: string): string {
            return root.handleLiveActivity("stop", actId, "", -1)
        }
        function liveActivityClear(): string {
            return root.handleLiveActivity("clear", "", "", -1)
        }
        function timerStart(minutes: int): string {
            root.startTimer(minutes, "")
            return "ok"
        }
        function setContext(ctxId: string): string {
            return root.applyContext(ctxId) ? "ok" : "unknown_context"
        }
        function toggleCheatsheet() {
            Theme.cheatsheetVisible = !Theme.cheatsheetVisible
        }
        function toggleOverview() {
            Theme.overviewVisible = !Theme.overviewVisible
        }
        function toggleWidgetEditMode() {
            Theme.widgetsEditMode = !Theme.widgetsEditMode
        }
        function toggleWallpaperPicker() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.islandLauncherOpen = false
                Theme.islandNotesOpen = false
                Theme.themePickerOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.wallpaperPickerOpen = !Theme.wallpaperPickerOpen
            } else {
                Quickshell.execDetached(["quickshell", "-n", "-p", Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"])
            }
        }
        function toggleThemePicker() {
            if (Theme.barStyle === "island") {
                Theme.activePopup = ""
                Theme.islandPanelOpen = false
                Theme.islandLauncherOpen = false
                Theme.islandNotesOpen = false
                Theme.wallpaperPickerOpen = false
                Theme.islandLiveActivityOpen = false
                Theme.themePickerOpen = !Theme.themePickerOpen
            } else {
                Theme.openConfigSection("apparence_couleurs")
            }
        }
        function themeNav(action: string) {
            const a = String(action || "").toLowerCase()
            if (a === "close" || a === "fermer") {
                Theme.themePickerOpen = false
                return
            }
            if (root.themeNavHook) root.themeNavHook(a)
        }
        function wpNav(action: string) {
            const a = String(action || "").toLowerCase()
            if (a === "close" || a === "fermer") {
                Theme.wallpaperPickerOpen = false
                return
            }
            if (root.wallpaperNavHook) root.wallpaperNavHook(a)
        }
        function showCheatsheet() {
            Theme.cheatsheetVisible = true
        }
        function hideCheatsheet() {
            Theme.cheatsheetVisible = false
        }
        function cheatsheetState(): bool {
            return Theme.cheatsheetVisible
        }
        function showSpotlight() {
            Theme.spotlightVisible = true
        }
        function hideSpotlight() {
            Theme.spotlightVisible = false
        }
        function spotlightState(): bool {
            return Theme.spotlightVisible
        }
        function launchHistoryState(): bool {
            return Theme.launchHistory
        }
        function toggleScreenshotPicker() {
            Theme.screenshotPickerVisible = !Theme.screenshotPickerVisible
        }
        function showScreenshotPicker() {
            Theme.screenshotPickerVisible = true
        }
        function hideScreenshotPicker() {
            Theme.screenshotPickerVisible = false
        }
        function screenshotPickerState(): bool {
            return Theme.screenshotPickerVisible
        }
        function captureMode(mode: string) {
            if (root.captureHook)
                root.captureHook(mode)
        }
        function notifTargets(): string {
            return root.notifTargetsHook ? String(root.notifTargetsHook()) : "[]"
        }
        function notifOpenLatest(): bool {
            return root.notifOpenHook ? Boolean(root.notifOpenHook()) : false
        }
        function notifClear(): bool {
            return root.notifClearHook ? Boolean(root.notifClearHook()) : false
        }
        function notifInvoke(actionId: string): bool {
            return root.notifInvokeHook ? Boolean(root.notifInvokeHook(actionId)) : false
        }
        function toggleNotifHistory() {
            root.notifHistoryVisible = !root.notifHistoryVisible
        }
        function showNotifHistory() {
            root.notifHistoryVisible = true
        }
        function hideNotifHistory() {
            root.notifHistoryVisible = false
        }
        function notifHistoryState(): bool {
            return root.notifHistoryVisible
        }
        function minimiser(): bool {
            return root.minimiserFenetre("")
        }
        function rappelerDerniere(): bool {
            return root.rappelerDerniere()
        }
        function rappelerFenetreAdresse(adresse: string) {
            return root.rappelerFenetre(adresse)
        }
        function minimisees(): string {
            const liste = root.fenetresMinimisees()
            const out = []
            for (let i = 0; i < liste.length; i++)
                out.push({ adresse: String(liste[i].address),
                           titre: String(liste[i].title || "") })
            return JSON.stringify(out)
        }
    }
}
