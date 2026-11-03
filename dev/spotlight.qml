import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ─────────────────────────────────────────────────────────────────────────────
// 9. SPOTLIGHT PILL — launcher bas-centre qui remplace fuzzel
// ─────────────────────────────────────────────────────────────────────────────
// Chargée par la PanelWindow `shell-spotlight` de main.qml, elle-même pilotée
// par Theme.spotlightVisible (IPC `quickshell ipc call shell toggleSpotlight`).
//
// Trois sources, une seule liste de résultats :
//   • applications — core/app_index.json (core/app_index.py)
//   • alias        — core/app_vars.json, les mêmes que les raccourcis Hyprland
//   • commandes    — préfixe « > », passées telles quelles à sh
// Et, si `launch_history` est activé dans le panneau, les lancements récents
// (core/launch_history.json) affichés à l'ouverture dans le champ vide.
Item {
    id: root

    // Remplit la PanelWindow : c'est la pilule qui se pose en bas au centre.
    property var appIndex: []
    property var aliases: ({})
    property var history: []
    property string query: ""
    property string mode: "apps"    // "apps" | "cmd"
    property var results: []
    property int sel: 0

    readonly property int maxResults: 6
    readonly property int rowHeight: 46
    readonly property bool cmdMode: mode === "cmd"

    // ── index des applications ───────────────────────────────────────────────
    FileView {
        id: indexFile
        path: Quickshell.shellPath("core/app_index.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.appIndex = JSON.parse(text())
            } catch (e) {
                console.warn("spotlight: app_index.json illisible:", e)
                root.appIndex = []
            }
            root.build()
        }
    }

    // ── alias d'applications (partagés avec les raccourcis Hyprland) ─────────
    FileView {
        id: aliasFile
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.aliases = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.aliases = ({})
            }
            root.build()
        }
    }

    // ── historique des lancements ────────────────────────────────────────────
    FileView {
        id: historyFile
        path: Quickshell.shellPath("core/launch_history.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.history = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                root.history = []
            }
            root.build()
        }
    }

    // Rafraîchit l'index à l'ouverture : une application installée pendant la
    // session doit apparaître sans redémarrer le shell.
    Process {
        id: indexProc
        command: ["python3", Quickshell.shellPath("core/app_index.py"), "--quiet"]
        onExited: indexFile.reload()
    }

    // ── construction de la liste ─────────────────────────────────────────────
    function entry(kind, name, exec, icon, tag) {
        return { kind: kind, name: name, exec: exec, icon: icon, tag: tag }
    }

    function build() {
        const q = String(root.query).trim()

        // Mode commande : tout ce qui suit « > » part tel quel dans sh.
        if (q.indexOf(">") === 0) {
            root.mode = "cmd"
            const cmd = q.substring(1).trim()
            root.results = cmd === "" ? [] : [root.entry("cmd", cmd, cmd, "", "commande")]
            root.sel = 0
            return
        }
        root.mode = "apps"

        // Champ vide : les lancements récents, si l'historique est activé.
        if (q === "") {
            root.results = Theme.launchHistory
                    ? root.history.slice(0, root.maxResults).map(h => root.entry(
                          "recent", h.name, h.exec, h.icon || "", "récent"))
                    : []
            root.sel = 0
            return
        }

        const needle = q.toLowerCase()
        const scored = []

        for (const name in root.aliases) {
            const cmd = String(root.aliases[name] || "")
            if (cmd === "") continue
            const low = name.toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 95 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 70 - low.length
            else if (low.indexOf(needle) >= 0) score = 50 - low.length
            if (score >= 0) {
                scored.push({
                    entry: root.entry("alias", name, cmd,
                                      cmd.trim().split(/\s+/)[0], "alias"),
                    score: score,
                })
            }
        }

        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            const low = String(app.name).toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 100 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 60 - low.length
            else if (low.indexOf(needle) >= 0) score = 40 - low.length
            else if (String(app.comment || "").toLowerCase().indexOf(needle) >= 0) score = 10
            if (score >= 0) {
                scored.push({
                    entry: root.entry("app", app.name, app.exec, app.icon || "",
                                      app.category || ""),
                    score: score,
                })
            }
        }

        scored.sort((a, b) => b.score - a.score
                    || a.entry.name.localeCompare(b.entry.name))
        root.results = scored.slice(0, root.maxResults).map(x => x.entry)
        root.sel = 0
    }

    // Souligne la sous-chaîne trouvée (texte enrichi QML : pas de <span style>).
    function markup(name, highlightColor) {
        const q = String(root.query).trim()
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        if (q === "" || q.indexOf(">") === 0) return esc(name)
        const at = name.toLowerCase().indexOf(q.toLowerCase())
        if (at < 0) return esc(name)
        return esc(name.substring(0, at))
             + "<font color=\"" + highlightColor + "\"><u>"
             + esc(name.substring(at, at + q.length))
             + "</u></font>"
             + esc(name.substring(at + q.length))
    }

    // ── actions ──────────────────────────────────────────────────────────────
    function run(entry) {
        if (!entry) return
        // `cd $HOME` : un lanceur démarre dans le dossier personnel, pas dans
        // celui du shell (hérité de Quickshell).
        const shell = entry.kind === "cmd"
                ? "cd \"$HOME\" && " + entry.exec
                : "cd \"$HOME\" && exec " + entry.exec
        Quickshell.execDetached(["setsid", "sh", "-c", shell])
        if (Theme.launchHistory) {
            Quickshell.execDetached(["python3",
                Quickshell.shellPath("core/launch_history.py"),
                "add", entry.name, entry.exec, entry.icon || ""])
        }
        Theme.spotlightVisible = false
    }

    function runSelected() {
        if (root.results.length === 0) return
        root.run(root.results[root.sel])
    }

    function move(delta) {
        if (root.results.length === 0) return
        root.sel = (root.sel + delta + root.results.length) % root.results.length
    }

    function complete() {
        if (root.results.length === 0 || root.cmdMode) return
        searchInput.text = root.results[root.sel].name
        searchInput.cursorPosition = searchInput.text.length
    }

    // ── la pilule ────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        width: 720
        height: field.height
                + (root.results.length > 0 ? list.height + footer.height : 0)
                + (root.results.length === 0 && root.query !== "" ? footer.height + 40 : 0)
        radius: 26
        // Même opacité que les popups (shell_opacity) : la pilule reste une
        // surface du shell, pas un panneau opaque.
        color: Theme.surfaceBg
        border.color: Qt.alpha(Theme.accent, 0.26)
        border.width: 1

        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // Absorbe les clics sur les zones inertes de la pilule (pied, marges) :
        // sans ça, ils traversent jusqu'au fond cliquable et ferment la surface.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: {}
        }

        // ── champ de recherche ───────────────────────────────────────────────
        Item {
            id: field
            width: parent.width
            height: 62

            Icon {
                id: lens
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.cmdMode ? "chevron-right" : "search"
                size: Theme.iconMd
                color: Theme.accent
                opacityLevel: 1
            }

            TextInput {
                id: searchInput
                anchors.left: lens.right
                anchors.leftMargin: 14
                anchors.right: escChip.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.textLg
                font.family: root.cmdMode ? "monospace" : Qt.application.font.family
                selectByMouse: true
                clip: true
                focus: Theme.spotlightVisible

                onTextChanged: {
                    root.query = text
                    root.build()
                }
                onAccepted: root.runSelected()
                Keys.onEscapePressed: {
                    if (text !== "") {
                        text = ""
                        root.build()
                    } else {
                        Theme.spotlightVisible = false
                    }
                }
                Keys.onDownPressed: root.move(1)
                Keys.onUpPressed: root.move(-1)
                Keys.onTabPressed: root.complete()
            }

            Text {
                visible: searchInput.text === ""
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Rechercher une application…   (> pour une commande)"
                color: Qt.alpha(Theme.fg, 0.42)
                font.pixelSize: Theme.textLg
            }

            Rectangle {
                id: escChip
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: escLabel.implicitWidth + 16
                height: 22
                radius: 7
                color: "transparent"
                border.color: Qt.alpha(Theme.fg, 0.14)
                border.width: 1

                Text {
                    id: escLabel
                    anchors.centerIn: parent
                    text: "Échap"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }
            }
        }

        // ── résultats ────────────────────────────────────────────────────────
        Item {
            id: list
            anchors.top: field.bottom
            width: parent.width
            height: resultsCol.height + 12

            Column {
                id: resultsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 2

                Repeater {
                    model: root.results

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: resultsCol.width
                        height: root.rowHeight
                        radius: 13
                        color: root.sel === index ? Theme.accent : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 12

                            // Pastille d'icône : l'icône du thème si elle existe,
                            // sinon l'initiale — ou « > » pour une commande.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 9
                                color: root.sel === index ? Qt.alpha(Theme.bg, 0.18)
                                                          : Qt.alpha(Theme.accent, 0.14)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.kind === "cmd"
                                          ? ">"
                                          : String(modelData.name).charAt(0).toUpperCase()
                                    color: root.sel === index ? Theme.bg : Theme.accent
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: status === Image.Ready
                                    sourceSize.width: 36
                                    sourceSize.height: 36
                                    source: modelData.icon !== ""
                                            ? "image://icon/" + modelData.icon : ""
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28 - 12 - tagText.implicitWidth - 12
                                textFormat: Text.StyledText
                                text: root.markup(modelData.name,
                                                  root.sel === index ? Theme.bg : Theme.accentMuted)
                                color: root.sel === index ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textLg
                                font.family: modelData.kind === "cmd" ? "monospace" : Qt.application.font.family
                                elide: Text.ElideRight
                            }

                            Text {
                                id: tagText
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.tag ? String(modelData.tag).toUpperCase() : ""
                                color: root.sel === index ? Qt.alpha(Theme.bg, 0.75)
                                                          : Qt.alpha(Theme.fg, 0.34)
                                font.pixelSize: Theme.textXs
                                font.letterSpacing: 0.6
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = index
                            onClicked: root.run(modelData)
                        }
                    }
                }
            }
        }

        // ── aucun résultat ───────────────────────────────────────────────────
        Item {
            visible: root.results.length === 0 && root.query !== ""
            anchors.top: field.bottom
            width: parent.width
            height: 40

            Text {
                anchors.centerIn: parent
                text: root.cmdMode
                      ? "Tapez une commande après « > »"
                      : "Aucun résultat pour « " + root.query + " »"
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: Theme.textSm
            }
        }

        // ── pied ─────────────────────────────────────────────────────────────
        Rectangle {
            id: footer
            anchors.top: list.bottom
            anchors.topMargin: root.results.length > 0 ? 0 : 40
            visible: root.results.length > 0
            width: parent.width
            height: 36
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.fg, 0.07)
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "↑ ↓"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text { text: "naviguer"; color: Qt.alpha(Theme.fg, 0.40); font.pixelSize: Theme.textXs }
                }
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Entrée"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text {
                        text: root.cmdMode ? "exécuter" : "lancer"
                        color: Qt.alpha(Theme.fg, 0.40)
                        font.pixelSize: Theme.textXs
                    }
                }
                Row {
                    visible: !root.cmdMode
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Tab"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text { text: "compléter"; color: Qt.alpha(Theme.fg, 0.40); font.pixelSize: Theme.textXs }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: root.cmdMode
                      ? "shell"
                      : root.results.length + (root.results.length > 1 ? " résultats" : " résultat")
                color: Qt.alpha(Theme.fg, 0.28)
                font.pixelSize: Theme.textXs
            }
        }
    }

    // Le panneau vient de s'ouvrir : champ vide, focus clavier, index à jour.
    Connections {
        target: Theme
        function onSpotlightVisibleChanged() {
            if (!Theme.spotlightVisible) return
            searchInput.text = ""
            root.query = ""
            root.mode = "apps"
            root.sel = 0
            indexFile.reload()
            aliasFile.reload()
            historyFile.reload()
            root.build()
            searchInput.forceActiveFocus()
            indexProc.running = true
        }
        // Activer/désactiver l'historique depuis le panneau agit tout de suite.
        function onLaunchHistoryChanged() {
            root.build()
        }
    }

    Component.onCompleted: {
        if (Theme.spotlightVisible) searchInput.forceActiveFocus()
    }
}
