import QtQuick
import Quickshell
import Quickshell.Io

// ════════════════════════════════════════════════════════════════════════════
// PANNEAU CALENDRIER — grille du mois et Nextcloud CalDAV
// ════════════════════════════════════════════════════════════════════════════
// Sorti de island_center.qml : l'applet « calendrier » et le widget « date »
// l'ouvrent (Theme.activePopup = "calendar"), il se dessine sous l'îlot.
// Les identifiants Nextcloud viennent de core/secrets.json, renseignés depuis
// l'onglet Quickshell du panneau de configuration.
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: panneau

    // Item de référence (l'îlot) : la fenêtre se place sous lui.
    // `required` : l'ancre doit exister *avant* la création de la fenêtre,
    // sinon Quickshell ne mappe jamais la surface du popup.
    required property Item ancre
    property bool ouvert: false

    // L'attrapeur de focus de l'îlot a besoin de la *fenêtre*, pas de
    // cet Item : les deux ne sont pas au même niveau d'imbrication.
    readonly property var surface: fenetre

    // Calendar navigation & Nextcloud sync state
    property int monthOffset: 0
    property string selectedDateStr: "" // "YYYY-MM-DD" when user clicks a day
    property var eventsByDay: ({})      // { "YYYY-MM-DD": [ { summary, time, location, all_day }, ... ] }
    property var eventsCacheByMonth: ({}) // { "YYYY-MM": { "YYYY-MM-DD": [...] } } multi-month local cache
    property string syncStatus: "idle"  // "loading" | "ok" | "cached" | "offline" | "error"
    property bool forceRefreshNext: false

    function currentMonthKey(y, m) {
        return String(y) + "-" + String(m).padStart(2, "0")
    }

    function syncEventsForView() {
        const key = currentMonthKey(viewYear, viewMonth)
        if (eventsCacheByMonth && eventsCacheByMonth[key]) {
            eventsByDay = eventsCacheByMonth[key]
            if (syncStatus === "loading") syncStatus = "ok"
        } else {
            eventsByDay = ({})
        }
    }

    // Add Event Form state
    property bool addingEvent: false
    property bool addEventBusy: false
    property string addEventStatus: ""

    // French date localization
    readonly property var monthNamesFr: [
        "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
        "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"
    ]
    readonly property var dayNamesShortFr: ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    readonly property var dayNamesFullFr: ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    property date nowDate: new Date()
    // Le calendrier garde sa propre notion du jour : l'horloge est devenue un
    // applet (autre fichier, autres identifiants) et ne peut plus la lui donner.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: panneau.nowDate = new Date()
    }
    readonly property date viewDate: new Date(nowDate.getFullYear(), nowDate.getMonth() + monthOffset, 1)
    readonly property int viewYear: viewDate.getFullYear()
    readonly property int viewMonth: viewDate.getMonth() + 1 // 1..12

    readonly property string hoverDateText: {
        const d = nowDate
        return dayNamesFullFr[d.getDay()] + " " + d.getDate() + " " + monthNamesFr[d.getMonth()]
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: CALENDAR GRID & DATE HELPERS
    // ────────────────────────────────────────────────────────────────────────
    function formatIsoDate(y, m1, d) {
        const ys = String(y)
        const ms = String(m1).padStart(2, "0")
        const ds = String(d).padStart(2, "0")
        return ys + "-" + ms + "-" + ds
    }

    // Durée de lecture au format m:ss (popup média).
    // 42 cells (6 weeks x 7 days, Monday-first)
    readonly property var calendarCells: {
        const y = viewDate.getFullYear()
        const m = viewDate.getMonth()
        // JS getDay(): 0=Sun..6=Sat -> Monday=0..Sunday=6
        const firstDow = (new Date(y, m, 1).getDay() + 6) % 7
        const ty = nowDate.getFullYear()
        const tm = nowDate.getMonth()
        const td = nowDate.getDate()
        const evMap = panneau.eventsByDay || ({})

        const cells = []
        for (let i = 0; i < 42; i++) {
            const cellDate = new Date(y, m, i - firstDow + 1)
            const cy = cellDate.getFullYear()
            const cm = cellDate.getMonth()
            const cd = cellDate.getDate()
            const dateStr = formatIsoDate(cy, cm + 1, cd)
            const dayEvents = evMap[dateStr] || []

            cells.push({
                dayNum: cd,
                dateStr: dateStr,
                inMonth: (cm === m),
                isToday: (cy === ty && cm === tm && cd === td),
                hasEvents: dayEvents.length > 0,
                eventCount: dayEvents.length
            })
        }
        return cells
    }

    readonly property var selectedDayEvents: {
        if (!selectedDateStr || !eventsByDay) return []
        return eventsByDay[selectedDateStr] || []
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 5: NEXTCLOUD SERVICE INTEGRATION & CALDAV BACKGROUND TASKS
    // ────────────────────────────────────────────────────────────────────────
    // Single in-flight request; a newer request is queued (never kill the process,
    // which would deliver truncated JSON).
    property bool ncQueued: false
    property bool ncQueuedForce: false

    function startMonthFetch(force) {
        const args = [
            "python3",
            Quickshell.shellPath("core/nextcloud_service.py"),
            "month",
            String(viewYear),
            String(viewMonth)
        ]
        if (force) args.push("--force")
        ncProc.command = args
        ncProc.running = true
    }

    function fetchMonthEvents(force) {
        const key = currentMonthKey(viewYear, viewMonth)
        if (!eventsCacheByMonth || !eventsCacheByMonth[key]) {
            syncStatus = "loading"
        }
        forceRefreshNext = Boolean(force)
        if (ncProc.running) {
            ncQueued = true
            ncQueuedForce = ncQueuedForce || Boolean(force)
            return
        }
        startMonthFetch(force)
    }

    onViewYearChanged: {
        syncEventsForView()
        if (panneau.ouvert) fetchMonthEvents(false)
    }
    onViewMonthChanged: {
        syncEventsForView()
        if (panneau.ouvert) fetchMonthEvents(false)
    }
    onSelectedDateStrChanged: {
        addingEvent = false
        addEventStatus = ""
    }
    // L'horloge est un applet : elle ne peut plus remettre `monthOffset` à zéro
    // elle-même (autre fichier, autres identifiants). C'est l'ouverture du
    // calendrier qui ramène au mois courant.
    onOuvertChanged: {
        if (panneau.ouvert) {
            monthOffset = 0
            syncEventsForView()
            fetchMonthEvents(false)
        } else {
            selectedDateStr = ""
            addingEvent = false
            addEventStatus = ""
        }
    }

    // Silent background prefetch on startup: pre-loads current month + next 5 months into cache
    Timer {
        id: bgPrefetchTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            panneau.fetchMonthEvents(false)
        }
    }

    function submitNewEvent(title, startTime, endTime, location) {
        if (addEventProc.running || !selectedDateStr) return
        const t = (title || "").trim()
        if (!t) {
            addEventStatus = "✕ Titre requis"
            return
        }
        addEventBusy = true
        addEventStatus = "Création sur Nextcloud..."
        addEventProc.command = [
            "python3",
            Quickshell.shellPath("core/nextcloud_service.py"),
            "add",
            selectedDateStr,
            t,
            (startTime || "").trim(),
            (endTime || "").trim(),
            (location || "").trim()
        ]
        addEventProc.running = true
    }

    Process {
        id: addEventProc
        stdout: StdioCollector {
            onStreamFinished: {
                panneau.addEventBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.success) {
                        panneau.addEventStatus = "✓ " + (res.message || "Événement ajouté")
                        panneau.addingEvent = false
                        evTitleInput.text = ""
                        evStartInput.text = ""
                        evEndInput.text = ""
                        evLocInput.text = ""
                        panneau.fetchMonthEvents(true)
                    } else {
                        panneau.addEventStatus = "✕ " + (res.message || "Erreur lors de l'ajout")
                    }
                } catch (e) {
                    panneau.addEventStatus = "✕ Erreur de communication"
                }
            }
        }
    }

    Process {
        id: ncProc
        onExited: {
            if (panneau.ncQueued) {
                const force = panneau.ncQueuedForce
                panneau.ncQueued = false
                panneau.ncQueuedForce = false
                panneau.startMonthFetch(force)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (panneau.ncQueued) return // stale: a newer request is queued
                try {
                    const res = JSON.parse(text.trim())
                    panneau.syncStatus = res.status || "ok"

                    // Merge multi-month pre-cached data into local QML memory
                    const updatedCache = Object.assign({}, panneau.eventsCacheByMonth)
                    if (res.months && typeof res.months === "object") {
                        for (const mk in res.months) {
                            updatedCache[mk] = res.months[mk]
                        }
                    }
                    if (res.year && res.month && res.days) {
                        const k = panneau.currentMonthKey(res.year, res.month)
                        updatedCache[k] = res.days
                    }
                    panneau.eventsCacheByMonth = updatedCache

                    // Synchronize currently viewed month
                    const viewKey = panneau.currentMonthKey(panneau.viewYear, panneau.viewMonth)
                    if (updatedCache[viewKey]) {
                        panneau.eventsByDay = updatedCache[viewKey]
                    } else if (res.days) {
                        panneau.eventsByDay = res.days
                    }
                } catch (e) {
                    panneau.syncStatus = "error"
                }
            }
        }
    }


    // ────────────────────────────────────────────────────────────────────────
    // SECTION 8: INTERACTIVE CALENDAR & NEXTCLOUD POPUP WINDOW
    // ────────────────────────────────────────────────────────────────────────
    PopupWindow {
        id: fenetre
        // Fenêtre de l'îlot (pour l'attrapeur de focus) : elle appartient à
        // `ancre`, pas à ce panneau.
        readonly property var parentWin: panneau.ancre ? panneau.ancre.QsWindow.window : null

        anchor.item: panneau.ancre
        anchor.rect.x: (panneau.ancre.width - implicitWidth) / 2
        anchor.rect.y: panneau.ancre.popupY(panneau.ancre)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(panneau.ancre.clampPopupX(panneau.ancre, (panneau.ancre.width - implicitWidth) / 2, implicitWidth), panneau.ancre.popupY(panneau.ancre), anchor.rect.width, anchor.rect.height)
        implicitWidth: 310
        implicitHeight: calMainCol.implicitHeight + 28
        color: "transparent"
        visible: panneau.ouvert
        grabFocus: visible && panneau.addingEvent

        Rectangle {
            id: calContainer
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: calMainCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 10

                // ────────────────────────────────────────────────────────────
                // SUB-SECTION 8.1: MONTH NAVIGATION HEADER
                // ────────────────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 28

                    // Previous month button
                    Rectangle {
                        width: 26
                        height: 26
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: prevMa.containsMouse ? Theme.surfaceVariant : "transparent"
                        border.color: Theme.surfaceVariant
                        border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            glyph: "chevron-left"
                            size: Theme.iconSm
                            color: Theme.fg
                            opacityLevel: 0.8
                        }

                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panneau.selectedDateStr = ""
                                panneau.monthOffset -= 1
                            }
                        }
                    }

                    // Month + Year title (click to reset to current month)
                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: panneau.monthNamesFr[panneau.viewDate.getMonth()] + " " + panneau.viewYear
                            color: titleResetMa.containsMouse ? Theme.accent : Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true

                            MouseArea {
                                id: titleResetMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panneau.selectedDateStr = ""
                                    panneau.monthOffset = 0
                                }
                            }
                        }

                        // Nextcloud sync status / refresh button
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: panneau.syncStatus === "ok"
                                ? "cloud-check"
                                : panneau.syncStatus === "loading" ? "refresh" : "cloud"
                            color: panneau.syncStatus === "ok"
                                ? Theme.success
                                : panneau.syncStatus === "loading"
                                    ? Theme.info
                                    : Theme.warn
                            size: Theme.iconMd
                            opacityLevel: 0.9

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panneau.fetchMonthEvents(true)
                            }
                        }
                    }

                    // Next month button
                    Rectangle {
                        width: 26
                        height: 26
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: nextMa.containsMouse ? Theme.surfaceVariant : "transparent"
                        border.color: Theme.surfaceVariant
                        border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            glyph: "chevron-right"
                            size: Theme.iconSm
                            color: Theme.fg
                            opacityLevel: 0.8
                        }

                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panneau.selectedDateStr = ""
                                panneau.monthOffset += 1
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // SUB-SECTION 8.2: WEEKDAY COLUMN HEADERS (Lun .. Dim)
                // ────────────────────────────────────────────────────────────
                Row {
                    width: parent.width
                    Repeater {
                        model: panneau.dayNamesShortFr
                        Text {
                            required property string modelData
                            width: calMainCol.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Theme.accentMuted
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // SUB-SECTION 8.3: 6x7 DAYS INTERACTIVE GRID
                // ────────────────────────────────────────────────────────────
                Grid {
                    id: daysGrid
                    width: parent.width
                    columns: 7

                    Repeater {
                        model: panneau.calendarCells

                        Item {
                            id: dayCell
                            required property var modelData
                            width: daysGrid.width / 7
                            height: 34

                            readonly property bool isSelected: panneau.selectedDateStr === modelData.dateStr

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Theme.globalRadius
                                color: dayCell.modelData.isToday
                                    ? Theme.accent
                                    : dayCell.isSelected
                                        ? Theme.surfaceVariant
                                        : dayCellMa.containsMouse
                                            ? Qt.alpha(Theme.surfaceVariant, 0.6)
                                            : "transparent"
                                border.color: dayCell.isSelected
                                    ? Theme.accent
                                    : dayCell.modelData.hasEvents
                                        ? Qt.alpha(Theme.accentMuted, 0.5)
                                        : "transparent"
                                border.width: (dayCell.isSelected || dayCell.modelData.hasEvents) ? 1 : 0

                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: dayCell.modelData.hasEvents ? -3 : 0
                                    text: dayCell.modelData.dayNum
                                    color: dayCell.modelData.isToday
                                        ? Theme.bg
                                        : dayCell.modelData.inMonth
                                            ? Theme.fg
                                            : Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: Theme.textSm
                                    font.bold: dayCell.modelData.isToday || dayCell.modelData.hasEvents
                                }

                                // Colored dot for days with Nextcloud events
                                Rectangle {
                                    visible: dayCell.modelData.hasEvents
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: dayCell.modelData.isToday ? Theme.bg : Theme.warn
                                }
                            }

                            MouseArea {
                                id: dayCellMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (panneau.selectedDateStr === dayCell.modelData.dateStr) {
                                        panneau.selectedDateStr = ""
                                    } else {
                                        panneau.selectedDateStr = dayCell.modelData.dateStr
                                    }
                                }
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // SUB-SECTION 8.4: SELECTED DAY AGENDA & NEXTCLOUD EVENTS
                // ────────────────────────────────────────────────────────────
                Column {
                    id: dayDetailsSection
                    visible: panneau.selectedDateStr !== ""
                    width: parent.width
                    spacing: 8

                    // Divider line
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.surfaceVariant
                    }

                    // Selected date header + Add button
                    Item {
                        width: parent.width
                        height: 24

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.space1

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "calendar"
                                size: Theme.iconSm
                                color: Theme.accent
                                opacityLevel: 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: panneau.selectedDateStr
                                color: Theme.accent
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Rectangle {
                                width: 68
                                height: 22
                                radius: Theme.globalRadius
                                color: panneau.addingEvent
                                    ? Theme.accentMuted
                                    : (addEvToggleMa.containsMouse ? Theme.accent : Theme.surfaceVariant)
                                border.color: Theme.accent
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: panneau.addingEvent ? "Annuler" : "+ Ajouter"
                                    color: (panneau.addingEvent || addEvToggleMa.containsMouse) ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    id: addEvToggleMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        panneau.addEventStatus = ""
                                        panneau.addingEvent = !panneau.addingEvent
                                    }
                                }
                            }

                            Rectangle {
                                width: 22
                                height: 22
                                radius: Theme.globalRadius
                                color: closeDayMa.containsMouse ? Theme.surfaceVariant : "transparent"

                                Icon {
                                    anchors.centerIn: parent
                                    glyph: "close"
                                    size: 11
                                    color: Theme.fg
                                    opacityLevel: 1
                                }

                                MouseArea {
                                    id: closeDayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panneau.selectedDateStr = ""
                                }
                            }
                        }
                    }

                    // Status feedback banner (after adding event or error)
                    Rectangle {
                        visible: panneau.addEventStatus !== ""
                        width: parent.width
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant
                        border.color: panneau.addEventStatus.indexOf("✓") === 0
                            ? Theme.success
                            : (panneau.addEventStatus.indexOf("✕") === 0 ? Theme.error : Theme.info)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: panneau.addEventStatus
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                        }
                    }

                    // ────────────────────────────────────────────────────────
                    // SUB-SECTION 8.5: INLINE ADD EVENT FORM (Nextcloud CalDAV)
                    // ────────────────────────────────────────────────────────
                    Rectangle {
                        id: addEventFormBox
                        visible: panneau.addingEvent
                        width: parent.width
                        height: visible ? (addFormCol.implicitHeight + 16) : 0
                        color: Theme.surfaceVariant
                        radius: Theme.globalRadius
                        border.color: Theme.accent
                        border.width: 1
                        clip: true

                        onVisibleChanged: {
                            if (visible) {
                                evTitleInput.forceActiveFocus()
                            }
                        }

                        Column {
                            id: addFormCol
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            spacing: 6

                            // Event Title Input
                            Rectangle {
                                width: parent.width
                                height: 28
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: evTitleInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                Text {
                                    visible: evTitleInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: "Titre de l'événement..."
                                    color: Qt.alpha(Theme.fg, 0.45)
                                    font.pixelSize: Theme.textXs
                                }

                                TextInput {
                                    id: evTitleInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    focus: panneau.addingEvent
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                    clip: true
                                    KeyNavigation.tab: evStartInput
                                    onAccepted: panneau.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: panneau.addingEvent = false
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.NoButton
                                }
                            }

                            // Start / End time row (optional -> empty = all-day)
                            Row {
                                width: parent.width
                                spacing: 6

                                Rectangle {
                                    width: (parent.width - 6) / 2
                                    height: 26
                                    color: Theme.bg
                                    radius: Theme.globalRadius
                                    border.color: evStartInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                    border.width: 1

                                    Text {
                                        visible: evStartInput.text.length === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        text: "Début (ex: 14:00)"
                                        color: Qt.alpha(Theme.fg, 0.45)
                                        font.pixelSize: Theme.textXs
                                    }

                                    TextInput {
                                        id: evStartInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        selectByMouse: true
                                        color: Theme.fg
                                        font.pixelSize: Theme.textXs
                                        clip: true
                                        KeyNavigation.tab: evEndInput
                                        onAccepted: panneau.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                        Keys.onEscapePressed: panneau.addingEvent = false
                                    }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.NoButton
                                }
                            }

                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 26
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: evEndInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                Text {
                                    visible: evEndInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: "Fin (ex: 15:00)"
                                    color: Qt.alpha(Theme.fg, 0.45)
                                    font.pixelSize: Theme.textXs
                                }

                                TextInput {
                                    id: evEndInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                    clip: true
                                    KeyNavigation.tab: evLocInput
                                    onAccepted: panneau.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: panneau.addingEvent = false
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.NoButton
                                }
                            }
                        }

                        // Location + Submit Button Row
                        Row {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                width: parent.width - 78
                                height: 28
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: evLocInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                Text {
                                    visible: evLocInput.text.length === 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    text: "Lieu (optionnel)..."
                                    color: Qt.alpha(Theme.fg, 0.45)
                                    font.pixelSize: Theme.textXs
                                }

                                TextInput {
                                    id: evLocInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                    clip: true
                                    KeyNavigation.tab: evTitleInput
                                    onAccepted: panneau.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: panneau.addingEvent = false
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.NoButton
                                }
                            }

                            Rectangle {
                                width: 72
                                height: 28
                                radius: Theme.globalRadius
                                color: panneau.addEventBusy
                                    ? Theme.surfaceVariant
                                    : (createEvMa.containsMouse ? Theme.accentMuted : Theme.accent)

                                Text {
                                    anchors.centerIn: parent
                                    text: panneau.addEventBusy ? "..." : "Créer"
                                    color: panneau.addEventBusy ? Theme.fg : Theme.bg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    id: createEvMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panneau.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                }
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // SUB-SECTION 8.6: SELECTED DAY EVENTS LIST
                // ────────────────────────────────────────────────────────────
                // Empty state when no events on selected day
                Text {
                    visible: panneau.selectedDayEvents.length === 0
                    width: parent.width
                    text: panneau.syncStatus === "loading"
                        ? "Synchronisation Nextcloud en cours..."
                        : "Aucun événement Nextcloud prévu ce jour."
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Theme.textXs
                    font.italic: true
                }

                // List of Nextcloud events for the selected day
                Repeater {
                    model: panneau.selectedDayEvents

                    Rectangle {
                        required property var modelData
                        width: dayDetailsSection.width
                        height: evCol.implicitHeight + 12
                        color: Theme.surfaceVariant
                        radius: Theme.globalRadius
                        border.color: Theme.accentMuted
                        border.width: 1

                        Column {
                            id: evCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 8
                            spacing: 2

                            Row {
                                spacing: 6
                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.warn
                                }
                                Text {
                                    text: modelData.time || ""
                                    color: Theme.accentMuted
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData.summary || "Événement"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Row {
                                visible: Boolean(modelData.location && modelData.location !== "")
                                width: parent.width
                                spacing: Theme.space1

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "map-marker"
                                    size: 10
                                    color: Qt.alpha(Theme.fg, 0.8)
                                    opacityLevel: 1
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 14
                                    text: modelData.location || ""
                                    color: Qt.alpha(Theme.fg, 0.8)
                                    font.pixelSize: Theme.textXs
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

}
