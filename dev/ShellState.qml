pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

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
        Theme.doNotDisturb = found.dnd
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
            if (Theme.placeWidgetHook)
                Theme.placeWidgetHook()
        }
        function openWidgetMenu(id: string) {
            if (Theme.widgetMenuHook)
                Theme.widgetMenuHook(id)
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
            Theme.showOsd(kind, value)
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
            if (Theme.islandNavHook) {
                Theme.islandNavHook(a)
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
            if (Theme.themeNavHook) Theme.themeNavHook(a)
        }
        function wpNav(action: string) {
            const a = String(action || "").toLowerCase()
            if (a === "close" || a === "fermer") {
                Theme.wallpaperPickerOpen = false
                return
            }
            if (Theme.wallpaperNavHook) Theme.wallpaperNavHook(a)
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
            if (Theme.captureHook)
                Theme.captureHook(mode)
        }
        function notifTargets(): string {
            return Theme.notifTargetsHook ? String(Theme.notifTargetsHook()) : "[]"
        }
        function notifOpenLatest(): bool {
            return Theme.notifOpenHook ? Boolean(Theme.notifOpenHook()) : false
        }
        function notifClear(): bool {
            return Theme.notifClearHook ? Boolean(Theme.notifClearHook()) : false
        }
        function notifInvoke(actionId: string): bool {
            return Theme.notifInvokeHook ? Boolean(Theme.notifInvokeHook(actionId)) : false
        }
        function toggleNotifHistory() {
            Theme.notifHistoryVisible = !Theme.notifHistoryVisible
        }
        function showNotifHistory() {
            Theme.notifHistoryVisible = true
        }
        function hideNotifHistory() {
            Theme.notifHistoryVisible = false
        }
        function notifHistoryState(): bool {
            return Theme.notifHistoryVisible
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
