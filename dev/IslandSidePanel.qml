import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// PANNEAU LATÉRAL DE L'ÎLOT (IslandSidePanel.qml) — 340 × 420 px
// ══════════════════════════════════════════════════════════════════════
// Déployé à droite du panneau principal pour :
// - "todo-add" : création rapide d'une tâche dans todo_applet.py
// - "calendar" : calendrier mensuel + événements Nextcloud CalDAV
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    readonly property string mode: Theme.islandSidePanel
    readonly property bool ouvert: Theme.islandPanelOpen && mode !== ""

    // ── État ajout de tâche ───────────────────────────────────────────────
    property var todoFiles: []
    property string selectedTodoFile: ""
    property bool todoBusy: false
    property string todoStatus: ""
    property bool newFileOpen: false
    property string newFileDir: Quickshell.env("HOME") || "/home"

    function defaultNewFileDir() {
        const cur = root.todoFiles.find(f => String(f.nom || "") === root.selectedTodoFile) || root.todoFiles[0]
        if (cur && cur.chemin) {
            const p = String(cur.chemin)
            const idx = p.lastIndexOf("/")
            if (idx > 0) return p.substring(0, idx)
        }
        return Quickshell.env("HOME") || "/home"
    }

    function createNewTodoFile() {
        const nom = newFileNameInput.text.trim()
        if (nom === "" || todoCreateFileProc.running) {
            if (nom === "") root.todoStatus = "Nom du fichier requis"
            return
        }
        root.todoBusy = true
        root.todoStatus = ""
        todoCreateFileProc.command = [
            "python3", Quickshell.shellPath("core/todo_applet.py"),
            "creer_fichier", nom, root.newFileDir
        ]
        todoCreateFileProc.running = true
    }

    // ── État calendrier ───────────────────────────────────────────────────
    property int monthOffset: 0
    property string selectedDateStr: ""
    property var eventsByDay: ({})
    property bool calLoading: false
    property date nowDate: new Date()

    readonly property var monthNamesFr: [
        "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
        "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"
    ]
    readonly property var dayNamesShortFr: ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    readonly property date viewDate: new Date(nowDate.getFullYear(), nowDate.getMonth() + monthOffset, 1)
    readonly property int viewYear: viewDate.getFullYear()
    readonly property int viewMonth: viewDate.getMonth() + 1

    function formatIsoDate(y, m1, d) {
        return String(y) + "-" + String(m1).padStart(2, "0") + "-" + String(d).padStart(2, "0")
    }

    readonly property string todayStr: formatIsoDate(nowDate.getFullYear(), nowDate.getMonth() + 1, nowDate.getDate())

    readonly property var calendarCells: {
        const y = viewDate.getFullYear()
        const m = viewDate.getMonth()
        const firstDow = (new Date(y, m, 1).getDay() + 6) % 7
        const daysInMonth = new Date(y, m + 1, 0).getDate()
        const daysPrev = new Date(y, m, 0).getDate()
        const cells = []
        for (let i = 0; i < 42; i++) {
            let cy = y, cm = m + 1, cd = 1, cur = false
            if (i < firstDow) {
                cd = daysPrev - firstDow + i + 1
                cm = m === 0 ? 12 : m
                cy = m === 0 ? y - 1 : y
            } else if (i < firstDow + daysInMonth) {
                cd = i - firstDow + 1
                cur = true
            } else {
                cd = i - (firstDow + daysInMonth) + 1
                cm = m === 11 ? 1 : m + 2
                cy = m === 11 ? y + 1 : y
            }
            const ds = formatIsoDate(cy, cm, cd)
            cells.push({
                day: cd,
                dateStr: ds,
                currentMonth: cur,
                isToday: ds === root.todayStr
            })
        }
        return cells
    }

    readonly property var selectedEvents: {
        const key = root.selectedDateStr !== "" ? root.selectedDateStr : root.todayStr
        const ev = root.eventsByDay ? root.eventsByDay[key] : null
        return Array.isArray(ev) ? ev : []
    }

    function fermer() {
        Theme.islandNeedsKeyboard = false
        Theme.islandSidePanel = ""
    }

    function fetchMonth() {
        if (calProc.running) calProc.running = false
        calLoading = true
        calProc.command = [
            "python3", Quickshell.shellPath("core/nextcloud_service.py"),
            "month", String(root.viewYear), String(root.viewMonth)
        ]
        calProc.running = true
    }

    function submitTodo() {
        const titre = todoTitleInput.text.trim()
        if (titre === "" || todoAddProc.running) {
            if (titre === "") root.todoStatus = "Titre requis"
            return
        }
        root.todoBusy = true
        root.todoStatus = ""
        const args = [
            "python3", Quickshell.shellPath("core/todo_applet.py"),
            "ajouter", titre, todoDetailInput.text.trim()
        ]
        if (root.selectedTodoFile !== "") args.push(root.selectedTodoFile)
        todoAddProc.command = args
        todoAddProc.running = true
    }

    onModeChanged: {
        if (mode === "todo-add") {
            todoTitleInput.text = ""
            todoDetailInput.text = ""
            newFileNameInput.text = ""
            newFileOpen = false
            todoStatus = ""
            if (!todoFilesProc.running) todoFilesProc.running = true
            focusTimer.restart()
        } else if (mode === "calendar") {
            Theme.islandNeedsKeyboard = false
            monthOffset = 0
            selectedDateStr = todayStr
            fetchMonth()
        } else {
            Theme.islandNeedsKeyboard = false
        }
    }

    Timer {
        id: focusTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (root.mode === "todo-add" && Theme.islandPanelOpen) {
                todoTitleInput.forceActiveFocus()
            }
        }
    }

    Process {
        id: todoFilesProc
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"), "fichiers"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text.trim())
                    root.todoFiles = Array.isArray(arr) ? arr : []
                    if (root.todoFiles.length > 0 && root.selectedTodoFile === "") {
                        const foc = root.todoFiles.find(f => f.focus)
                        root.selectedTodoFile = foc ? String(foc.nom || "") : String(root.todoFiles[0].nom || "")
                    }
                } catch (e) {
                    root.todoFiles = []
                }
            }
        }
    }

    Process {
        id: todoCreateFileProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.todoBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.ok) {
                        if (Array.isArray(res.fichiers)) root.todoFiles = res.fichiers
                        if (res.nom) root.selectedTodoFile = String(res.nom)
                        newFileNameInput.text = ""
                        root.newFileOpen = false
                        root.todoStatus = ""
                        Theme.todoRev += 1
                    } else {
                        root.todoStatus = String(res.message || "Erreur")
                    }
                } catch (e) {
                    root.todoStatus = "Réponse illisible"
                }
            }
        }
        onExited: code => {
            root.todoBusy = false
            if (code !== 0 && root.todoStatus === "") root.todoStatus = "Échec de création"
        }
    }

    SelecteurDossier {
        id: dossierSelector
        titre: "Dossier du fichier de tâches"
        chemin: root.newFileDir
        onAccepte: c => {
            if (c && c !== "") root.newFileDir = c
        }
    }

    Process {
        id: todoAddProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.todoBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.ok) {
                        Theme.todoRev += 1
                        todoTitleInput.text = ""
                        todoDetailInput.text = ""
                        root.fermer()
                    } else {
                        root.todoStatus = String(res.message || "Erreur")
                    }
                } catch (e) {
                    root.todoStatus = "Réponse illisible"
                }
            }
        }
        onExited: code => {
            root.todoBusy = false
            if (code !== 0 && root.todoStatus === "") root.todoStatus = "Échec d'ajout"
        }
    }

    Process {
        id: calProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.calLoading = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res && res.days) root.eventsByDay = res.days
                    else if (res && res.events) root.eventsByDay = res.events
                    else if (res && typeof res === "object" && !res.error) root.eventsByDay = res
                    else root.eventsByDay = ({})
                } catch (e) {
                    root.eventsByDay = ({})
                }
            }
        }
        onExited: root.calLoading = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── En-tête aligné sur l'en-tête du panneau principal ────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.barHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 8

                Icon {
                    glyph: root.mode === "calendar" ? "calendar" : "widgets"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: root.mode === "calendar" ? "Agenda" : "Nouvelle tâche"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 7
                    color: closeSideMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: Theme.textSm
                        font.weight: Font.Bold
                        color: closeSideMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.75)
                    }

                    MouseArea {
                        id: closeSideMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fermer()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.12)
        }

        // ── Contenu : Création de tâche ──────────────────────────────────
        ColumnLayout {
            visible: root.mode === "todo-add"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 14
            spacing: 10

            Text {
                text: "TITRE"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                radius: 8
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.width: 1
                border.color: todoTitleInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                TextInput {
                    id: todoTitleInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    clip: true
                    onActiveFocusChanged: Theme.islandNeedsKeyboard = activeFocus || todoDetailInput.activeFocus
                    Keys.onReturnPressed: root.submitTodo()
                    Keys.onEnterPressed: root.submitTodo()
                    Keys.onEscapePressed: root.fermer()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Titre de la tâche..."
                        color: Qt.alpha(Theme.fg, 0.38)
                        font: todoTitleInput.font
                        visible: todoTitleInput.text.length === 0
                    }
                }
            }

            Text {
                text: "DÉTAILS (OPTIONNEL)"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 74
                radius: 8
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.width: 1
                border.color: todoDetailInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                TextEdit {
                    id: todoDetailInput
                    anchors.fill: parent
                    anchors.margins: 10
                    color: Theme.fg
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    wrapMode: TextEdit.Wrap
                    clip: true
                    onActiveFocusChanged: Theme.islandNeedsKeyboard = activeFocus || todoTitleInput.activeFocus
                    Keys.onEscapePressed: root.fermer()

                    Text {
                        anchors.fill: parent
                        text: "Précisions ou sous-tâche..."
                        color: Qt.alpha(Theme.fg, 0.38)
                        font: todoDetailInput.font
                        visible: todoDetailInput.text.length === 0
                    }
                }
            }

            ColumnLayout {
                visible: root.todoFiles.length > 0 || root.newFileOpen
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "FICHIER CIBLE"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    font.weight: Font.Bold
                    color: Qt.alpha(Theme.fg, 0.65)
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 6

                    Repeater {
                        model: root.todoFiles
                        delegate: Rectangle {
                            required property var modelData
                            readonly property string nom: String(modelData.nom || "")
                            readonly property bool actif: root.selectedTodoFile === nom
                            height: 24
                            width: fileLbl.implicitWidth + 16
                            radius: 7
                            color: actif ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.4)
                            border.width: 1
                            border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.12)

                            Text {
                                id: fileLbl
                                anchors.centerIn: parent
                                text: nom
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                color: actif ? Theme.accent : Theme.fg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedTodoFile = nom
                            }
                        }
                    }

                    Rectangle {
                        height: 24
                        width: newFileBtnLbl.implicitWidth + 14
                        radius: 7
                        color: root.newFileOpen ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.3)
                        border.width: 1
                        border.color: root.newFileOpen ? Theme.accent : Qt.alpha(Theme.fg, 0.22)

                        Text {
                            id: newFileBtnLbl
                            anchors.centerIn: parent
                            text: root.newFileOpen ? "✕ Nouveau" : "+ Nouveau"
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            font.weight: Font.Medium
                            color: root.newFileOpen ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.newFileOpen = !root.newFileOpen
                                if (root.newFileOpen) {
                                    root.newFileDir = root.defaultNewFileDir()
                                    newFileNameInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // Création rapide d'un nouveau fichier Markdown + sélecteur de dossier
                Rectangle {
                    visible: root.newFileOpen
                    Layout.fillWidth: true
                    Layout.preferredHeight: newFileCol.implicitHeight + 16
                    radius: 8
                    color: Qt.alpha(Theme.surfaceVariant, 0.28)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, 0.35)

                    ColumnLayout {
                        id: newFileCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: Qt.alpha(Theme.bg, 0.5)
                                border.width: 1
                                border.color: newFileNameInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                                TextInput {
                                    id: newFileNameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.fg
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    clip: true
                                    onActiveFocusChanged: Theme.islandNeedsKeyboard = activeFocus || todoTitleInput.activeFocus || todoDetailInput.activeFocus
                                    Keys.onReturnPressed: root.createNewTodoFile()
                                    Keys.onEnterPressed: root.createNewTodoFile()
                                    Keys.onEscapePressed: root.newFileOpen = false

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "nom-fichier.md"
                                        color: Qt.alpha(Theme.fg, 0.38)
                                        font: newFileNameInput.font
                                        visible: newFileNameInput.text.length === 0
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: createFileLbl.implicitWidth + 14
                                Layout.preferredHeight: 28
                                radius: 6
                                color: Theme.accent
                                opacity: root.todoBusy ? 0.5 : 1.0

                                Text {
                                    id: createFileLbl
                                    anchors.centerIn: parent
                                    text: "Créer"
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    font.weight: Font.Bold
                                    color: Theme.bg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.todoBusy
                                    onClicked: root.createNewTodoFile()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: root.newFileDir
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                color: Qt.alpha(Theme.fg, 0.7)
                                elide: Text.ElideMiddle
                            }

                            Rectangle {
                                Layout.preferredWidth: pickDirLbl.implicitWidth + 12
                                Layout.preferredHeight: 24
                                radius: 6
                                color: Qt.alpha(Theme.surfaceVariant, 0.55)
                                border.width: 1
                                border.color: Qt.alpha(Theme.fg, 0.16)

                                Text {
                                    id: pickDirLbl
                                    anchors.centerIn: parent
                                    text: "Dossier…"
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    color: Theme.fg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        dossierSelector.chemin = root.newFileDir
                                        dossierSelector.ouvert = true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.todoStatus !== ""
                text: root.todoStatus
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Theme.error
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: cancelMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.7) : Qt.alpha(Theme.surfaceVariant, 0.45)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: "Annuler"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Theme.fg
                    }

                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fermer()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 8
                    color: addMa.containsMouse ? Theme.accent : Qt.alpha(Theme.accent, 0.85)
                    opacity: root.todoBusy ? 0.6 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: root.todoBusy ? "Ajout..." : "Ajouter"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Bold
                        color: Theme.bg
                    }

                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submitTodo()
                    }
                }
            }
        }

        // ── Contenu : Calendrier mensuel & événements ────────────────────
        ColumnLayout {
            visible: root.mode === "calendar"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            spacing: 8

            // Barre mois + navigation
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 24
                    radius: 6
                    color: prevMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.7) : Qt.alpha(Theme.surfaceVariant, 0.35)
                    Text { anchors.centerIn: parent; text: "‹"; color: Theme.fg; font.pixelSize: Theme.textMd }
                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.monthOffset -= 1; root.fetchMonth() }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.monthNamesFr[root.viewMonth - 1] + " " + root.viewYear
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                Rectangle {
                    visible: root.monthOffset !== 0
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: todayLbl.implicitWidth + 12
                    radius: 6
                    color: todayMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.4)
                    Text {
                        id: todayLbl
                        anchors.centerIn: parent
                        text: "Auj."
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        color: Theme.accent
                    }
                    MouseArea {
                        id: todayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.monthOffset = 0
                            root.selectedDateStr = root.todayStr
                            root.fetchMonth()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 24
                    radius: 6
                    color: nextMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.7) : Qt.alpha(Theme.surfaceVariant, 0.35)
                    Text { anchors.centerIn: parent; text: "›"; color: Theme.fg; font.pixelSize: Theme.textMd }
                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.monthOffset += 1; root.fetchMonth() }
                    }
                }
            }

            // En-têtes jours
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 2

                Repeater {
                    model: root.dayNamesShortFr
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Qt.alpha(Theme.fg, 0.55)
                    }
                }
            }

            // Grille 6x7
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 2
                rowSpacing: 2

                Repeater {
                    model: root.calendarCells
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isSel: root.selectedDateStr === modelData.dateStr
                        readonly property bool hasEv: Boolean(root.eventsByDay && root.eventsByDay[modelData.dateStr] && root.eventsByDay[modelData.dateStr].length > 0)
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        radius: 6
                        color: modelData.isToday ? Theme.accent
                             : (isSel ? Qt.alpha(Theme.accent, 0.25)
                             : (dayMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.6) : "transparent"))
                        border.width: isSel && !modelData.isToday ? 1 : 0
                        border.color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: hasEv ? -2 : 0
                            text: String(modelData.day)
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: modelData.isToday ? Font.Bold : Font.Normal
                            color: modelData.isToday ? Theme.bg
                                 : (modelData.currentMonth ? Theme.fg : Qt.alpha(Theme.fg, 0.30))
                        }

                        Rectangle {
                            visible: hasEv
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            width: 4
                            height: 4
                            radius: 2
                            color: modelData.isToday ? Theme.bg : Theme.accent
                        }

                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedDateStr = modelData.dateStr
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(Theme.fg, 0.1)
            }

            // Liste des événements du jour sélectionné
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: evCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: evCol
                    width: parent.width
                    spacing: 4

                    Text {
                        visible: root.selectedEvents.length === 0
                        text: root.calLoading ? "Synchronisation..." : "Aucun événement ce jour"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Qt.alpha(Theme.fg, 0.55)
                    }

                    Repeater {
                        model: root.selectedEvents
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: evRow.implicitHeight + 8
                            radius: 6
                            color: Qt.alpha(Theme.surfaceVariant, 0.35)

                            RowLayout {
                                id: evRow
                                anchors.fill: parent
                                anchors.margins: 4
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    visible: Boolean(modelData.time)
                                    text: String(modelData.time || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Theme.accent
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.summary || "")
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textXs
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
