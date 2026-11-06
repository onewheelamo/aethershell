import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ────────────────────────────────────────────────────────────────────────────
// TIROIR DE L'HISTORIQUE DES NOTIFICATIONS
// ────────────────────────────────────────────────────────────────────────────
// Surface indépendante du petit panneau de notifications : celui-ci montre les
// notifications courantes (avec toast et boutons d'action), ce tiroir garde la
// trace de TOUT ce qui est arrivé, y compris ce qui a été effacé du panneau ou
// fermé par l'application émettrice.
//
// Source : `~/.cache/quickshell/notifications-history.jsonl`, écrit par
// core/notif_target.py (une ligne par notification, la plus récente en fin de
// fichier, plafond 200 tenu par core/notif_history.py).
//
// Un clic sur le titre rouvre la cible déjà résolue à la réception — la
// notification peut être morte depuis longtemps, la commande est figée dans
// l'entrée. Une cible de type « action » n'est pas rouvrable (il faudrait le
// client) : son titre reste du texte.
//
// Pas de flou sur cette surface : le tiroir occupe presque toute la hauteur,
// une règle de flou sur son namespace flouterait tout l'écran. Le fond est donc
// plus dense que celui du panneau (0.92 au lieu de l'opacité des surfaces).
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property int drawerWidth: 380
    readonly property color surfaceColor: Qt.alpha(Theme.surface, 0.92)
    property var rows: []
    property int entryCount: 0
    // Ligne sélectionnée au clavier (-1 : aucune). Seules les cartes comptent,
    // pas les séparateurs de jour.
    property int selectedRow: -1
    // Garde-fou, pas une mesure : dans les 250 ms qui suivent le map, un clic
    // extérieur est ignoré. Une surface plein écran qui apparaît sous le curseur
    // peut recevoir un clic résiduel ; la marge coûte trois lignes et évite de
    // refermer le tiroir qu'on vient d'ouvrir.
    property double openedAt: 0

    signal closeRequested()

    // `Quickshell.env()` rend `undefined` pour une variable absente, et non une
    // chaîne vide : un test `!== ""` passait donc toujours, la propriété (typée
    // string) retombait sur "" et le chemin devenait « /quickshell/… » — le
    // panneau lisait un fichier inexistant et l'historique paraissait vidé, alors
    // que le script d'écriture, lui, visait le bon fichier. Tester la valeur
    // elle-même (faux pour undefined comme pour "").
    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        if (xdg) return String(xdg)
        const home = Quickshell.env("HOME")
        return home ? String(home) + "/.cache" : ""
    }

    // ── lecture de l'historique ─────────────────────────────────────────────
    FileView {
        id: historyFile
        path: root.cacheDir + "/quickshell/notifications-history.jsonl"
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: root.parseHistory(text())
    }

    function parseHistory(txt) {
        const lines = String(txt || "").split("\n")
        const entries = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line === "") continue
            try {
                const e = JSON.parse(line)
                if (e && e.id) entries.push(e)
            } catch (err) { /* ligne illisible : ignorée */ }
        }
        entries.reverse()                       // la plus récente en tête
        root.entryCount = entries.length

        const rows = []
        let lastDay = ""
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i]
            const day = String(e.ts || "").slice(0, 10)
            if (day !== lastDay) {
                lastDay = day
                rows.push({ type: "day", label: root.dayLabel(day), key: "d" + day })
            }
            rows.push({ type: "entry", entry: e, key: "e" + e.id })
        }
        root.rows = rows
    }

    function dayLabel(day) {
        const now = new Date()
        const pad = n => (n < 10 ? "0" + n : String(n))
        const today = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
        const yesterdayDate = new Date(now.getTime() - 86400000)
        const yesterday = yesterdayDate.getFullYear() + "-"
               + pad(yesterdayDate.getMonth() + 1) + "-" + pad(yesterdayDate.getDate())
        if (day === today) return "Aujourd'hui"
        if (day === yesterday) return "Hier"
        const parts = day.split("-")
        return parts.length === 3 ? parts[2] + "/" + parts[1] + "/" + parts[0] : day
    }

    // ── actions sur l'historique ────────────────────────────────────────────
    Process {
        id: historyCmd
        onExited: historyFile.reload()
    }

    function deleteEntry(id) {
        historyCmd.command = ["python3", Quickshell.shellPath("core/notif_history.py"), "delete", String(id)]
        historyCmd.running = true
    }

    // Bascule immédiate à l'écran, écriture derrière : attendre la réponse du
    // script rendrait le clic mou, alors que l'effet est purement local.
    function basculerDnd() {
        Theme.doNotDisturb = !Theme.doNotDisturb
        dndProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                           "style", "do_not_disturb", Theme.doNotDisturb ? "true" : "false"]
        dndProc.running = true
    }

    Process {
        id: dndProc
    }

    function clearHistory() {
        historyCmd.command = ["python3", Quickshell.shellPath("core/notif_history.py"), "clear"]
        historyCmd.running = true
    }

    function reopen(entry) {
        const target = entry && entry.target ? entry.target : null
        if (!target || target.kind === "action") return false
        const aCmd = target.cmd && target.cmd.length > 0
        const aFocus = target.focus && target.focus.length > 0
        if (!aCmd && !aFocus) return false
        // Passer par notif_open.sh plutôt que `execDetached` : une cible morte
        // (binaire désinstallé, alias renommé) doit se voir, sinon le clic ne
        // produit rien et rien ne dit pourquoi. Le script met au focus la fenêtre
        // déjà ouverte avant de lancer quoi que ce soit.
        let args = ["bash", Quickshell.shellPath("core/notif_open.sh"),
                    String(entry.summary || entry.app || "cette notification")]
        const focus = target.focus || []
        for (let i = 0; i < focus.length; i++)
            args = args.concat(["--focus", String(focus[i])])
        Quickshell.execDetached(args.concat(["--"]).concat(target.cmd || []))
        return true
    }

    // ── navigation au clavier ───────────────────────────────────────────────
    function entryRowIndexes() {
        const out = []
        for (let i = 0; i < rows.length; i++)
            if (rows[i] && rows[i].type === "entry") out.push(i)
        return out
    }

    function moveSelection(step) {
        const dispo = entryRowIndexes()
        if (dispo.length === 0) return
        let pos = dispo.indexOf(selectedRow)
        if (pos < 0) pos = step > 0 ? -1 : dispo.length
        pos = Math.min(Math.max(pos + step, 0), dispo.length - 1)
        selectedRow = dispo[pos]
        historyList.positionViewAtIndex(selectedRow, ListView.Contain)
    }

    function selectedEntry() {
        const ligne = rows[selectedRow]
        return (ligne && ligne.type === "entry") ? ligne.entry : null
    }

    function activateSelection() {
        const entry = selectedEntry()
        if (entry) reopen(entry)
    }

    function deleteSelection() {
        const entry = selectedEntry()
        if (!entry) return
        deleteEntry(entry.id)
        selectedRow = -1        // la liste est relue : l'index ne veut plus rien dire
    }

    function canReopen(entry) {
        const target = entry && entry.target ? entry.target : null
        if (!target || target.kind === "action") return false
        return Boolean(target.cmd && target.cmd.length > 0)
    }

    // ── la surface : un plein écran transparent (clic extérieur, Échap) avec
    //    le tiroir posé à droite, qui glisse depuis le bord.
    PanelWindow {
        id: historyWindow
        // La surface reste montée tant que le tiroir n'est pas complètement sorti :
        // sinon elle se démapte au premier changement d'état et coupe l'animation.
        visible: Theme.notifHistoryVisible || historyWindow.reveal > 0
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Le clavier est pris pendant l'ouverture seulement : à la fermeture, il
        // revient tout de suite à l'application, alors que le tiroir finit de
        // sortir. (Le passage à None ne recrée pas la couche : l'animation de
        // sortie avait été coupée par la course `visible`/timer, pas par ceci.)
        WlrLayershell.keyboardFocus: Theme.notifHistoryVisible
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-notif-history"

        // Avancement du glissement, 0 = hors écran à droite, 1 = posé.
        // Un nombre plutôt qu'un booléen : la position se déduit d'un ancrage à
        // droite et d'une marge interpolée, donc elle ne dépend jamais de
        // parent.width au moment où la fenêtre est encore à 0 px de large.
        property real reveal: 0
        Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // L'animation s'arme une frame après le map (même raison que la pastille
        // de capture) : sinon la première image est déjà à l'arrivée.
        Timer {
            id: openTimer
            interval: 40
            onTriggered: historyWindow.reveal = 1
        }

        Connections {
            target: Theme
            function onNotifHistoryVisibleChanged() {
                if (Theme.notifHistoryVisible) {
                    root.selectedRow = -1
                    root.openedAt = Date.now()
                    Theme.activePopup = ""      // le panneau de notifications s'efface
                    historyFile.reload()
                    openTimer.restart()
                } else {
                    openTimer.stop()
                    historyWindow.reveal = 0
                }
            }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: Theme.notifHistoryVisible
            Keys.onEscapePressed: Theme.notifHistoryVisible = false
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onReturnPressed: root.activateSelection()
            Keys.onEnterPressed: root.activateSelection()
            Keys.onDeletePressed: root.deleteSelection()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                // 250 → 450 ms : le relâchement du clic qui a ouvert le tiroir
                // (icône de l'en-tête du panneau) arrive parfois après le map de
                // cette surface plein écran, et passait pour un clic extérieur.
                if (Date.now() - root.openedAt < 450) return
                Theme.notifHistoryVisible = false
            }
        }

        Rectangle {
            id: drawer
            width: root.drawerWidth
            height: parent.height - 28
            y: 14
            anchors.right: parent.right
            // 14 px du bord une fois posé ; à reveal = 0 le tiroir est entièrement
            // sorti à droite (marge négative de sa propre largeur).
            anchors.rightMargin: 14 - (1 - historyWindow.reveal) * (width + 20)
            radius: Theme.globalRadius
            color: root.surfaceColor

            // Sans cette surface, un clic sur une carte (hors titre, croix ou
            // bouton) traversait le tiroir et atteignait le capteur plein
            // écran : cliquer une notification la refermait.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
            border.color: Qt.alpha(Theme.accent, 0.22)
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ── en-tête ─────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 24

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "history"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Historique"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.entryCount > 0
                            text: root.entryCount
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    // « Ne pas déranger » : à gauche de « Tout effacer », et
                    // visible même sans notification — c'est justement quand il
                    // n'y a rien à effacer qu'on veut couper les toasts.
                    Item {
                        id: dndItem
                        anchors.right: parent.right
                        anchors.rightMargin: clearItem.visible ? clearItem.width + 10 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: dndPill.width
                        height: 20

                        Rectangle {
                            id: dndPill
                            width: dndRow.implicitWidth + 14
                            height: 20
                            radius: 10
                            color: Theme.doNotDisturb ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.07)
                            border.width: 1
                            border.color: Theme.doNotDisturb ? Theme.accent : "transparent"

                            Row {
                                id: dndRow
                                anchors.centerIn: parent
                                spacing: 4

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: Theme.doNotDisturb ? "bell-off" : "bell"
                                    size: 11
                                    color: Theme.doNotDisturb ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Ne pas déranger"
                                    color: Theme.doNotDisturb ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                                    font.pixelSize: Theme.textXs
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.basculerDnd()
                        }
                    }

                    Item {
                        id: clearItem
                        visible: root.entryCount > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: clearLabel.implicitWidth + 12
                        height: 20

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.globalRadius
                            color: clearMa.containsMouse ? Qt.alpha(Theme.error, 0.12) : "transparent"
                        }

                        Text {
                            id: clearLabel
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
                            onClicked: root.clearHistory()
                        }
                    }
                }

                // ── liste ───────────────────────────────────────────────
                ListView {
                    id: historyList
                    width: parent.width
                    height: parent.height - 34
                    clip: true
                    model: root.rows
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Loader {
                        id: rowLoader
                        required property var modelData
                        required property int index
                        width: historyList.width
                        sourceComponent: modelData.type === "day" ? daySeparator : entryCard

                        Component {
                            id: daySeparator
                            Item {
                                width: historyList.width
                                height: 22

                                Text {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    text: modelData.label
                                    color: Qt.alpha(Theme.fg, 0.45)
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    width: parent.width - 90
                                    height: 1
                                    color: Qt.alpha(Theme.fg, 0.08)
                                }
                            }
                        }

                        Component {
                            id: entryCard
                            Rectangle {
                                id: histCard
                                width: historyList.width
                                height: histCol.implicitHeight + 16
                                radius: Theme.globalRadius
                                readonly property bool selectionne: rowLoader.index === root.selectedRow
                                color: selectionne
                                    ? Qt.lighter(Theme.surfaceVariant, 1.32)
                                    : (histMa.containsMouse ? Qt.lighter(Theme.surfaceVariant, 1.12)
                                                            : Theme.surfaceVariant)
                                border.width: selectionne ? 1 : 0
                                border.color: Theme.accent
                                Behavior on color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    id: histMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }

                                Column {
                                    id: histCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Item {
                                        width: parent.width
                                        height: 15

                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 62
                                            text: {
                                                const e = rowLoader.modelData.entry
                                                const heure = String(e.ts || "").slice(11, 16)
                                                return e.app + (heure ? "  " + heure : "")
                                            }
                                            color: Theme.accent
                                            font.pixelSize: Theme.text2xs
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Icon {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "close"
                                            size: 9
                                            color: histDeleteMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                                            opacityLevel: 1

                                            MouseArea {
                                                id: histDeleteMa
                                                anchors.fill: parent
                                                anchors.margins: -5
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.deleteEntry(rowLoader.modelData.entry.id)
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        text: rowLoader.modelData.entry.summary
                                        color: histTitleMa.containsMouse && histTitleMa.enabled
                                            ? Theme.accent : Theme.fg
                                        font.pixelSize: Theme.textSm
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        MouseArea {
                                            id: histTitleMa
                                            anchors.fill: parent
                                            enabled: root.canReopen(rowLoader.modelData.entry)
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.reopen(rowLoader.modelData.entry)
                                        }
                                    }

                                    Text {
                                        visible: String(rowLoader.modelData.entry.body || "") !== ""
                                        width: parent.width
                                        text: rowLoader.modelData.entry.body || ""
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.text2xs
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // État vide, centré sous l'en-tête
            Column {
                visible: root.entryCount === 0
                anchors.centerIn: parent
                spacing: Theme.space2

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: "history"
                    size: Theme.iconLg
                    color: Qt.alpha(Theme.fg, 0.3)
                    opacityLevel: 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Aucune notification dans l'historique"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Theme.textSm
                }
            }
        }
    }
}
