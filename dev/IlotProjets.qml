import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET PROJETS DE L'ÎLOT : KANBAN PLANKA (icône columns-3)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var boardData: ({})
    property var boards: []
    property var lists: []
    property int activeListIndex: 0
    property bool onlyMine: false
    property string expandedCardId: ""
    property string menuCardId: ""
    property string draggingCardId: ""
    property bool loading: false
    property bool showNewBoardBar: false
    readonly property string agentEngine: String(boardData.agent_engine || "hermes")
    readonly property bool workerCronActive: Boolean(boardData.worker_cron)

    readonly property var activeList: (lists.length > 0 && activeListIndex >= 0 && activeListIndex < lists.length)
        ? lists[activeListIndex]
        : null

    readonly property var filteredCards: {
        if (!activeList || !activeList.cards) return []
        if (!onlyMine) return activeList.cards
        let out = []
        for (let i = 0; i < activeList.cards.length; i++) {
            if (activeList.cards[i].isMine) out.push(activeList.cards[i])
        }
        return out
    }

    function refreshBoard() {
        if (!boardProc.running) {
            root.loading = true
            boardProc.command = [Quickshell.shellPath("core/as-core"), "planka", "board"]
            boardProc.running = true
        }
    }

    function runAction(args) {
        actionProc.command = [Quickshell.shellPath("core/as-core"), "planka"].concat(args)
        actionProc.running = true
    }

    function cycleAgentMode() {
        if (!root.activeList) return
        const cur = String(root.activeList.agentMode || "inactif")
        const next = cur === "inactif" ? "autonome" : (cur === "autonome" ? "approbation" : "inactif")
        runAction(["agent_col", String(root.activeList.id), next])
    }

    Component.onCompleted: refreshBoard()

    Process {
        id: boardProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const d = JSON.parse(text.trim())
                    root.boardData = d || ({})
                    root.boards = Array.isArray(d.boards) ? d.boards : []
                    root.lists = Array.isArray(d.lists) ? d.lists : []
                    if (root.activeListIndex >= root.lists.length) {
                        root.activeListIndex = 0
                    }
                } catch (e) {}
            }
        }
        onExited: root.loading = false
    }

    Process {
        id: actionProc
        onExited: root.refreshBoard()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── En-tête : Titre + Filtre + Toggle Agent colonne + Liens ──────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "PROJETS"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                color: "transparent"

                Rectangle {
                    id: boardSwitchPill
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    width: Math.min(parent.width, boardNameLbl.implicitWidth + (root.boards.length > 1 ? 16 : 4))
                    radius: 6
                    color: (root.boards.length > 1 && boardSwitchMa.containsMouse)
                        ? Qt.alpha(Theme.accent, 0.14)
                        : "transparent"

                    Text {
                        id: boardNameLbl
                        anchors.left: parent.left
                        anchors.leftMargin: root.boards.length > 1 ? 6 : 0
                        anchors.right: parent.right
                        anchors.rightMargin: root.boards.length > 1 ? 6 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.boardData.board && root.boardData.board.name)
                            ? ("· " + root.boardData.board.name + (root.boards.length > 1 ? " ⇄" : ""))
                            : (root.boardData.statut === "non_configure" ? "· Non configuré" : "· Hors ligne")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: root.boardData.ok ? Qt.alpha(Theme.fg, 0.78) : Theme.warn
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: boardSwitchMa
                        anchors.fill: parent
                        enabled: root.boards.length > 1
                        hoverEnabled: true
                        cursorShape: root.boards.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.boards.length <= 1) return
                            const curId = root.boardData.board ? String(root.boardData.board.id || "") : ""
                            let idx = 0
                            for (let i = 0; i < root.boards.length; i++) {
                                if (String(root.boards[i].id) === curId) {
                                    idx = (i + 1) % root.boards.length
                                    break
                                }
                            }
                            root.activeListIndex = 0
                            root.runAction(["set_board", String(root.boards[idx].id)])
                        }
                    }
                }
            }

            // Bouton + Nouveau tableau
            Rectangle {
                visible: Boolean(root.boardData.ok && root.boardData.projects && root.boardData.projects.length > 0)
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 7
                color: (root.showNewBoardBar || newBoardBtnMa.containsMouse)
                    ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.07)
                border.width: root.showNewBoardBar ? 1 : 0
                border.color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.bold: true
                    color: root.showNewBoardBar ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: newBoardBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.showNewBoardBar = !root.showNewBoardBar
                        if (root.showNewBoardBar) newBoardInput.forceActiveFocus()
                    }
                }
            }

            // Filtre bascule [Toutes | Mes cartes]
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: filterLbl.implicitWidth + 14
                radius: 7
                color: root.onlyMine ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.07)
                border.width: 1
                border.color: root.onlyMine ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Text {
                    id: filterLbl
                    anchors.centerIn: parent
                    text: root.onlyMine ? "Mes cartes" : "Toutes"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.weight: Font.Bold
                    color: root.onlyMine ? Theme.accent : Theme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.onlyMine = !root.onlyMine
                }
            }

            // Toggle Agent par colonne (Inactif / Autonome / Approbation)
            Rectangle {
                visible: root.activeList !== null
                readonly property string mode: root.activeList ? String(root.activeList.agentMode || "inactif") : "inactif"
                Layout.preferredHeight: 24
                Layout.preferredWidth: agentRow.implicitWidth + 12
                radius: 7
                color: mode === "inactif"
                    ? Qt.alpha(Theme.fg, 0.07)
                    : (mode === "autonome" ? Qt.alpha("#22c55e", 0.20) : Qt.alpha(Theme.accent, 0.22))
                border.width: 1
                border.color: mode === "inactif"
                    ? Qt.alpha(Theme.fg, 0.14)
                    : (mode === "autonome" ? "#22c55e" : Theme.accent)

                Row {
                    id: agentRow
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "robot"
                        size: 13
                        color: parent.parent.mode === "inactif"
                            ? Qt.alpha(Theme.fg, 0.65)
                            : (parent.parent.mode === "autonome" ? "#22c55e" : Theme.accent)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.parent.mode === "inactif"
                            ? "IA off"
                            : (parent.parent.mode === "autonome" ? "IA auto" : "IA approb.")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        font.weight: Font.Bold
                        color: parent.parent.mode === "inactif"
                            ? Qt.alpha(Theme.fg, 0.75)
                            : (parent.parent.mode === "autonome" ? "#22c55e" : Theme.accent)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleAgentMode()
                }
            }

            // Choix moteur IA (Hermes | Agy)
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: engineLbl.implicitWidth + 12
                radius: 7
                color: root.agentEngine === "agy" ? Qt.alpha(Theme.accent, 0.20) : Qt.alpha(Theme.fg, 0.07)
                border.width: 1
                border.color: root.agentEngine === "agy" ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Text {
                    id: engineLbl
                    anchors.centerIn: parent
                    text: root.agentEngine === "agy" ? "Agy" : "Hermes"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                    color: root.agentEngine === "agy" ? Theme.accent : Theme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction(["agent_engine", root.agentEngine === "agy" ? "hermes" : "agy"])
                }
            }

            // Cron surveillance IA (planka-worker.timer, 60s)
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: cronLbl.implicitWidth + 12
                radius: 7
                color: root.workerCronActive ? Qt.alpha("#22c55e", 0.20) : Qt.alpha(Theme.fg, 0.07)
                border.width: 1
                border.color: root.workerCronActive ? "#22c55e" : Qt.alpha(Theme.fg, 0.14)

                Text {
                    id: cronLbl
                    anchors.centerIn: parent
                    text: root.workerCronActive ? "Cron ON" : "Cron OFF"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.bold: true
                    color: root.workerCronActive ? "#22c55e" : Qt.alpha(Theme.fg, 0.7)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction(["worker_cron", "toggle"])
                }
            }

            // Bouton rafraîchir
            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 7
                color: refMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07)

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    color: Theme.fg
                }

                MouseArea {
                    id: refMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshBoard()
                }
            }

            // Bouton ouvrir Planka web
            Rectangle {
                visible: Boolean(root.boardData.board && root.boardData.board.url)
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 7
                color: webMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.07)

                Text {
                    anchors.centerIn: parent
                    text: "↗"
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Theme.accent
                }

                MouseArea {
                    id: webMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["xdg-open", String(root.boardData.board.url)])
                }
            }
        }

        // ── Barre inline de création d'un nouveau tableau ────────────────
        Rectangle {
            visible: root.showNewBoardBar
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: Qt.alpha(Theme.surfaceVariant, 0.42)
            border.width: 1
            border.color: newBoardInput.activeFocus ? Theme.accent : Qt.alpha(Theme.accent, 0.45)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 4
                spacing: 6

                TextInput {
                    id: newBoardInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    clip: true
                    onActiveFocusChanged: Theme.islandNeedsKeyboard = activeFocus
                    Keys.onEscapePressed: {
                        text = ""
                        focus = false
                        Theme.islandNeedsKeyboard = false
                        root.showNewBoardBar = false
                    }
                    onAccepted: newBoardSubmitMa.submit()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        text: "Nom du nouveau tableau… (Entrée)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        visible: !newBoardInput.text && !newBoardInput.activeFocus
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.preferredWidth: newBoardBtnTxt.implicitWidth + 12
                    Layout.preferredHeight: 22
                    radius: 6
                    color: Qt.alpha(Theme.accent, 0.22)
                    Text {
                        id: newBoardBtnTxt
                        anchors.centerIn: parent
                        text: "Créer"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                        color: Theme.accent
                    }
                    MouseArea {
                        id: newBoardSubmitMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function submit() {
                            const nom = newBoardInput.text.trim()
                            const pid = (root.boardData.projects && root.boardData.projects.length > 0)
                                ? String(root.boardData.projects[0].id || "") : ""
                            if (nom !== "" && pid !== "") {
                                root.activeListIndex = 0
                                root.runAction(["creer_board", pid, nom])
                                newBoardInput.text = ""
                                newBoardInput.focus = false
                                Theme.islandNeedsKeyboard = false
                                root.showNewBoardBar = false
                            }
                        }
                        onClicked: submit()
                    }
                }
            }
        }

        // ── Onglets horizontaux des colonnes (cibles de Drop) ────────────
        RowLayout {
            visible: root.lists.length > 0
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.lists
                delegate: Rectangle {
                    id: colTab
                    required property var modelData
                    required property int index
                    readonly property bool sel: root.activeListIndex === index
                    readonly property bool dropHover: colDrop.containsDrag

                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 8
                    color: dropHover
                        ? Qt.alpha(Theme.accent, 0.35)
                        : (sel ? Qt.alpha(Theme.accent, 0.20) : Qt.alpha(Theme.surfaceVariant, 0.32))
                    border.width: (sel || dropHover) ? 1 : 0
                    border.color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        horizontalAlignment: Text.AlignHCenter
                        text: colTab.modelData.name + " (" + (colTab.modelData.cards ? colTab.modelData.cards.length : 0) + ")"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: (colTab.sel || colTab.dropHover) ? Font.Bold : Font.Medium
                        color: colTab.sel ? Theme.accent : Theme.fg
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeListIndex = colTab.index
                    }

                    DropArea {
                        id: colDrop
                        anchors.fill: parent
                        keys: ["planka-card"]
                        onDropped: drop => {
                            if (root.draggingCardId !== "") {
                                root.runAction(["deplacer", root.draggingCardId, String(colTab.modelData.id)])
                                root.draggingCardId = ""
                            }
                        }
                    }
                }
            }
        }

        // ── Champ d'ajout rapide dans la colonne active ──────────────────
        Rectangle {
            visible: root.activeList !== null
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 8
            color: Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: quickInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.10)

            TextInput {
                id: quickInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 32
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                clip: true

                onActiveFocusChanged: Theme.islandNeedsKeyboard = activeFocus
                Keys.onEscapePressed: {
                    text = ""
                    focus = false
                    Theme.islandNeedsKeyboard = false
                }
                onAccepted: {
                    const t = text.trim()
                    if (t !== "" && root.activeList) {
                        root.runAction(["creer", String(root.activeList.id), t])
                        text = ""
                    }
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "+ Ajouter une carte dans « " + (root.activeList ? root.activeList.name : "") + " »… (Entrée)"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    visible: !quickInput.text && !quickInput.activeFocus
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 6
                color: quickInput.text.trim() !== "" ? Qt.alpha(Theme.accent, 0.24) : Qt.alpha(Theme.fg, 0.08)
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.bold: true
                    color: quickInput.text.trim() !== "" ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const t = quickInput.text.trim()
                        if (t !== "" && root.activeList) {
                            root.runAction(["creer", String(root.activeList.id), t])
                            quickInput.text = ""
                        } else {
                            quickInput.forceActiveFocus()
                        }
                    }
                }
            }
        }

        // ── Message si non configuré / hors ligne / colonne vide ─────────
        Rectangle {
            visible: root.lists.length === 0 || root.filteredCards.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 10
            color: Qt.alpha(Theme.surfaceVariant, 0.22)

            Text {
                anchors.centerIn: parent
                width: parent.width - 32
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: {
                    if (root.loading && root.lists.length === 0) return "Chargement du tableau Planka…"
                    if (root.boardData.statut === "non_configure")
                        return "Planka n'est pas encore configuré.\nAjoutez l'URL et votre clé API dans dev/core/secrets.json (section \"planka\")."
                    if (!root.boardData.ok && root.lists.length === 0)
                        return "Serveur Planka inaccessible.\n" + (root.boardData.error || "")
                    if (root.lists.length === 0) return "Aucune colonne dans ce tableau."
                    return root.onlyMine ? "Aucune carte assignée dans cette colonne." : "Aucune carte dans cette colonne."
                }
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.65)
            }

            Rectangle {
                visible: Boolean(root.boardData.ok && root.boardData.board && root.lists.length === 0)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                width: createDefaultColLbl.implicitWidth + 24
                height: 28
                radius: 7
                color: Qt.alpha(Theme.accent, 0.22)
                border.width: 1
                border.color: Theme.accent

                Text {
                    id: createDefaultColLbl
                    anchors.centerIn: parent
                    text: "+ Créer colonne « À faire »"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.bold: true
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const bid = root.boardData.board ? String(root.boardData.board.id || "") : ""
                        if (bid !== "") root.runAction(["creer_liste", bid, "À faire"])
                    }
                }
            }
        }

        // ── Liste des cartes (Drag & Drop + Bouton [➔] + Accordéon) ──────
        ListView {
            id: cardsView
            visible: root.lists.length > 0 && root.filteredCards.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.filteredCards

            delegate: Item {
                id: cardWrapper
                required property var modelData
                required property int index
                readonly property bool isExpanded: root.expandedCardId === String(modelData.id)
                readonly property bool showMenu: root.menuCardId === String(modelData.id)
                readonly property bool hasNextList: root.activeListIndex + 1 < root.lists.length
                readonly property bool hasPrevList: root.activeListIndex > 0

                width: cardsView.width
                height: cardRect.height

                Rectangle {
                    id: cardRect
                    width: parent.width
                    height: cardCol.implicitHeight + 14
                    radius: 9
                    color: cardDrop.containsDrag
                        ? Qt.alpha(Theme.accent, 0.16)
                        : Qt.alpha(Theme.surfaceVariant, 0.40)
                    border.width: (cardWrapper.isExpanded || cardDrop.containsDrag) ? 1 : 0
                    border.color: Theme.accent

                    Drag.active: dragMa.drag.active
                    Drag.keys: ["planka-card"]
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    states: State {
                        when: dragMa.drag.active
                        ParentChange { target: cardRect; parent: root }
                        PropertyChanges { target: cardRect; z: 100; opacity: 0.88 }
                    }

                    // Drop sur une autre carte -> réordonnancement vertical (Option B)
                    DropArea {
                        id: cardDrop
                        anchors.fill: parent
                        keys: ["planka-card"]
                        onDropped: drop => {
                            if (root.draggingCardId !== "" && root.draggingCardId !== String(cardWrapper.modelData.id) && root.activeList) {
                                const targetPos = Number(cardWrapper.modelData.position || 65536) - 1
                                root.runAction(["deplacer", root.draggingCardId, String(root.activeList.id), String(Math.max(1, targetPos))])
                                root.draggingCardId = ""
                            }
                        }
                    }

                    ColumnLayout {
                        id: cardCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 8
                        spacing: 6

                        // Ligne principale de la carte
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            // Poignée de drag & drop
                            Text {
                                text: "⋮⋮"
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                color: Qt.alpha(Theme.fg, 0.45)

                                MouseArea {
                                    id: dragMa
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.OpenHandCursor
                                    drag.target: cardRect
                                    onPressed: root.draggingCardId = String(cardWrapper.modelData.id)
                                    onReleased: {
                                        cardRect.Drag.drop()
                                        cardRect.x = 0
                                        cardRect.y = 0
                                        root.draggingCardId = ""
                                    }
                                }
                            }

                            // Pastille temporelle (vert / orange <24h / rouge <6h)
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: cardWrapper.modelData.urgence === "rouge"
                                    ? "#ef4444"
                                    : (cardWrapper.modelData.urgence === "orange" ? "#f97316" : "#22c55e")
                            }

                            // Titre cliquable (déplie/replie l'accordéon)
                            Text {
                                Layout.fillWidth: true
                                text: cardWrapper.modelData.name
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                font.weight: Font.Medium
                                color: Theme.fg
                                elide: Text.ElideRight

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const cid = String(cardWrapper.modelData.id)
                                        root.expandedCardId = (root.expandedCardId === cid) ? "" : cid
                                    }
                                }
                            }

                            // Badge checklist
                            Rectangle {
                                visible: Number(cardWrapper.modelData.tasksTotal || 0) > 0
                                Layout.preferredHeight: 18
                                Layout.preferredWidth: chkLbl.implicitWidth + 10
                                radius: 5
                                color: Qt.alpha(Theme.fg, 0.08)

                                Text {
                                    id: chkLbl
                                    anchors.centerIn: parent
                                    text: "☑ " + cardWrapper.modelData.tasksDone + "/" + cardWrapper.modelData.tasksTotal
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    color: Qt.alpha(Theme.fg, 0.8)
                                }
                            }

                            // Bouton avancement rapide [➔]
                            Rectangle {
                                visible: cardWrapper.hasNextList
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 22
                                radius: 6
                                color: advMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.18)

                                Text {
                                    anchors.centerIn: parent
                                    text: "➔"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    color: advMa.containsMouse ? Theme.bg : Theme.accent
                                }

                                MouseArea {
                                    id: advMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const nextLst = root.lists[root.activeListIndex + 1]
                                        if (nextLst) {
                                            root.runAction(["deplacer", String(cardWrapper.modelData.id), String(nextLst.id)])
                                        }
                                    }
                                }
                            }

                            // Bouton menu contextuel [⋮]
                            Rectangle {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 22
                                radius: 6
                                color: menuMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "⋮"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    color: Qt.alpha(Theme.fg, 0.75)
                                }

                                MouseArea {
                                    id: menuMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const cid = String(cardWrapper.modelData.id)
                                        root.menuCardId = (root.menuCardId === cid) ? "" : cid
                                    }
                                }
                            }
                        }

                        // Barre d'options rapides (si [⋮] ouvert)
                        RowLayout {
                            visible: cardWrapper.showMenu
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                visible: cardWrapper.hasPrevList
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: prevColLbl.implicitWidth + 12
                                radius: 6
                                color: Qt.alpha(Theme.fg, 0.08)

                                Text {
                                    id: prevColLbl
                                    anchors.centerIn: parent
                                    text: "← Reculer"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    color: Theme.fg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const prevLst = root.lists[root.activeListIndex - 1]
                                        if (prevLst) {
                                            root.menuCardId = ""
                                            root.runAction(["deplacer", String(cardWrapper.modelData.id), String(prevLst.id)])
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: openCardLbl.implicitWidth + 12
                                radius: 6
                                color: Qt.alpha(Theme.accent, 0.16)

                                Text {
                                    id: openCardLbl
                                    anchors.centerIn: parent
                                    text: "Ouvrir ↗"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    color: Theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.menuCardId = ""
                                        Quickshell.execDetached(["xdg-open", String(cardWrapper.modelData.url)])
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: delCardLbl.implicitWidth + 12
                                radius: 6
                                color: Qt.alpha(Theme.error, 0.18)

                                Text {
                                    id: delCardLbl
                                    anchors.centerIn: parent
                                    text: "Supprimer"
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    color: Theme.error
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.menuCardId = ""
                                        root.runAction(["supprimer", String(cardWrapper.modelData.id)])
                                    }
                                }
                            }
                        }

                        // Accordéon intérieur (description + checklists interactives)
                        ColumnLayout {
                            visible: cardWrapper.isExpanded
                            Layout.fillWidth: true
                            spacing: 5

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.alpha(Theme.fg, 0.08)
                            }

                            Text {
                                visible: String(cardWrapper.modelData.description || "") !== ""
                                Layout.fillWidth: true
                                text: String(cardWrapper.modelData.description || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                color: Qt.alpha(Theme.fg, 0.78)
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: cardWrapper.modelData.tasks || []
                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: chkTaskRow.implicitHeight

                                    RowLayout {
                                        id: chkTaskRow
                                        anchors.fill: parent
                                        spacing: 6

                                        Text {
                                            text: modelData.isCompleted ? "☑" : "☐"
                                            font.family: Theme.fontUi
                                            font.pixelSize: 12
                                            color: modelData.isCompleted ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            font.family: Theme.fontUi
                                            font.pixelSize: Theme.text2xs
                                            font.strikeout: Boolean(modelData.isCompleted)
                                            color: modelData.isCompleted ? Qt.alpha(Theme.fg, 0.5) : Theme.fg
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction([
                                            "toggle_checklist",
                                            String(modelData.id),
                                            modelData.isCompleted ? "false" : "true"
                                        ])
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
