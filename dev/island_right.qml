import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Notifications

// ════════════════════════════════════════════════════════════════════════════
// ÎLOT DROIT — ce qui reste quand la barre est devenue modulaire.
// ════════════════════════════════════════════════════════════════════════════
// Tous les éléments de barre sont des applets, posés par `AppletRow` selon le
// registre `bar_applets.json` : comptes, système, volume, systray, réseau,
// notifications, mises à jour, alimentation.
//
// Il reste ici trois choses qui ne sont pas des éléments de barre :
//   • Section 1-3 : le centre de notifications (serveur, historique, cibles,
//     toasts) — un service, pas un bouton ; l'applet « notifications » n'en est
//     que la cloche et publie son compte dans Theme.notifCount ;
//   • Section 5 : le bouton clavier virtuel (mode tablette) ;
//   • Section 6-7 : l'attrapeur de clic extérieur et les deux fenêtres du centre
//     de notifications (panneau et toast).
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
    // Batterie, volume et luminosité sont partis dans les applets
    // « alimentation » et « volume ». Il ne reste ici que le mode tablette,
    // qui commande le bouton clavier virtuel.
    property bool tabletMode: false


    // Notifications State
    property var notificationsList: []
    // L'applet de la cloche ne peut pas lire cette liste (identifiants locaux au
    // fichier) : le compte est publié dans le singleton Theme.
    onNotificationsListChanged: Theme.notifCount = notificationsList.length
    property var latestToast: null

    // Le compteur de paquets en attente vit dans l'applet « maj ».

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HELPER FUNCTIONS & FORMATTERS
    // ────────────────────────────────────────────────────────────────────────
    // Renvoient un NOM d'icône (Icon.qml), plus un glyphe brut : c'est ce qui
    // garantit une seule famille, une seule taille et un seul centrage.


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
            // « Ne pas déranger » coupe le toast, pas l'historique : la
            // notification est déjà dans la liste ci-dessus.
            if (!Theme.doNotDisturb && Theme.quietNotifApps.indexOf(entry.appName) < 0) {
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

    // Le seul sondage système qui reste : le mode tablette, qui commande le
    // bouton clavier virtuel (Yoga). Batterie, volume et luminosité sont lus par
    // les applets concernés, chacun pour son compte.
    Process {
        id: modeTabletteProc
        command: ["python3", Quickshell.shellPath("core/system_service.py"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (typeof d.tablet_mode === "boolean") islandRight.tabletMode = d.tablet_mode
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!modeTabletteProc.running) modeTabletteProc.running = true
    }


    Component.onCompleted: {
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
                ile: "haut:fin"
                anchors.verticalCenter: parent.verticalCenter
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

        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 6: HYPRLAND OUTSIDE CLICK / FOCUS GRAB
    // ────────────────────────────────────────────────────────────────────────
    // Dismisses open right-island popups when clicking anywhere on the desktop
    HyprlandFocusGrab {
        active: Theme.activePopup === "notifications"
        windows: [
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
    // SUB-SECTION 7.4: NOTIFICATION CENTER POPUP
    // ────────────────────────────────────────────────────────────────────────
    // Chronological notification history with dismiss & clear-all controls
    PopupWindow {
        id: notificationsPopup
        // La cloche est devenue l'applet « notifications » : le panneau s'ancre
        // au bord droit de l'îlot, comme l'ancien menu d'alimentation.
        anchor.item: islandRight
        anchor.rect.x: islandRight.width - implicitWidth
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
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
