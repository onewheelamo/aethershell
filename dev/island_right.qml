import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Notifications

// ════════════════════════════════════════════════════════════════════════════
// RIGHT ISLAND: HARDWARE CONTROLS, SYSTRAY & POWER MENU (island_right.qml)
// ════════════════════════════════════════════════════════════════════════════
// Architecture Overview:
//   • Section 1: Popup Geometry & System State Properties
//   • Section 2: Helper Functions & Formatters (signal, battery, volume icons)
//   • Section 3: IPC & Hardware Background Processes (system info, actions, WiFi, notifications)
//   • Section 4: Arch-Update Check Service (pacman + AUR update counter & timer)
//   • Section 5: Main Right Island Bar UI:
//       - 5.1 Systray & Notifications (Arch-Update badge, Tray icons, Notif bell)
//       - 5.2 WiFi / Network Button (status, SSID, signal strength)
//       - 5.3 System Controls Box (Battery status, Volume, Brightness)
//       - 5.4 Tablet Mode Virtual Keyboard Button (on-screen keyboard toggle)
//       - 5.5 Power Menu Button (scaled dynamically to bar height)
//   • Section 6: Hyprland Focus Grab (dismiss popups on outside click)
//   • Section 7: Popups:
//       - 7.1 Interactive WiFi Network Selection Panel
//       - 7.2 System Controls Panel (ASUS Battery 80% limit, Volume slider, Brightness slider)
//       - 7.3 Power & Session Management Menu (Shutdown, Reboot, Lock, Suspend, Logout)
//       - 7.4 Notification Center Popup (notification list & history)
//       - 7.5 Ephemeral Toast Popup (incoming desktop notifications)
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandRight

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: POPUP GEOMETRY & SYSTEM STATE PROPERTIES
    // ────────────────────────────────────────────────────────────────────────
    // Keep popups fully inside the bar window (= screen width) with an 8px margin.
    // Vertical offset so that every popup opens 6px under the BAR (island bottom).
    function popupY(item) {
        return islandRight.height + 6 - islandRight.mapFromItem(item, 0, 0).y
    }

    function clampPopupX(item, relX, popupW) {
        const win = islandRight.QsWindow.window
        if (!win) return relX
        const ix = win.contentItem.mapFromItem(item, 0, 0).x
        const absX = Math.max(8, Math.min(win.width - popupW - 8, ix + relX))
        return absX - ix
    }
    implicitWidth: mainRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Host & hardware properties
    property string hostName: "Station"
    property bool hasBattery: false
    property bool hasBacklight: false

    property int batPercent: 0
    property string batStatus: "Unknown"
    property bool batLimit80: false

    property int volPercent: 0
    property bool volMuted: false

    property int briPercent: 100


    property bool tabletMode: false


    // Notifications State
    property var notificationsList: []
    property var latestToast: null

    // Arch-Update State
    property bool hasArchUpdate: false
    property int pendingUpdatesCount: 0

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HELPER FUNCTIONS & FORMATTERS
    // ────────────────────────────────────────────────────────────────────────
    // Renvoient un NOM d'icône (Icon.qml), plus un glyphe brut : c'est ce qui
    // garantit une seule famille, une seule taille et un seul centrage.

    function batteryIconFor(pct, status) {
        if (status === "Charging" || status === "Full") return "battery-charging"
        if (pct >= 90) return "battery-full"
        if (pct >= 70) return "battery-70"
        if (pct >= 50) return "battery-50"
        if (pct >= 25) return "battery-25"
        if (pct >= 10) return "battery-10"
        return "battery-outline"
    }

    function applySystemInfo(data) {
        if (!data) return
        if (typeof data.hostname === "string" && data.hostname.length > 0) {
            hostName = data.hostname.charAt(0).toUpperCase() + data.hostname.slice(1)
        }
        if (typeof data.has_battery === "boolean") {
            hasBattery = data.has_battery
        }
        if (typeof data.has_backlight === "boolean") {
            hasBacklight = data.has_backlight
        }
        if (data.battery) {
            batPercent = Number(data.battery.level || 0)
            batStatus = String(data.battery.status || "Unknown")
            batLimit80 = Boolean(data.battery.limit_80)
        }
        if (data.volume) {
            volPercent = Number(data.volume.level || 0)
            volMuted = Boolean(data.volume.muted)
        }
        if (typeof data.brightness === "number") {
            briPercent = data.brightness
        }
        if (typeof data.tablet_mode === "boolean") {
            tabletMode = data.tablet_mode
        }
    }

    function refreshSystemInfo() {
        if (!sysInfoProc.running) sysInfoProc.running = true
    }


    // Actions (volume, brightness...) are serialized: while one runs, newer ones are queued.
    // A queued action replaces an older queued one of the same kind so that dragging a slider
    // only applies the latest value instead of dropping it.
    property var sysActionQueue: []

    function startSysAction(args) {
        sysActionProc.command = ["python3", Quickshell.shellPath("core/system_service.py")].concat(args)
        sysActionProc.running = true
    }

    function runSysAction(args) {
        if (!sysActionProc.running) {
            startSysAction(args)
            return
        }
        // "mute" is a toggle action: do not deduplicate / replace previous mute toggles.
        // For continuous values (volume, brightness), replace older pending requests of the same type.
        const isToggle = (args[0] === "mute")
        const q = isToggle ? sysActionQueue.slice() : sysActionQueue.filter(a => a[0] !== args[0])
        q.push(args)
        sysActionQueue = q
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: IPC & HARDWARE BACKGROUND PROCESSES
    // ────────────────────────────────────────────────────────────────────────
    NotificationServer {
        id: notifServer
        keepOnReload: true
        // Capacités annoncées aux clients. Mesuré le 05/11 : sans
        // `actionsSupported`, notify-send répond « Actions are not supported by
        // this notifications server » et le client n'envoie **aucune** action —
        // la règle « action native » du clic sur le titre était donc morte-née,
        // alors que le serveur, lui, sait les recevoir (vérifié en D-Bus pur).
        // Les boutons d'action ne sont pas encore dessinés (lot L4) : seule
        // l'action `default` est exploitée, par le clic sur le titre.
        actionsSupported: true
        // Les notifications restent dans le centre après une action : on
        // l'annonce plutôt que de laisser le client le deviner.
        persistenceSupported: true
        onNotification: notification => {
            notification.tracked = true
            // La notification peut mourir sans nous : son application la ferme,
            // elle expire, ou une action non « resident » vient d'être invoquée.
            // Dans tous ces cas le serveur émet `closed` et la carte doit quitter
            // le centre — sinon elle reste avec des boutons qui ne répondent plus.
            // L'historique, lui, garde son entrée : il vit sur disque.
            try {
                notification.closed.connect(function () {
                    // L'objet, pas l'id : une application peut *remplacer* une
                    // notification (`notify-send -r 1`), et le serveur réutilise
                    // alors l'id. Filtrer par id retirait la nouvelle carte au lieu
                    // de l'ancienne — c'est ce qui faisait disparaître les avis
                    // d'arch-update du centre alors que le toast et l'historique
                    // les gardaient.
                    islandRight.dropClosedNotif(notification)
                })
            } catch (e) {}
            const entry = {
                id: notification.id,
                appName: notification.appName || "Système",
                summary: notification.summary || "Notification",
                body: notification.body || "",
                time: Qt.formatDateTime(new Date(), "hh:mm"),
                // Photographie des actions : la carte les dessine même si la
                // notification est fermée ensuite. L'invocation, elle, repasse
                // par `raw` (l'objet Qt sait parler au client).
                actions: islandRight.notifActionList(notification),
                raw: notification
            }
            // Une application peut *remplacer* sa notification (`notify-send -r`).
            // Le serveur met alors l'objet à jour sur place et n'émet **pas**
            // `notification` : sans ces connexions, la carte gardait le texte de
            // la notification précédente — un avis d'arch-update restait invisible
            // dans le centre parce qu'il portait le nom et le résumé d'une autre
            // application. Les propriétés de Notification ont toutes un NOTIFY,
            // on écoute celles qui s'affichent.
            const rafraichir = function () { islandRight.rafraichirEntree(notification) }
            const signaux = ["appNameChanged", "summaryChanged", "bodyChanged",
                             "actionsChanged", "hintsChanged", "desktopEntryChanged",
                             "urgencyChanged", "imageChanged"]
            for (let s = 0; s < signaux.length; s++) {
                try { notification[signaux[s]].connect(rafraichir) } catch (e) {}
            }

            const all = [entry].concat(islandRight.notificationsList)
            // Les évincées doivent être relâchées du serveur : `keepOnReload` garde
            // tout ce qui est encore `tracked` et les ferait réapparaître au
            // prochain rechargement du shell.
            for (let i = 30; i < all.length; i++) {
                try { all[i].raw.tracked = false } catch (e) {}
            }
            islandRight.notificationsList = all.slice(0, 30)
            // Cible du clic sur le titre : décidée tout de suite (l'objet peut
            // mourir ensuite), calculée hors du shell par notif_target.py.
            islandRight.requestNotifTarget(notification)
            // Application écartée des toasts : la notification va directement au
            // centre, sans apparition spontanée.
            if (Theme.quietNotifApps.indexOf(entry.appName) < 0) {
                islandRight.latestToast = entry
                toastTimer.restart()
            }
        }
    }

    Timer {
        id: toastTimer
        interval: 4500
        repeat: false
        onTriggered: islandRight.latestToast = null
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3bis: CIBLE DU CLIC SUR UNE NOTIFICATION (socle)
    // ────────────────────────────────────────────────────────────────────────
    // Ce que le clic sur le TITRE ouvrira, décidé **à la réception** et rangé dans
    // l'entrée (`target`) : l'objet QsNotification peut être détruit ensuite, et
    // l'historique doit rester cliquable. Ce bloc ne lance rien — il décide et il
    // journalise, pour qu'on puisse relire les décisions sans toucher au bureau :
    //
    //     ~/.cache/quickshell/notifications.log
    //
    // La cascade (hint → table par application → action native → chemin/URL →
    // application émettrice) vit dans core/notif_target.py, et les programmes
    // viennent du tiroir « Programmes par défaut » du panneau (core/app_vars.json),
    // jamais d'un binaire écrit en dur.
    property var targetQueue: []

    function notifActionList(notification) {
        const out = []
        const raw = notification.actions || []
        for (let i = 0; i < raw.length; i++)
            out.push({ identifier: String(raw[i].identifier || ""),
                       text: String(raw[i].text || "") })
        return out
    }

    function notifTargetPayload(notification) {
        const hints = (notification.hints && typeof notification.hints === "object")
            ? notification.hints : ({})
        const plainHints = ({})
        for (const key in hints)
            plainHints[String(key)] = String(hints[key])

        const actions = islandRight.notifActionList(notification)

        return JSON.stringify({
            id: String(notification.id),
            appName: notification.appName || "",
            desktopEntry: notification.desktopEntry || "",
            summary: notification.summary || "",
            body: notification.body || "",
            hints: plainHints,
            actions: actions
        })
    }

    function requestNotifTarget(notification) {
        islandRight.targetQueue.push(islandRight.notifTargetPayload(notification))
        islandRight.pumpNotifTargets()
    }

    // Un seul résolveur pour toute la session : il lit une requête JSON par
    // ligne et répond de même (le shell est seul à lui écrire).
    function pumpNotifTargets() {
        if (!notifResolver.running) return
        while (islandRight.targetQueue.length > 0)
            notifResolver.write(islandRight.targetQueue.shift() + "\n")
    }

    function applyNotifTarget(line) {
        let res
        try { res = JSON.parse(String(line)) } catch (e) { return }
        const id = String(res.id || "")
        delete res.id
        const list = islandRight.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) !== id) continue
            // Nouvel objet : la liste est un tableau JS, une mutation en place ne
            // réveillerait aucune liaison (donc pas d'affordance).
            const merged = Object.assign({}, list[i], { target: res })
            const copy = list.slice()
            copy[i] = merged
            islandRight.notificationsList = copy
            // Le toast a été affiché **avant** la réponse : il tient sa propre
            // référence à l'entrée. Sans cette ligne, son titre restait inerte.
            if (islandRight.latestToast && String(islandRight.latestToast.id) === id)
                islandRight.latestToast = merged
            return
        }
    }

    Process {
        id: notifResolver
        running: true
        stdinEnabled: true
        command: ["python3", Quickshell.shellPath("core/notif_target.py"), "--serve"]
        onStarted: islandRight.pumpNotifTargets()
        onExited: {
            console.warn("notif_target.py s'est arrêté, nouvelle tentative dans 5 s")
            notifResolverRestart.restart()
        }
        stdout: SplitParser {
            onRead: line => islandRight.applyNotifTarget(line)
        }
    }

    Timer {
        id: notifResolverRestart
        interval: 5000
        onTriggered: { if (!notifResolver.running) notifResolver.running = true }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3ter: OUVRIR LA CIBLE D'UNE NOTIFICATION (clic sur le titre)
    // ────────────────────────────────────────────────────────────────────────
    // Le centre et le toast suivent la même règle pour le titre, et deux règles
    // différentes pour le reste : dans le centre la carte ne fait rien (on lit une
    // notification), dans le toast le corps ouvre le centre. Détail : fiche
    // dev/PROPOSITION_notif_click.md.
    function notifHasTarget(entry) {
        if (!entry || !entry.target) return false
        if (entry.target.kind === "action") return true
        return Boolean(entry.target.cmd && entry.target.cmd.length > 0)
    }

    // Retrait d'une notification déjà fermée (application, expiration, action).
    // On ne touche pas à `tracked` : le serveur a déjà statué, et réécrire la
    // propriété d'un objet mort n'apporterait rien. `forgetNotif` reste réservé
    // au cas où c'est nous qui décidons de la fermeture.
    // `closed` nous donne l'objet Qt concerné : c'est lui qui identifie l'entrée,
    // pas son id. Deux notifications peuvent partager un id (remplacement), et
    // dans ce cas retirer « la première qui porte cet id » retirait la nouvelle.
    function dropClosedNotif(notif) {
        if (!notif) return
        const list = islandRight.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (list[i].raw !== notif) continue
            const copy = list.slice()
            copy.splice(i, 1)
            islandRight.notificationsList = copy
            if (islandRight.latestToast && islandRight.latestToast.raw === notif)
                islandRight.latestToast = null
            return
        }
    }

    // Le contenu d'une notification remplacée : on recopie depuis l'objet, qui
    // est la seule source à jour. La cible du clic est recalculée (le nouveau
    // résumé peut désigner autre chose) et le toast suit s'il montre la même.
    function rafraichirEntree(notif) {
        if (!notif) return
        const list = islandRight.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (list[i].raw !== notif) continue
            const ancienne = list[i]
            if (String(notif.summary || "") === String(ancienne.summary || "")
                && String(notif.body || "") === String(ancienne.body || "")
                && String(notif.appName || "") === String(ancienne.appName || ""))
                return
            const maj = Object.assign({}, ancienne, {
                appName: notif.appName || "Système",
                summary: notif.summary || "Notification",
                body: notif.body || "",
                actions: islandRight.notifActionList(notif),
                target: undefined
            })
            const copy = list.slice()
            copy[i] = maj
            islandRight.notificationsList = copy
            if (islandRight.latestToast && islandRight.latestToast.raw === notif)
                islandRight.latestToast = maj
            islandRight.requestNotifTarget(notif)
            return
        }
    }

    // Retirer de la liste **et** du serveur : sans `tracked = false`, keepOnReload
    // ressuscite la notification au prochain rechargement du shell.
    function forgetNotif(entry) {
        if (!entry) return
        if (entry.raw) {
            try { entry.raw.tracked = false } catch (e) {}
        }
        const list = islandRight.notificationsList
        for (let i = 0; i < list.length; i++) {
            // Par objet quand on l'a encore (id partagé après un remplacement),
            // par id sinon (entrée reconstruite depuis le disque).
            const meme = entry.raw ? (list[i].raw === entry.raw) : (String(list[i].id) === String(entry.id))
            if (!meme) continue
            const copy = list.slice()
            copy.splice(i, 1)
            islandRight.notificationsList = copy
            return
        }
        console.warn("notification " + entry.id + " absente de la liste au retrait")
    }

    // Actions affichables : tout sauf « default », qui est déjà le clic sur le
    // titre (deux boutons pour la même chose sèmeraient le doute).
    function notifActions(entry) {
        if (!entry || !entry.actions) return []
        const out = []
        for (let i = 0; i < entry.actions.length; i++) {
            const a = entry.actions[i]
            if (String(a.identifier).toLowerCase() === "default") continue
            if (!a.text) continue
            out.push(a)
        }
        return out
    }

    // Invoque une action nommée. Si la notification a été fermée par son
    // application entre-temps, l'objet Qt ne répond plus : on garde l'entrée
    // (l'historique n'appartient pas au client) et on ne fait rien d'autre.
    function invokeNotifAction(entry, identifier) {
        if (!entry || !entry.raw) return false
        const actions = entry.raw.actions || []
        for (let i = 0; i < actions.length; i++) {
            if (String(actions[i].identifier) !== String(identifier)) continue
            try { actions[i].invoke() } catch (e) { return false }
            // Le retrait de la carte ne se décide pas ici : le serveur ferme la
            // notification de façon asynchrone (sauf action « resident »), et son
            // signal `closed` s'en charge. Tester `tracked` juste après `invoke()`
            // ne pouvait rien voir.
            return true
        }
        console.warn("action " + identifier + " introuvable (notification fermée ?)")
        return false
    }

    function clearNotifications() {
        const list = islandRight.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (!list[i].raw) continue
            try { list[i].raw.tracked = false } catch (e) {}
        }
        islandRight.notificationsList = []
    }

    // Ouvre ce que le titre annonce, puis retire la notification. `closeCentre`
    // referme le popup des notifications (un toast n'en ouvre pas).
    function openNotifTarget(entry, closeCentre) {
        if (!islandRight.notifHasTarget(entry)) return false
        const target = entry.target
        if (target.kind === "action") {
            const actions = entry.raw ? entry.raw.actions : []
            for (let i = 0; i < actions.length; i++) {
                if (String(actions[i].identifier) !== String(target.actionId)) continue
                try { actions[i].invoke() } catch (e) {}
                break
            }
        } else {
            // Même raison que dans le tiroir : l'échec doit être visible.
            const label = String(entry.summary || entry.appName || "cette notification")
            Quickshell.execDetached(
                ["bash", Quickshell.shellPath("core/notif_open.sh"), label, "--"].concat(target.cmd))
        }
        islandRight.forgetNotif(entry)
        if (islandRight.latestToast && String(islandRight.latestToast.id) === String(entry.id))
            islandRight.latestToast = null
        if (closeCentre) Theme.activePopup = ""
        return true
    }

    // Écarte une application des toasts, ou la rétablit. La liste vit dans
    // core/style_vars.json : Theme.qml la recharge via son FileView.
    function setToastQuiet(appName, quiet) {
        if (!appName) return
        quietNotifProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                                  "notif_quiet", quiet ? "true" : "false", appName]
        quietNotifProc.running = true
    }

    function quietToastSource() {
        if (!latestToast) return
        setToastQuiet(latestToast.appName, true)
        latestToast = null
    }

    property Process quietNotifProc: Process {}

    Process {
        id: sysInfoProc
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    islandRight.applySystemInfo(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: sysActionProc
        onExited: {
            if (islandRight.sysActionQueue.length > 0) {
                const q = islandRight.sysActionQueue.slice()
                const next = q.shift()
                islandRight.sysActionQueue = q
                islandRight.startSysAction(next)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // Stale result: a newer action is queued, don't overwrite the optimistic UI value
                if (islandRight.sysActionQueue.length > 0) return
                try {
                    const parsed = JSON.parse(text.trim())
                    if (typeof parsed.limit_80 === "boolean" && !parsed.battery) {
                        islandRight.batLimit80 = parsed.limit_80
                        islandRight.refreshSystemInfo()
                    } else {
                        // Full info or partial ({volume} / {brightness}) payload
                        islandRight.applySystemInfo(parsed)
                    }
                } catch (e) {
                    islandRight.refreshSystemInfo()
                }
            }
        }
    }


    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: islandRight.refreshSystemInfo()
    }

    // Les touches média changent le volume via osd.sh : l'OSD est le seul signal
    // disponible, on s'en sert pour rafraîchir l'icône tout de suite au lieu
    // d'attendre le prochain sondage de 5 s. On ne teste pas `osdVisible` :
    // showOsd() écrit kind puis valeur avant de passer visible, donc au moment
    // du signal la surface est encore masquée.
    Connections {
        target: Theme
        function onOsdValueChanged() {
            if (Theme.osdKind === "volume" || Theme.osdKind === "mute") islandRight.refreshSystemInfo()
        }
        function onOsdKindChanged() {
            if (Theme.osdKind === "volume" || Theme.osdKind === "mute") islandRight.refreshSystemInfo()
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: ARCH-UPDATE CHECK SERVICE
    // ────────────────────────────────────────────────────────────────────────
    Process {
        id: checkArchUpdateInstalledProc
        command: ["sh", "-c", "command -v arch-update >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                islandRight.hasArchUpdate = (text.trim() === "1")
                if (islandRight.hasArchUpdate && !checkUpdatesProc.running) {
                    checkUpdatesProc.running = true
                }
            }
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["sh", "-c", "timeout 15 sh -c '(checkupdates 2>/dev/null; yay -Qua 2>/dev/null)' | grep -v '^\\s*$' | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const count = parseInt(text.trim(), 10)
                    islandRight.pendingUpdatesCount = isNaN(count) ? 0 : count
                } catch (e) {
                    islandRight.pendingUpdatesCount = 0
                }
            }
        }
    }

    Timer {
        id: checkUpdatesTimer
        interval: 1800000 // Refresh every 30 minutes
        running: islandRight.hasArchUpdate
        repeat: true
        onTriggered: {
            if (!checkUpdatesProc.running) checkUpdatesProc.running = true
        }
    }

    Component.onCompleted: {
        checkArchUpdateInstalledProc.running = true

        // Crochets de diagnostic, exposés par IPC depuis Theme :
        //   quickshell ipc call shell notifTargets     → JSON des cibles résolues
        //   quickshell ipc call shell notifOpenLatest  → ouvre la cible la plus récente
        // Sans eux, « le clic ne fait rien » ne se distingue pas de « pas de cible ».
        Theme.notifTargetsHook = function() {
            const out = []
            const list = islandRight.notificationsList
            for (let i = 0; i < list.length; i++) {
                const e = list[i]
                out.push({
                    id: String(e.id),
                    app: e.appName || "",
                    resume: e.summary || "",
                    regle: e.target ? String(e.target.rule || "") : "",
                    type: e.target ? String(e.target.kind || "") : "",
                    cible: e.target ? String(e.target.display || "") : ""
                })
            }
            return JSON.stringify(out)
        }
        Theme.notifClearHook = function() {
            islandRight.clearNotifications()
            return true
        }
        Theme.notifOpenHook = function() {
            const list = islandRight.notificationsList
            for (let i = 0; i < list.length; i++)
                if (islandRight.notifHasTarget(list[i]))
                    return islandRight.openNotifTarget(list[i], true)
            return false
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 5: MAIN RIGHT ISLAND BAR UI
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: islandBg
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }


        Row {
            id: mainRow
            anchors.centerIn: parent
            spacing: 12

            // ────────────────────────────────────────────────────────────────
            // Applets posés sur l'îlot droit (registre bar_applets.json).
            AppletRow {
                ile: "droite"
                anchors.verticalCenter: parent.verticalCenter
            }

            // SUB-SECTION 5.1: SYSTRAY & NOTIFICATIONS
            // ────────────────────────────────────────────────────────────────
            Row {
                id: systraySection
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Notification Center Trigger Button
                Rectangle {
                    id: notifBtn
                    width: notifRow.implicitWidth + 10
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: Theme.activePopup === "notifications"
                        ? Theme.accent
                        : (notifMa.containsMouse ? Theme.surfaceVariant : "transparent")

                    Row {
                        id: notifRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: islandRight.notificationsList.length > 0 ? "bell" : "bell-off"
                            size: Theme.iconSm
                            color: Theme.activePopup === "notifications"
                                ? Theme.bg
                                : (islandRight.notificationsList.length > 0 ? Theme.warn : Theme.fg)
                        }

                        Text {
                            visible: islandRight.notificationsList.length > 0
                            text: String(islandRight.notificationsList.length)
                            color: Theme.activePopup === "notifications" ? Theme.bg : Theme.warn
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: notifMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            islandRight.latestToast = null
                            Theme.togglePopup("notifications")
                        }
                    }
                }

                // Arch-Update Tray Button
                Rectangle {
                    id: archUpdateBtn
                    visible: islandRight.hasArchUpdate
                    width: archUpdateRow.implicitWidth + 10
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: archUpdateMa.containsMouse ? Theme.surfaceVariant : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        id: archUpdateRow
                        anchors.centerIn: parent
                        spacing: 4

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "arch"
                            size: Theme.iconSm
                            color: islandRight.pendingUpdatesCount > 0 ? Theme.warn : Theme.fg
                            opacityLevel: islandRight.pendingUpdatesCount > 0 ? 1 : 0.6
                        }

                        Text {
                            visible: islandRight.pendingUpdatesCount > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(islandRight.pendingUpdatesCount)
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: archUpdateMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (!checkUpdatesProc.running) checkUpdatesProc.running = true
                            } else {
                                Quickshell.execDetached(["kitty", "arch-update"])
                            }
                        }
                    }
                }

            }

            // Visual Separator 1 (Between Systray and Network)
            Rectangle {
                width: 1
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceVariant
            }


            // Visual Separator 2 (Visually separating Systray/Network from System Controls)
            Rectangle {
                width: 2
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accentMuted
                opacity: 0.6
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.3: SYSTEM CONTROLS & HARDWARE MONITORS
            // ────────────────────────────────────────────────────────────────
            // Battery status & 80% limit, volume slider, brightness slider
            Rectangle {
                id: systemControlsBox
                // Volume parti dans son applet : ce bloc ne garde que ce qui
                // existe sur la machine (batterie, rétroéclairage). Sur une tour,
                // il n'a plus rien à montrer et ne prend plus de place.
                visible: islandRight.hasBattery || islandRight.hasBacklight
                width: sysControlsRow.implicitWidth + 14
                height: 28
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.activePopup === "system"
                    ? Qt.alpha(Theme.accent, 0.25)
                    : (sysBoxMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.color: Theme.activePopup === "system" ? Theme.accent : "transparent"
                border.width: 1

                MouseArea {
                    id: sysBoxMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.togglePopup("system")
                }

                Row {
                    id: sysControlsRow
                    anchors.centerIn: parent
                    spacing: 12

                    // Battery indicator (+ 80% shield badge when limiter is active, hidden on Desktop Tower)
                    Row {
                        visible: islandRight.hasBattery
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: islandRight.batteryIconFor(islandRight.batPercent, islandRight.batStatus)
                            size: Theme.iconSm
                            color: (islandRight.batPercent <= 15 && islandRight.batStatus !== "Charging")
                                ? Theme.error
                                : (islandRight.batStatus === "Charging" ? Theme.success : Theme.accent)
                        }

                        Text {
                            text: islandRight.batPercent + "%"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: islandRight.batPercent <= 15
                        }

                        Rectangle {
                            visible: islandRight.batLimit80
                            width: 24
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 2
                            color: Theme.success
                            Text {
                                anchors.centerIn: parent
                                text: "80%"
                                color: Theme.bg
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }
                        }
                    }

                    // Entrée unique vers le panneau système (volume, luminosité, batterie).
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.4: TABLET MODE VIRTUAL KEYBOARD BUTTON
            // ────────────────────────────────────────────────────────────────
            // Visible only in Lenovo Yoga Tablet Mode
            Rectangle {
                id: keyboardBtn
                visible: islandRight.tabletMode
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Icon {
                    anchors.centerIn: parent
                    glyph: "keyboard"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "wvkbd-mobintl || cosmic-osk || wvkbd"])
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 5.5: POWER MENU BUTTON (Scaled to bar height)
            // ────────────────────────────────────────────────────────────────
            Rectangle {
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Icon {
                    anchors.centerIn: parent
                    glyph: "power"
                    size: Theme.iconSm
                    color: Theme.activePopup === "power"
                        ? Theme.bg
                        : (powerMa.containsMouse ? Theme.error : Theme.fg)
                    opacityLevel: Theme.activePopup === "power" ? 1 : 0.85
                }

                MouseArea {
                    id: powerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.togglePopup("power")
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 6: HYPRLAND OUTSIDE CLICK / FOCUS GRAB
    // ────────────────────────────────────────────────────────────────────────
    // Dismisses open right-island popups when clicking anywhere on the desktop
    HyprlandFocusGrab {
        active: Theme.activePopup === "system"
            || Theme.activePopup === "notifications"
        windows: [
            systemPanelPopup,
            notificationsPopup,
            islandRight.QsWindow.window
        ]
        onCleared: {
            if (Theme.activePopup !== "calendar") {
                Theme.activePopup = ""
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 7: POPUP WINDOWS
    // ────────────────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.2: SYSTEM HARDWARE & CONTROLS POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Controls ASUS Battery 80% charge threshold, audio volume slider, and backlight brightness slider
    PopupWindow {
        id: systemPanelPopup
        anchor.item: systemControlsBox
        anchor.rect.x: (systemControlsBox.width - implicitWidth) / 2
        anchor.rect.y: islandRight.popupY(systemControlsBox)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(systemControlsBox, (systemControlsBox.width - implicitWidth) / 2, implicitWidth), islandRight.popupY(systemControlsBox), anchor.rect.width, anchor.rect.height)
        implicitWidth: 310
        implicitHeight: sysCol.implicitHeight + 28
        color: "transparent"
        visible: Theme.activePopup === "system"

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: sysCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 14

                Row {
                    spacing: Theme.space2

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "cog"
                        size: Theme.iconSm
                        color: Theme.accent
                        opacityLevel: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Contrôles système · " + islandRight.hostName
                        color: Theme.fg
                        font.pixelSize: Theme.textLg
                        font.bold: true
                    }
                }

                // 2. Brightness Slider Control (Laptop / Backlight only)
                Column {
                    visible: islandRight.hasBacklight
                    width: parent.width
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "brightness"
                                size: Theme.iconSm
                                color: Theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Luminosité de l'écran"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            text: islandRight.briPercent + "%"
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    Rectangle {
                        id: briTrack
                        width: parent.width
                        height: 12
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: Math.min(1, Math.max(0.05, islandRight.briPercent / 100)) * parent.width
                            height: parent.height
                            radius: Theme.globalRadius
                            color: Theme.accentMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function applyPos(mx) {
                                const pct = Math.round(Math.max(0.05, Math.min(1, mx / briTrack.width)) * 100)
                                islandRight.briPercent = pct
                                islandRight.runSysAction(["brightness", String(pct)])
                            }
                            onPressed: mouse => applyPos(mouse.x)
                            onPositionChanged: mouse => { if (pressed) applyPos(mouse.x) }
                        }
                    }
                }

                // Divider
                Rectangle {
                    visible: islandRight.hasBattery
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariant
                }

                // 3. Battery Status & 80% Charge Limiter Card (Laptop only)
                Rectangle {
                    visible: islandRight.hasBattery
                    width: parent.width
                    height: 68
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: islandRight.batLimit80 ? Theme.success : "transparent"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 20

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.space1

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "battery"
                                    size: Theme.iconSm
                                    color: Theme.fg
                                    opacityLevel: 0.9
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Batterie : " + islandRight.batPercent + "% (" + islandRight.batStatus + ")"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Limiter la charge à 80% (Santé)"
                                color: Qt.alpha(Theme.fg, 0.9)
                                font.pixelSize: Theme.textXs
                            }

                            // 80% Limiter Toggle Button
                            Rectangle {
                                width: 64
                                height: 22
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.globalRadius
                                color: islandRight.batLimit80 ? Theme.success : Theme.bg
                                border.color: islandRight.batLimit80 ? Theme.success : Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: islandRight.batLimit80 ? "80% ON" : "100%"
                                    color: islandRight.batLimit80 ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const nextTarget = islandRight.batLimit80 ? 100 : 80
                                        islandRight.batLimit80 = !islandRight.batLimit80
                                        islandRight.runSysAction(["limit", String(nextTarget)])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.4: NOTIFICATION CENTER POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Chronological notification history with dismiss & clear-all controls
    PopupWindow {
        id: notificationsPopup
        anchor.item: notifBtn
        anchor.rect.x: (notifBtn.width - implicitWidth) / 2
        anchor.rect.y: islandRight.popupY(notifBtn)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(notifBtn, (notifBtn.width - implicitWidth) / 2, implicitWidth), islandRight.popupY(notifBtn), anchor.rect.width, anchor.rect.height)
        implicitWidth: 320
        implicitHeight: 340
        color: "transparent"
        visible: Theme.activePopup === "notifications"

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ────────────────────────────────────────────────────────────
                // En-tête : compteur discret, action neutre au repos
                // ────────────────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "bell"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: islandRight.notificationsList.length > 0
                            text: islandRight.notificationsList.length
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    // Historique : petite icône à gauche de « Tout effacer », qui
                    // ouvre le tiroir indépendant (tout ce qui est arrivé, y
                    // compris ce qui a été effacé ici ou fermé par l'application).
                    Item {
                        id: historyBtn
                        anchors.right: clearBtn.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 20

                        Icon {
                            anchors.centerIn: parent
                            glyph: "history"
                            size: 12
                            color: historyMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                            opacityLevel: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: historyMa
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.activePopup = ""
                                Theme.notifHistoryVisible = true
                            }
                        }
                    }

                    // « Tout effacer » : discret au repos, rouge seulement au survol.
                    // Le rouge reste un signal, pas une décoration.
                    Item {
                        id: clearBtn
                        visible: islandRight.notificationsList.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: clearText.implicitWidth + 12
                        height: 20

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.globalRadius
                            color: clearMa.containsMouse ? Qt.alpha(Theme.error, 0.12) : "transparent"
                        }

                        Text {
                            id: clearText
                            anchors.centerIn: parent
                            text: "Tout effacer"
                            color: clearMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRight.clearNotifications()
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // Cartes empilées, la plus récente en tête
                // ────────────────────────────────────────────────────────────
                Flickable {
                    id: notifFlick
                    width: parent.width
                    // Le pied « sans apparition spontanée » rogne la liste d'autant.
                    height: 268 - (quietFooter.visible ? quietFooter.height + 6 : 0)
                    contentWidth: width
                    contentHeight: notifListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: notifListCol
                        width: parent.width
                        spacing: 8

                        // État vide
                        Item {
                            visible: islandRight.notificationsList.length === 0
                            width: parent.width
                            height: notifFlick.height

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.space2

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    glyph: "bell-off"
                                    size: Theme.iconLg
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    opacityLevel: 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Aucune notification"
                                    color: Qt.alpha(Theme.fg, 0.55)
                                    font.pixelSize: Theme.textSm
                                }
                            }
                        }

                        Repeater {
                            model: islandRight.notificationsList

                            Rectangle {
                                id: notifCard
                                required property var modelData
                                required property int index
                                width: notifListCol.width
                                height: notifCardCol.implicitHeight + 20
                                radius: Theme.globalRadius
                                color: cardMa.containsMouse
                                    ? Qt.lighter(Theme.surfaceVariant, 1.15)
                                    : Theme.surfaceVariant
                                clip: true

                                Behavior on color { ColorAnimation { duration: 120 } }

                                // Liseré d'application : 2 px, franc sur la carte la
                                // plus récente, effacé sur les anciennes.
                                Rectangle {
                                    width: 2
                                    height: parent.height
                                    color: Qt.alpha(Theme.accent, index === 0 ? 0.95 : 0.35)
                                }

                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }

                                Column {
                                    id: notifCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Item {
                                        width: parent.width
                                        height: 18

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.space1

                                            Text {
                                                text: modelData.appName
                                                width: Math.min(implicitWidth, notifCardCol.width - 78)
                                                color: Theme.accent
                                                font.pixelSize: Theme.textXs
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: "·"
                                                color: Qt.alpha(Theme.fg, 0.4)
                                                font.pixelSize: Theme.textXs
                                            }
                                            Text {
                                                text: modelData.time
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.pixelSize: Theme.textXs
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        Icon {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "close"
                                            size: 10
                                            color: closeMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)
                                            opacityLevel: 1

                                            MouseArea {
                                                id: closeMa
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: islandRight.forgetNotif(modelData)
                                            }
                                        }
                                    }

                                    // Titre = cible : curseur main et teinte accent au
                                    // survol **seulement** si une cible a été résolue.
                                    Item {
                                        width: parent.width
                                        height: notifTitle.implicitHeight

                                        Text {
                                            id: notifTitle
                                            width: parent.width
                                            text: modelData.summary
                                            color: titleMa.containsMouse && titleMa.enabled
                                                ? Theme.accent : Theme.fg
                                            font.pixelSize: Theme.textSm
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        MouseArea {
                                            id: titleMa
                                            anchors.fill: parent
                                            enabled: islandRight.notifHasTarget(modelData)
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: islandRight.openNotifTarget(modelData, true)
                                        }
                                    }

                                    Text {
                                        visible: modelData.body !== ""
                                        width: parent.width
                                        text: modelData.body
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.textXs
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }

                                    // Actions proposées par l'application
                                    // (« Ouvrir », « Mettre en pause »…) : petites
                                    // pastilles sous le corps. L'action « default »
                                    // n'y figure pas, c'est le clic sur le titre.
                                    Flow {
                                        width: parent.width
                                        visible: islandRight.notifActions(notifCard.modelData).length > 0
                                        spacing: Theme.space1

                                        Repeater {
                                            model: islandRight.notifActions(notifCard.modelData)

                                            Rectangle {
                                                required property var modelData
                                                width: actionLabel.implicitWidth + Theme.space3 * 2
                                                height: 20
                                                radius: Theme.globalRadius
                                                color: actionMa.containsMouse
                                                    ? Qt.alpha(Theme.accent, 0.16)
                                                    : Qt.alpha(Theme.fg, 0.06)

                                                Text {
                                                    id: actionLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.text
                                                    color: actionMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                                                    font.pixelSize: Theme.textXs
                                                    elide: Text.ElideRight
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }

                                                MouseArea {
                                                    id: actionMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: islandRight.invokeNotifAction(notifCard.modelData, modelData.identifier)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────
                // Applications écartées des toasts : le choix se fait
                // depuis un toast (cloche barrée) et se défait ici.
                // ────────────────────────────────────────────────────
                Item {
                    id: quietFooter
                    width: parent.width
                    height: visible ? quietCol.implicitHeight + 12 : 0
                    visible: Theme.quietNotifApps.length > 0

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.08)
                    }

                    Column {
                        id: quietCol
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: parent.width
                        spacing: 6

                        Row {
                            spacing: Theme.space1

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "bell-off"
                                size: 10
                                color: Qt.alpha(Theme.fg, 0.45)
                                opacityLevel: 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications silencieuses"
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.text2xs
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: Theme.quietNotifApps

                                Rectangle {
                                    required property var modelData
                                    width: quietChipText.implicitWidth + 26
                                    height: 20
                                    radius: Theme.globalRadius
                                    color: Theme.surfaceVariant

                                    Text {
                                        id: quietChipText
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, 130)
                                        text: modelData
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.text2xs
                                        elide: Text.ElideRight
                                    }

                                    Icon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: "close"
                                        size: 9
                                        color: chipClose.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                                        opacityLevel: 1

                                        MouseArea {
                                            id: chipClose
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: islandRight.setToastQuiet(modelData, false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SUB-SECTION 7.5: EPHEMERAL NOTIFICATION TOAST POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Auto-dismissing transient toast on incoming notifications
    PopupWindow {
        id: toastPopup
        anchor.item: islandRight
        anchor.rect.x: islandRight.width - implicitWidth
        anchor.rect.y: islandRight.popupY(islandRight)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandRight.clampPopupX(islandRight, islandRight.width - implicitWidth, implicitWidth), islandRight.popupY(islandRight), anchor.rect.width, anchor.rect.height)
        implicitWidth: 300
        implicitHeight: toastCol.implicitHeight + 20
        color: "transparent"
        // Pas de toast par-dessus le tiroir de l'historique : il le recouvrirait.
        visible: islandRight.latestToast !== null && Theme.activePopup === ""
            && !Theme.notifHistoryVisible
            && Theme.quietNotifApps.indexOf(islandRight.latestToast ? islandRight.latestToast.appName : "") < 0

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceVariantBg
            radius: Theme.globalRadius
            clip: true

            // Zone de clic sur tout le toast : déclarée avant le contenu pour que
            // le bouton « écarter » du contenu reste cliquable par-dessus.
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Le clic ouvre le centre de notifications ; le toast s'efface ensuite
                // de lui-même (timer d'expiration).
                onClicked: {
                    islandRight.latestToast = null
                    Theme.activePopup = "notifications"
                }
            }

            Column {
                id: toastCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Item {
                    width: parent.width
                    height: 16

                    Icon {
                        id: toastBell
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "bell"
                        size: 10
                        color: Theme.accent
                        opacityLevel: 1
                    }

                    Text {
                        anchors.left: toastBell.right
                        anchors.leftMargin: Theme.space1
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 46)
                        text: islandRight.latestToast ? islandRight.latestToast.appName : ""
                        color: Theme.accent
                        font.pixelSize: Theme.textXs
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Écarte cette application des toasts : sa notification reste
                    // dans le centre, elle n'apparaît simplement plus ici.
                    Icon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "bell-off"
                        size: 12
                        color: toastQuietMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)
                        opacityLevel: 1

                        MouseArea {
                            id: toastQuietMa
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandRight.quietToastSource()
                        }
                    }
                }

                // Titre du toast : même règle que dans le centre — il ouvre la
                // cible et retire la notification ; le reste du toast continue
                // d'ouvrir le centre.
                Item {
                    width: parent.width
                    height: toastTitle.implicitHeight

                    Text {
                        id: toastTitle
                        width: parent.width
                        text: islandRight.latestToast ? islandRight.latestToast.summary : ""
                        color: toastTitleMa.containsMouse && toastTitleMa.enabled
                            ? Theme.accent : Theme.fg
                        font.pixelSize: Theme.textSm
                        font.bold: true
                        wrapMode: Text.WordWrap
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: toastTitleMa
                        anchors.fill: parent
                        enabled: islandRight.latestToast
                            ? islandRight.notifHasTarget(islandRight.latestToast) : false
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (islandRight.latestToast)
                                islandRight.openNotifTarget(islandRight.latestToast, false)
                        }
                    }
                }

                Text {
                    visible: Boolean(islandRight.latestToast && islandRight.latestToast.body !== "")
                    width: parent.width
                    text: islandRight.latestToast ? islandRight.latestToast.body : ""
                    color: Qt.alpha(Theme.fg, 0.85)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
