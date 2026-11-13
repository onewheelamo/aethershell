import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// ════════════════════════════════════════════════════════════════════════════
// SERVICE DE NOTIFICATIONS — serveur D-Bus, historique, cibles et toasts.
// ════════════════════════════════════════════════════════════════════════════
// Séparé de `island_right.qml` afin de rester actif quel que soit le style de
// barre (`classic` ou `island`). Alimente `Theme.notifCount`, `Theme.notifList`,
// `Theme.notifArchive`, `Theme.notifOps` et les crochets IPC de diagnostic.
// ════════════════════════════════════════════════════════════════════════════
Item {
    id: service
    visible: false

    // Item d'ancrage des toasts (en général `barContainer` dans main.qml).
    property Item anchorItem: null

    property var notificationsList: []
    property var notifArchive: []
    property var latestToast: null

    onNotificationsListChanged: {
        Theme.notifCount = notificationsList.length
        Theme.notifList = notificationsList
    }

    readonly property bool toastVisible: latestToast !== null
        && Theme.activePopup === ""
        && !Theme.notifHistoryVisible
        && Theme.quietNotifApps.indexOf(latestToast ? latestToast.appName : "") < 0

    function clampPopupX(item, relX, popupW) {
        const win = item ? item.QsWindow.window : null
        if (!win) return relX
        const ix = win.contentItem.mapFromItem(item, 0, 0).x
        const absX = Math.max(8, Math.min(win.width - popupW - 8, ix + relX))
        return absX - ix
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        actionsSupported: true
        persistenceSupported: true
        onNotification: notification => {
            notification.tracked = true
            try {
                notification.closed.connect(function () {
                    service.dropClosedNotif(notification)
                })
            } catch (e) {}
            const entry = {
                id: notification.id,
                appName: notification.appName || "Système",
                summary: notification.summary || "Notification",
                body: notification.body || "",
                time: Qt.formatDateTime(new Date(), "hh:mm"),
                actions: service.notifActionList(notification),
                raw: notification
            }
            const rafraichir = function () { service.rafraichirEntree(notification) }
            const signaux = ["appNameChanged", "summaryChanged", "bodyChanged",
                             "actionsChanged", "hintsChanged", "desktopEntryChanged",
                             "urgencyChanged", "imageChanged"]
            for (let s = 0; s < signaux.length; s++) {
                try { notification[signaux[s]].connect(rafraichir) } catch (e) {}
            }

            const all = [entry].concat(service.notificationsList)
            for (let i = 30; i < all.length; i++) {
                try { all[i].raw.tracked = false } catch (e) {}
            }
            service.notificationsList = all.slice(0, 30)
            service.requestNotifTarget(notification)
            if (!Theme.doNotDisturb && Theme.quietNotifApps.indexOf(entry.appName) < 0) {
                service.latestToast = entry
                if (toastTimer.running) toastTimer.restart()
                toastPeremption.restart()
            }
        }
    }

    FileView {
        id: archiveFile
        path: {
            const xdg = Quickshell.env("XDG_CACHE_HOME")
            const base = xdg ? String(xdg)
                             : (Quickshell.env("HOME") ? String(Quickshell.env("HOME")) + "/.cache" : "")
            return base + "/quickshell/notifications-history.jsonl"
        }
        watchChanges: true
        onFileChanged: reload()
        onLoaded: service.lireArchive(archiveFile.text())
        onTextChanged: service.lireArchive(archiveFile.text())
    }

    function lireArchive(txt) {
        const lignes = String(txt || "").split("\n")
        const out = []
        for (let i = lignes.length - 1; i >= 0 && out.length < 6; i--) {
            const l = lignes[i].trim()
            if (l === "") continue
            try {
                const e = JSON.parse(l)
                if (!e || !e.id) continue
                out.push({
                    id: e.id,
                    appName: e.app || "",
                    summary: e.summary || "",
                    body: e.body || "",
                    time: String(e.ts || "").slice(11, 16),
                    archive: true
                })
            } catch (err) {}
        }
        service.notifArchive = out
        Theme.notifArchive = out
    }

    Timer {
        id: toastTimer
        interval: 4500
        repeat: false
        running: service.toastVisible
        onTriggered: service.latestToast = null
    }

    Timer {
        id: toastPeremption
        interval: 60000
        repeat: false
        onTriggered: service.latestToast = null
    }

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

        return JSON.stringify({
            id: String(notification.id),
            appName: notification.appName || "",
            desktopEntry: notification.desktopEntry || "",
            summary: notification.summary || "",
            body: notification.body || "",
            hints: plainHints,
            actions: service.notifActionList(notification)
        })
    }

    function requestNotifTarget(notification) {
        service.targetQueue.push(service.notifTargetPayload(notification))
        service.pumpNotifTargets()
    }

    function pumpNotifTargets() {
        if (!notifResolver.running) return
        while (service.targetQueue.length > 0)
            notifResolver.write(service.targetQueue.shift() + "\n")
    }

    function applyNotifTarget(line) {
        let res
        try { res = JSON.parse(String(line)) } catch (e) { return }
        const id = String(res.id || "")
        delete res.id
        const list = service.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].id) !== id) continue
            const merged = Object.assign({}, list[i], { target: res })
            const copy = list.slice()
            copy[i] = merged
            service.notificationsList = copy
            if (service.latestToast && String(service.latestToast.id) === id)
                service.latestToast = merged
            return
        }
    }

    Process {
        id: notifResolver
        running: true
        stdinEnabled: true
        command: ["python3", Quickshell.shellPath("core/notif_target.py"), "--serve"]
        onStarted: service.pumpNotifTargets()
        onExited: {
            console.warn("notif_target.py s'est arrêté, nouvelle tentative dans 5 s")
            notifResolverRestart.restart()
        }
        stdout: SplitParser {
            onRead: line => service.applyNotifTarget(line)
        }
    }

    Timer {
        id: notifResolverRestart
        interval: 5000
        onTriggered: { if (!notifResolver.running) notifResolver.running = true }
    }

    function notifHasTarget(entry) {
        if (!entry || !entry.target) return false
        if (entry.target.kind === "action") return true
        return Boolean((entry.target.cmd && entry.target.cmd.length > 0)
                       || (entry.target.focus && entry.target.focus.length > 0))
    }

    function argsNotifOpen(entry) {
        const target = entry.target
        let args = ["bash", Quickshell.shellPath("core/notif_open.sh"),
                    String(entry.summary || entry.appName || "cette notification")]
        const focus = target.focus || []
        for (let i = 0; i < focus.length; i++)
            args = args.concat(["--focus", String(focus[i])])
        return args.concat(["--"]).concat(target.cmd || [])
    }

    function dropClosedNotif(notif) {
        if (!notif) return
        const list = service.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (list[i].raw !== notif) continue
            const copy = list.slice()
            copy.splice(i, 1)
            service.notificationsList = copy
            if (service.latestToast && service.latestToast.raw === notif)
                service.latestToast = null
            return
        }
    }

    function rafraichirEntree(notif) {
        if (!notif) return
        const list = service.notificationsList
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
                actions: service.notifActionList(notif),
                target: undefined
            })
            const copy = list.slice()
            copy[i] = maj
            service.notificationsList = copy
            if (service.latestToast && service.latestToast.raw === notif)
                service.latestToast = maj
            service.requestNotifTarget(notif)
            return
        }
    }

    function forgetNotif(entry) {
        if (!entry) return false
        if (entry.raw) {
            try { entry.raw.tracked = false } catch (e) {}
        }
        const list = service.notificationsList
        for (let i = 0; i < list.length; i++) {
            const meme = entry.raw ? (list[i].raw === entry.raw) : (String(list[i].id) === String(entry.id))
            if (!meme) continue
            const copy = list.slice()
            copy.splice(i, 1)
            service.notificationsList = copy
            return true
        }
        if (entry.raw) {
            console.warn("notification " + entry.id + " absente de la liste vive")
        }
        return false
    }

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

    function invokeNotifAction(entry, identifier) {
        if (!entry || !entry.raw) return false
        const actions = entry.raw.actions || []
        for (let i = 0; i < actions.length; i++) {
            if (String(actions[i].identifier) !== String(identifier)) continue
            try { actions[i].invoke() } catch (e) { return false }
            return true
        }
        console.warn("action " + identifier + " introuvable (notification fermée ?)")
        return false
    }

    function clearNotifications() {
        const list = service.notificationsList
        for (let i = 0; i < list.length; i++) {
            if (!list[i].raw) continue
            try { list[i].raw.tracked = false } catch (e) {}
        }
        service.notificationsList = []
    }

    function openNotifTarget(entry, closeCentre) {
        if (!service.notifHasTarget(entry)) return false
        const target = entry.target
        if (target.kind === "action") {
            const actions = entry.raw ? entry.raw.actions : []
            for (let i = 0; i < actions.length; i++) {
                if (String(actions[i].identifier) !== String(target.actionId)) continue
                try { actions[i].invoke() } catch (e) {}
                break
            }
        } else {
            Quickshell.execDetached(service.argsNotifOpen(entry))
        }
        service.forgetNotif(entry)
        if (service.latestToast && String(service.latestToast.id) === String(entry.id))
            service.latestToast = null
        if (typeof closeCentre === "function") {
            closeCentre()
        } else if (closeCentre) {
            Theme.activePopup = ""
            Theme.islandPanelOpen = false
        }
        return true
    }

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

    Component.onCompleted: {
        Theme.notifOps = ({
            clear: function () { service.clearNotifications() },
            forget: function (e) { service.forgetNotif(e) },
            open: function (e, fermer) { service.openNotifTarget(e, fermer) },
            invoke: function (e, ident) { service.invokeNotifAction(e, ident) },
            actions: function (e) { return service.notifActions(e) },
            hasTarget: function (e) { return service.notifHasTarget(e) },
            setQuiet: function (nom, muet) { service.setToastQuiet(nom, muet) }
        })

        Theme.notifTargetsHook = function() {
            const out = []
            const list = service.notificationsList
            for (let i = 0; i < list.length; i++) {
                const e = list[i]
                out.push({
                    id: String(e.id),
                    app: e.appName || "",
                    resume: e.summary || "",
                    regle: e.target ? String(e.target.rule || "") : "",
                    type: e.target ? String(e.target.kind || "") : "",
                    cible: e.target ? String(e.target.display || "") : "",
                    actions: service.notifActions(e)
                })
            }
            return JSON.stringify(out)
        }
        Theme.notifClearHook = function() {
            service.clearNotifications()
            return true
        }
        Theme.notifOpenHook = function() {
            const list = service.notificationsList
            for (let i = 0; i < list.length; i++)
                if (service.notifHasTarget(list[i]))
                    return service.openNotifTarget(list[i], true)
            return false
        }
        Theme.notifInvokeHook = function(actionId) {
            const list = service.notificationsList
            for (let i = 0; i < list.length; i++) {
                const acts = service.notifActions(list[i])
                for (let j = 0; j < acts.length; j++) {
                    if (String(acts[j].identifier) === String(actionId)) {
                        const ok = service.invokeNotifAction(list[i], actionId)
                        if (service.latestToast && service.latestToast.raw === list[i].raw)
                            service.latestToast = null
                        return ok
                    }
                }
            }
            return false
        }
    }

    PopupWindow {
        id: toastPopup
        anchor.item: service.anchorItem
        anchor.rect.x: service.anchorItem ? (service.anchorItem.width - implicitWidth) : 0
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: {
            if (!service.anchorItem) return
            const rx = service.anchorItem.width - implicitWidth
            anchor.rect = Qt.rect(
                service.clampPopupX(service.anchorItem, rx, implicitWidth),
                Theme.barHeight + 6,
                anchor.rect.width,
                anchor.rect.height
            )
        }
        implicitWidth: 300
        implicitHeight: toastCol.implicitHeight + 20
        color: "transparent"
        visible: service.toastVisible && service.anchorItem !== null

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceVariantBg
            radius: Theme.globalRadius
            clip: true

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    service.latestToast = null
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
                        text: service.latestToast ? service.latestToast.appName : ""
                        color: Theme.accent
                        font.pixelSize: Theme.textXs
                        font.bold: true
                        elide: Text.ElideRight
                    }

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
                            onClicked: service.quietToastSource()
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: toastTitle.implicitHeight

                    Text {
                        id: toastTitle
                        width: parent.width
                        text: service.latestToast ? service.latestToast.summary : ""
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
                        enabled: service.latestToast
                            ? service.notifHasTarget(service.latestToast) : false
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (service.latestToast)
                                service.openNotifTarget(service.latestToast, false)
                        }
                    }
                }

                Text {
                    visible: Boolean(service.latestToast && service.latestToast.body !== "")
                    width: parent.width
                    text: service.latestToast ? service.latestToast.body : ""
                    color: Qt.alpha(Theme.fg, 0.85)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                Flow {
                    width: parent.width
                    visible: Boolean(service.latestToast && service.notifActions(service.latestToast).length > 0)
                    spacing: Theme.space1

                    Repeater {
                        model: service.latestToast ? service.notifActions(service.latestToast) : []

                        Rectangle {
                            required property var modelData
                            width: toastActionLabel.implicitWidth + Theme.space3 * 2
                            height: 20
                            radius: Theme.globalRadius
                            color: toastActionMa.containsMouse
                                ? Qt.alpha(Theme.accent, 0.22)
                                : Qt.alpha(Theme.fg, 0.08)
                            border.width: 1
                            border.color: toastActionMa.containsMouse ? Theme.accent : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Text {
                                id: toastActionLabel
                                anchors.centerIn: parent
                                text: modelData.text || modelData.identifier
                                color: toastActionMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.9)
                                font.pixelSize: Theme.textXs
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: toastActionMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (service.latestToast) {
                                        service.invokeNotifAction(service.latestToast, modelData.identifier)
                                        service.latestToast = null
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
