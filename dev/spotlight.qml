import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ─────────────────────────────────────────────────────────────────────────────
// 9. SPOTLIGHT PILL — launcher bas-centre qui remplace fuzzel
// ─────────────────────────────────────────────────────────────────────────────
// Chargée par la PanelWindow `portable-spotlight` de main.qml, elle-même pilotée
// par Theme.spotlightVisible (IPC `quickshell ipc call portable toggleSpotlight`).
// Les applications viennent de core/app_index.json (core/app_index.py), pas d'un
// parseur .desktop en QML.
Item {
    id: root

    // Remplit la PanelWindow : c'est la pilule qui se pose en bas au centre.
    property var appIndex: []
    property string query: ""
    property var results: []
    property int sel: 0

    readonly property int maxResults: 6
    readonly property int rowHeight: 46

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
            root.filterApps()
        }
    }

    // Rafraîchit l'index à l'ouverture : une application installée pendant la
    // session doit apparaître sans redémarrer le shell.
    Process {
        id: indexProc
        command: ["python3", Quickshell.shellPath("core/app_index.py"), "--quiet"]
        onExited: indexFile.reload()
    }

    // ── filtrage ─────────────────────────────────────────────────────────────
    function filterApps() {
        const q = String(root.query).toLowerCase().trim()
        if (q === "") {
            // Comme la maquette : la pilule reste repliée tant qu'on n'a rien tapé.
            root.results = []
            root.sel = 0
            return
        }

        const scored = []
        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            const name = app.name.toLowerCase()
            let score = -1
            if (name.indexOf(q) === 0) score = 100 - name.length
            else if (name.indexOf(" " + q) >= 0) score = 60 - name.length
            else if (name.indexOf(q) >= 0) score = 40 - name.length
            else if (String(app.comment || "").toLowerCase().indexOf(q) >= 0) score = 10
            if (score >= 0) scored.push({ app: app, score: score })
        }
        scored.sort((a, b) => b.score - a.score || a.app.name.localeCompare(b.app.name))
        root.results = scored.slice(0, root.maxResults).map(x => x.app)
        root.sel = 0
    }

    // Souligne la sous-chaîne trouvée, dans la couleur passée.
    function markup(name, highlightColor) {
        const q = String(root.query).trim()
        if (q === "") return name.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        const at = name.toLowerCase().indexOf(q.toLowerCase())
        if (at < 0) return name.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        const before = name.substring(0, at).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        const hit = name.substring(at, at + q.length).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        const after = name.substring(at + q.length).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        return before + "<font color=\"" + highlightColor + "\"><u>" + hit + "</u></font>" + after
    }

    // ── actions ──────────────────────────────────────────────────────────────
    function launch(entry) {
        if (!entry) return
        // `cd $HOME` : un lanceur démarre dans le dossier personnel, pas dans
        // celui du shell (hérité de Quickshell).
        Quickshell.execDetached(["setsid", "sh", "-c", "cd \"$HOME\" && exec " + entry.exec])
        Theme.spotlightVisible = false
    }

    function launchSelected() {
        if (root.results.length === 0) return
        root.launch(root.results[root.sel])
    }

    function move(delta) {
        if (root.results.length === 0) return
        root.sel = (root.sel + delta + root.results.length) % root.results.length
    }

    function complete() {
        if (root.results.length === 0) return
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
        color: Qt.alpha(Theme.surface, 0.90)
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
                glyph: "search"
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
                selectByMouse: true
                clip: true
                focus: Theme.spotlightVisible

                onTextChanged: {
                    root.query = text
                    root.filterApps()
                }
                onAccepted: root.launchSelected()
                Keys.onEscapePressed: {
                    if (text !== "") {
                        text = ""
                        root.filterApps()
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
                text: "Rechercher une application…"
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
                            // sinon l'initiale de l'application.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 9
                                color: root.sel === index ? Qt.alpha(Theme.bg, 0.18)
                                                          : Qt.alpha(Theme.accent, 0.14)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name.charAt(0).toUpperCase()
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
                                width: parent.width - 28 - 12 - kindLabel.implicitWidth - 12
                                textFormat: Text.StyledText
                                text: root.markup(modelData.name,
                                                  root.sel === index ? Theme.bg : Theme.accentMuted)
                                color: root.sel === index ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textLg
                                elide: Text.ElideRight
                            }

                            Text {
                                id: kindLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.category ? modelData.category.toUpperCase() : ""
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
                            onClicked: root.launch(modelData)
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
                text: "Aucun résultat pour « " + root.query + " »"
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
                    Text { text: "lancer"; color: Qt.alpha(Theme.fg, 0.40); font.pixelSize: Theme.textXs }
                }
                Row {
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
                text: root.results.length + (root.results.length > 1 ? " résultats" : " résultat")
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
            root.sel = 0
            indexFile.reload()
            root.filterApps()
            searchInput.forceActiveFocus()
            indexProc.running = true
        }
    }

    Component.onCompleted: {
        if (Theme.spotlightVisible) searchInput.forceActiveFocus()
    }
}
