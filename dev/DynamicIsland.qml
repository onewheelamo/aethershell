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

    component LiveActivityChip: Rectangle {
        id: chip
        property bool animatePulse: true
        readonly property var primary: root.liveActivities.length > 0 ? root.liveActivities[0] : null
        height: Math.max(18, Theme.barHeight - 8)
        width: chipRow.implicitWidth + 12
        radius: Math.round(height / 2)
        anchors.verticalCenter: parent.verticalCenter
        color: primary ? Qt.alpha(primary.color, 0.16) : "transparent"
        border.width: 1
        border.color: primary ? Qt.alpha(primary.color, 0.45) : "transparent"

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5

            Rectangle {
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: chip.primary ? chip.primary.color : Theme.accent
                SequentialAnimation on opacity {
                    running: chip.animatePulse && chip.visible && !(chip.primary && chip.primary.paused)
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const p = chip.primary
                    if (!p) return ""
                    const t = String(p.title || "")
                    return t.length > 16 ? (t.substring(0, 15) + "…") : t
                }
                font.family: Theme.fontUi
                font.pixelSize: Math.max(8, Math.round(11 * Theme.barScale))
                font.weight: Font.Bold
                color: chip.primary ? chip.primary.color : Theme.fg
            }

            Rectangle {
                visible: root.liveActivities.length > 1
                width: chipCntTxt.implicitWidth + 8
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: chip.primary ? chip.primary.color : Theme.accent

                Text {
                    id: chipCntTxt
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

    component CaptureDot: Rectangle {
        property string ilotState: "compact"
        visible: Theme.ilotVisibleIn(Theme.ilotShowCapture, ilotState) && root.captureState !== "none"
        width: 6
        height: 6
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: root.captureState === "video" ? "#ef4444" : "#f97316"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    component VpnDot: Rectangle {
        property string ilotState: "compact"
        visible: Theme.ilotVisibleIn(Theme.ilotShowVpn, ilotState)
        width: 6
        height: 6
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: root.vpnState === "connected" ? "#00a3d5" : (root.vpnState === "error" ? "#eab308" : "#ffffff")
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    component PlankaAlertIcon: Item {
        property string ilotState: "compact"
        property int boxSize: 20
        visible: Theme.ilotProjetsActif && Theme.ilotVisibleIn(Theme.ilotShowPlanka, ilotState) && root.plankaEcheanceProche
        width: boxSize
        height: boxSize
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
        command: [Quickshell.shellPath("core/as-core"), "planka", "statut"]
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
        command: [Quickshell.shellPath("core/as-core"), "indicateurs"]
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
        interval: 5000
        repeat: true
        running: Theme.barStyle === "island"
        triggeredOnStart: true
        onTriggered: if (!indicateursProc.running) indicateursProc.running = true
    }

    // Service MPRIS direct pour la réactivité instantanée
    readonly property var players: Mpris.players.values

    // Respecte le filtre navigateur activé dans les réglages de l'applet musique
    readonly property bool ignorerNavigateurs: {
        let a = (ShellState.barAppletsActifs && ShellState.barAppletsActifs["musique"]) ? ShellState.barAppletsActifs["musique"].options : null
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

    readonly property bool isCalendarOpen: Theme.activePopup === "calendar"
    readonly property bool isPopupOpen: {
        const p = String(Theme.activePopup || "")
        if (p === "") return false
        if (p.startsWith("applet:")) {
            const aid = p.slice(7)
            if (Theme.ilotAppletCornerFor(aid) !== "") return false
        }
        return true
    }
    readonly property bool panelOpen: Theme.islandPanelOpen
    readonly property bool notifToastActive: Theme.barStyle === "island"
        && ShellState.notifToastVisible
        && ShellState.notifToast !== null
        && !panelOpen
    readonly property bool meteoExpanded: Theme.barStyle === "island"
        && Theme.activePopup === "applet:meteo"
        && Theme.ilotAppletCornerFor("meteo") === ""
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

    property bool pretGrabTheme: false
    onThemeExpandedChanged: {
        if (themeExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabTheme = false
            delaiGrabTheme.restart()
            themeContainer.activate()
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

    property bool pretGrabWallpaper: false
    onWallpaperExpandedChanged: {
        if (wallpaperExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabWallpaper = false
            delaiGrabWallpaper.restart()
            wallpaperContainer.activate()
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
    property var launcherServiceResults: []
    property string launcherQuery: ""
    property int launcherSelectedIdx: 0
    property bool launcherSearching: false

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

        if (rl === "matrix" || rl.indexOf("matrix ") === 0) {
            const tokens = rl.slice(6).trim().split(/\s+/).filter(function (t) { return t !== "" })
            if (tokens.indexOf("stop") !== -1) {
                return [{ name: "as matrix stop", desc: "Arrêter le terminal Matrix ou annuler le délai", icon: "stop", kind: "as", asAction: "matrix", asArg: { stop: true } }]
            }
            let delayMin = 0
            let isSs = false
            for (let i = 0; i < tokens.length; i++) {
                const tok = tokens[i]
                if (tok === "ss" || tok === "veille" || tok === "screensaver") {
                    isSs = true
                } else {
                    const m = parseFloat(tok)
                    if (!isNaN(m) && m > 0) delayMin = m
                }
            }
            const label = "as matrix" + (delayMin > 0 ? (" " + delayMin) : "") + (isSs ? " ss" : "")
            const descMode = isSs
                ? "Écran de veille plein écran devant tout (souris/clavier pour quitter)"
                : "Fond animé plein écran derrière les surfaces Quickshell"
            const descDelai = delayMin > 0 ? (" dans " + delayMin + " min") : ""
            return [{ name: label, desc: descMode + descDelai, icon: "monitor", kind: "as", asAction: "matrix", asArg: { ss: isSs, delay: delayMin, stop: false } }]
        }

        if (rl === "contexte" || rl.indexOf("contexte ") === 0) {
            const qCtx = rl.slice(8).trim()
            const ctxs = ShellState.workContexts || []
            for (let i = 0; i < ctxs.length; i++) {
                const c = ctxs[i]
                if (qCtx === "" || c.id.indexOf(qCtx) !== -1 || c.label.toLowerCase().indexOf(qCtx) !== -1) {
                    out.push({
                        name: "as contexte " + c.id,
                        desc: (c.id === ShellState.activeContext ? "Actif · " : "") + c.label + " — " + c.desc,
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
            { name: "as dnd", desc: ShellState.doNotDisturb ? "Désactiver Ne Pas Déranger" : "Activer Ne Pas Déranger", icon: ShellState.doNotDisturb ? "bell" : "bell-off", kind: "as", asAction: "dnd" },
            { name: "as caffeine", desc: SystemServices.caffeineActif ? "Désactiver Caffeine" : "Activer Caffeine (empêche la veille)", icon: "coffee", kind: "as", asAction: "caffeine" },
            { name: "as nuit", desc: "Basculer le mode nuit (ou « as nuit 3500 »)", icon: "weather-night", kind: "as", asAction: "nuit" },
            { name: "as theme", desc: "Choisir un jeu de couleurs (ou « as theme <nom> »)", icon: "palette", kind: "as", asAction: "theme_picker" },
            { name: "as fond", desc: "Ouvrir le sélecteur de fond d'écran", icon: "image", kind: "as", asAction: "fond" },
            { name: "as barre", desc: Theme.barStyle === "island" ? "Passer en barre classique" : "Passer en Îlot dynamique", icon: "widgets", kind: "as", asAction: "barre" },
            { name: "as widgets", desc: Theme.widgetsBureauVisibles ? "Masquer les widgets du bureau" : "Afficher les widgets du bureau", icon: "widgets", kind: "as", asAction: "widgets" },
            { name: "as energie", desc: "Profil d'énergie (perf / equilibre / eco)", icon: "battery", kind: "as", asAction: "prefill_as", asArg: "as energie " },
            { name: "as timer", desc: "Lancer un minuteur (ex. « as timer 25 »)", icon: "clock", kind: "as", asAction: "prefill_as", asArg: "as timer 25" },
            { name: "as matrix", desc: "Fond animé Matrix (ou « as matrix 10 ss » pour veille)", icon: "monitor", kind: "as", asAction: "matrix", asArg: { ss: false, delay: 0, stop: false } },
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
            launcherContainer.setText(String(entry.asArg))
            return
        }
        Theme.islandLauncherOpen = false
        if (act === "dnd") {
            ShellState.doNotDisturb = !ShellState.doNotDisturb
            Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "style", "do_not_disturb", ShellState.doNotDisturb ? "true" : "false"])
        } else if (act === "caffeine") {
            SystemServices.caffeineActif = !SystemServices.caffeineActif
        } else if (act === "nuit") {
            Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "nuit", "basculer"])
        } else if (act === "nuit_temp") {
            Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "nuit", "temperature", String(entry.asArg)])
        } else if (act === "barre") {
            const next = Theme.barStyle === "island" ? "classic" : "island"
            Quickshell.execDetached([Quickshell.shellPath("core/as-core"), "config", "style", "bar_style", next])
        } else if (act === "widgets") {
            Theme.widgetsBureauVisibles = !Theme.widgetsBureauVisibles
        } else if (act === "theme_picker") {
            Theme.themePickerOpen = true
        } else if (act === "theme_apply" && entry.asArg) {
            themeContainer.applyScheme(String(entry.asArg))
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
            ShellState.startTimer(entry.asArg, "")
        } else if (act === "matrix") {
            const opts = entry.asArg || ({})
            const args = [Quickshell.shellPath("core/as-core"), "matrix"]
            if (opts.stop) args.push("--stop")
            else {
                if (opts.ss) args.push("--ss")
                if (opts.delay && Number(opts.delay) > 0) {
                    args.push("--delay", String(opts.delay))
                }
            }
            Quickshell.execDetached(args)
        } else if (act === "contexte" && entry.asArg) {
            ShellState.applyContext(String(entry.asArg))
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
        command: [Quickshell.shellPath("core/as-core"), "live-activity"]
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
        interval: (root.liveRecording.active || root.liveDownloads.length > 0) ? 1000 : 5000
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
        if (ShellState.timerRunning) {
            const pct = ShellState.timerTotalSec > 0
                ? Math.max(0, Math.min(100, Math.round(100 * (ShellState.timerTotalSec - ShellState.timerRemainingSec) / ShellState.timerTotalSec)))
                : 0
            list.push({
                id: "timer",
                kind: "timer",
                title: (ShellState.timerPaused ? "⏸ " : "") + root.formatLiveDuration(ShellState.timerRemainingSec),
                subtitle: ShellState.timerLabel,
                etaText: "Reste ~ " + root.formatLiveDuration(ShellState.timerRemainingSec),
                progress: pct,
                paused: ShellState.timerPaused,
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
        const ipcs = Array.isArray(ShellState.ipcActivities) ? ShellState.ipcActivities : []
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
    readonly property real compactExtraHeight: (!ShellState.osdVisible && root.compactBarsList.length > 1)
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
            if (root.launcherCategory !== "") {
                return LauncherEngine.appsInCategory(root.launcherCategory, true)
            }
            return LauncherEngine.categoriesEntries()
        }
        return LauncherEngine.searchAppsAndAliases(q, 8)
    }
    property string launcherCategory: ""

    Timer {
        id: launcherSvcTimer
        interval: 100
        repeat: false
        onTriggered: {
            const q = root.launcherQuery.trim()
            if (!/^[^a-zA-Z0-9\s>]/.test(q)) return
            if (launcherServiceProc.running) launcherServiceProc.running = false
            launcherServiceProc.command = [
                Quickshell.shellPath("core/as-core"), "launcher",
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
        if (entry.kind === "category") {
            root.launcherCategory = String(entry.category || "")
            root.launcherSelectedIdx = 0
            return
        }
        if (entry.kind === "category_back") {
            root.launcherCategory = ""
            root.launcherSelectedIdx = 0
            return
        }
        if (entry.kind === "as") {
            root.runAsCommand(entry)
            return
        }
        if (entry.action === "prefill" && entry.arg !== undefined) {
            launcherContainer.setText(String(entry.arg))
            return
        }
        if (entry.action === "copy" && entry.arg) {
            Quickshell.execDetached(["wl-copy", String(entry.arg)])
            Theme.islandLauncherOpen = false
            return
        }
        if (entry.action === "open-config") {
            Theme.islandLauncherOpen = false
            Theme.configPanelVisible = true
            return
        }
        if ((entry.action === "open" || entry.action === "open-url") && entry.arg) {
            SystemServices.launchInScope('exec xdg-open "' + String(entry.arg).replace(/"/g, '\\"') + '"')
            Theme.islandLauncherOpen = false
            return
        }
        if (entry.action === "kill" && entry.arg) {
            Quickshell.execDetached(["kill", "-TERM", String(entry.arg)])
            Theme.islandLauncherOpen = false
            return
        }
        if (!entry.exec) return
        LauncherEngine.launch(entry)
        Theme.islandLauncherOpen = false
    }

    property bool pretGrabLauncher: false
    onLauncherExpandedChanged: {
        if (launcherExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabLauncher = false
            delaiGrabLauncher.restart()
            LauncherEngine.reload()
            root.launcherQuery = ""
            root.launcherCategory = ""
            root.launcherSelectedIdx = 0
            launcherContainer.clearAndFocus()
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
    property bool pretGrabNotes: false
    onNotesExpandedChanged: {
        if (notesExpanded) {
            retractTimer.stop()
            expanded = true
            pretGrabNotes = false
            delaiGrabNotes.restart()
            notesContainer.activate()
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
            SystemServices.rafraichirMeteo(false)
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
        target: ShellState
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
    readonly property real compactWidth: ShellState.osdVisible ? osdWidth : compactRestWidth
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
    onWidthChanged: ShellState.ilotWidth = width

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
            visible: ShellState.osdVisible

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: ShellState.osdGlyph
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
                    width: parent.width * (ShellState.osdValue / 100)
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 100 } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.osdPercent
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
            visible: !ShellState.osdVisible

            // Point capture vidéo (rouge) / audio seule (orange) avant les ws
            CaptureDot { ilotState: "compact" }

            WorkspacesApplet {
                id: compactWorkspaces
                visible: Theme.ilotAppletCornerFor("workspaces") === ""
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("workspaces"), "compact")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: Theme.ilotAppletCornerFor("workspaces") === ""
                    && Theme.ilotAppletCornerFor("horloge") === ""
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("workspaces"), "compact")
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("horloge"), "compact")
                width: 1
                height: 12
                color: Theme.fg
                opacity: 0.15
                anchors.verticalCenter: parent.verticalCenter
            }

            // Horloge principale sans glyphe (clic -> panneau étendu)
            Text {
                visible: Theme.ilotAppletCornerFor("horloge") === ""
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("horloge"), "compact")
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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            // Applets configurés en mode « Repos » ou « Les deux »
            AppletRow {
                id: compactApplets
                directModel: ShellState.appletsPourIlot("compact", "all")
                visible: compactApplets.applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Icône Projets (columns-3) si échéance Planka < 24h
            PlankaAlertIcon { ilotState: "compact"; boxSize: 20 }

            // Badge contexte actif (si différent de « normal »)
            Rectangle {
                visible: ShellState.activeContext !== "" && ShellState.activeContext !== "normal"
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
                        const ctxs = ShellState.workContexts || []
                        for (let i = 0; i < ctxs.length; i++) {
                            if (ctxs[i].id === ShellState.activeContext) return ctxs[i].label
                        }
                        return ShellState.activeContext
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
            LiveActivityChip {
                id: liveActivityPill
                visible: Theme.ilotVisibleIn(Theme.ilotShowLiveActivity, "compact") && root.liveActivities.length > 0
                animatePulse: true
            }

            // Point VPN à droite (bleu = connecté, blanc = déconnecté, jaune = erreur)
            VpnDot { ilotState: "compact" }
        }

        // Seconde barre (et +) vers le bas pour les téléchargements / activités secondaires
        // Barres de progression fines (2px, espacées de 1px) collées en bas de la pilule
        // Barres de progression fines (2px, espacées de 1px) collées en bas de la pilule
        Column {
            id: compactBarsCol
            visible: root.compactBarsList.length > 0 && !ShellState.osdVisible
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
            CaptureDot { ilotState: "expanded" }

            WorkspacesApplet {
                id: expandedWorkspaces
                visible: Theme.ilotAppletCornerFor("workspaces") === ""
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("workspaces"), "expanded")
                dotsMode: true
                anchors.verticalCenter: parent.verticalCenter
            }

            AppletRow {
                id: leftApplets
                directModel: ShellState.appletsPourIlot("expanded", "left")
                visible: applets.length > 0
                anchors.verticalCenter: parent.verticalCenter
            }

            // Centre : Horloge + Date (clic -> panneau étendu)
            Item {
                visible: Theme.ilotAppletCornerFor("horloge") === ""
                    && Theme.ilotVisibleIn(Theme.ilotAppletModeFor("horloge"), "expanded")
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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirPanneau(0)
                }
            }

            // Live Activity visible aussi en mode étendu (au survol)
            LiveActivityChip {
                id: expandedLiveActivityPill
                visible: Theme.ilotVisibleIn(Theme.ilotShowLiveActivity, "expanded") && root.liveActivities.length > 0
                animatePulse: false
            }

            // Côté Droit : Applets droite
            AppletRow {
                id: rightApplets
                directModel: ShellState.appletsPourIlot("expanded", "right")
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
            PlankaAlertIcon { ilotState: "expanded"; boxSize: 22 }

            // Point VPN à droite en mode étendu
            VpnDot { ilotState: "expanded" }
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
                if (ShellState.notifOps && ShellState.notifOps.dismissToast) ShellState.notifOps.dismissToast()
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
                    text: ShellState.notifToast ? String(ShellState.notifToast.appName || "Système") : ""
                    color: Theme.accent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: ShellState.notifToast ? String(ShellState.notifToast.time || "") : ""
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
                            if (ShellState.notifOps && ShellState.notifOps.quietToast) ShellState.notifOps.quietToast()
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
                            if (ShellState.notifOps && ShellState.notifOps.dismissToast) ShellState.notifOps.dismissToast()
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
                    text: ShellState.notifToast ? String(ShellState.notifToast.summary || "") : ""
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
                    enabled: Boolean(ShellState.notifToast && ShellState.notifOps && ShellState.notifOps.hasTarget && ShellState.notifOps.hasTarget(ShellState.notifToast))
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (ShellState.notifToast && ShellState.notifOps && ShellState.notifOps.open) {
                            ShellState.notifOps.open(ShellState.notifToast, false)
                        }
                    }
                }
            }

            // Corps du message
            Text {
                visible: Boolean(ShellState.notifToast && ShellState.notifToast.body && ShellState.notifToast.body !== "")
                width: parent.width
                text: ShellState.notifToast ? String(ShellState.notifToast.body || "") : ""
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
                visible: Boolean(ShellState.notifToast && ShellState.notifOps && ShellState.notifOps.actions && ShellState.notifOps.actions(ShellState.notifToast).length > 0)
                spacing: Theme.space1

                Repeater {
                    model: (ShellState.notifToast && ShellState.notifOps && ShellState.notifOps.actions)
                        ? ShellState.notifOps.actions(ShellState.notifToast) : []

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
                                if (ShellState.notifToast && ShellState.notifOps && ShellState.notifOps.invoke) {
                                    ShellState.notifOps.invoke(ShellState.notifToast, modelData.identifier)
                                    if (ShellState.notifOps.dismissToast) ShellState.notifOps.dismissToast()
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

        readonly property var meteo: SystemServices.meteoData
        readonly property bool ok: SystemServices.meteoLoaded && meteo && meteo.ok === true
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
                            : (SystemServices.meteoStatut !== "" ? SystemServices.meteoStatut : "Chargement…")
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
                        onClicked: SystemServices.rafraichirMeteo(true)
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
    IslandWallpaperPicker {
        id: wallpaperContainer
        open: root.wallpaperExpanded
        fadeDuration: root.fadeDuration
    }

    // ──────────────────────────────────────────────────────────────────────
    // LANCEUR D'APPLICATIONS INLINE FAÇON IMPASTO (SUPER + R)
    // ──────────────────────────────────────────────────────────────────────
    IslandLauncherDrawer {
        id: launcherContainer
        open: root.launcherExpanded
        fadeDuration: root.fadeDuration
        results: root.launcherResults
        searching: root.launcherSearching
        selectedIdx: root.launcherSelectedIdx
        inCategory: root.launcherCategory !== ""
        onQueryEdited: q => { root.launcherQuery = q }
        onSelectedIdxChangedRequested: idx => { root.launcherSelectedIdx = idx }
        onEntryActivated: entry => root.runLauncherEntry(entry)
        onBackRequested: {
            root.launcherCategory = ""
            root.launcherSelectedIdx = 0
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // NOTES RAPIDES / POST-ITS INLINE (SUPER + N)
    // ──────────────────────────────────────────────────────────────────────
    IslandNotesDrawer {
        id: notesContainer
        open: root.notesExpanded
        fadeDuration: root.fadeDuration
    }

    // ──────────────────────────────────────────────────────────────────────
    // SÉLECTEUR DE JEU DE COULEURS INLINE (SUPER + C)
    // ──────────────────────────────────────────────────────────────────────
    IslandThemePicker {
        id: themeContainer
        open: root.themeExpanded
        fadeDuration: root.fadeDuration
    }

    // ──────────────────────────────────────────────────────────────────────
    // EXTENSION INLINE LIVE ACTIVITY (TÂCHES LONGUES, MINUTEUR, REC, DL)
    // ──────────────────────────────────────────────────────────────────────
    IslandLiveActivityDrawer {
        id: liveActivityContainer
        open: root.liveActivityExpanded
        fadeDuration: root.fadeDuration
        liveActivities: root.liveActivities
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