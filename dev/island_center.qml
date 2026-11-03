import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris

// ════════════════════════════════════════════════════════════════════════════
// CENTER ISLAND: CLOCK, MEDIA BANNER & NEXTCLOUD CALENDAR (island_center.qml)
// ════════════════════════════════════════════════════════════════════════════
// Features:
//   • Minimal digital clock (HH:MM) with hover expansion to full date
//   • Dynamic MPRIS player preview (shows current track, filters out web browsers)
//   • System configuration panel toggle button (gear icon)
//   • Interactive 6x7 month calendar popup (Monday-first grid)
//   • Full two-way Nextcloud CalDAV integration (fetch events & create new ones)
//   • Event dots, daily agenda cards, and inline event creation form
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandCenter
    implicitWidth: contentRow.implicitWidth + 28
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: POPUP GEOMETRY & SCREEN CLAMPING HELPERS
    // ────────────────────────────────────────────────────────────────────────
    // Keep popups fully inside the bar window (= screen width) with an 8px margin.
    // Vertical offset so that every popup opens 6px under the BAR (island bottom).
    function popupY(item) {
        return islandCenter.height + 6 - islandCenter.mapFromItem(item, 0, 0).y
    }

    function clampPopupX(item, relX, popupW) {
        const win = islandCenter.QsWindow.window
        if (!win) return relX
        const ix = win.contentItem.mapFromItem(item, 0, 0).x
        const absX = Math.max(8, Math.min(win.width - popupW - 8, ix + relX))
        return absX - ix
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: BAR EXPANSION & CALENDAR STATE
    // ────────────────────────────────────────────────────────────────────────
    property bool hovered: false
    property real expandProgress: hovered ? 1.0 : 0.0
    Behavior on expandProgress { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    readonly property bool calendarOpen: Theme.activePopup === "calendar"

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
    readonly property date viewDate: new Date(nowDate.getFullYear(), nowDate.getMonth() + monthOffset, 1)
    readonly property int viewYear: viewDate.getFullYear()
    readonly property int viewMonth: viewDate.getMonth() + 1 // 1..12

    readonly property string hoverDateText: {
        const d = nowDate
        return dayNamesFullFr[d.getDay()] + " " + d.getDate() + " " + monthNamesFr[d.getMonth()]
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: MPRIS MEDIA INTEGRATION
    // ────────────────────────────────────────────────────────────────────────
    // Live tracking of currently playing media (excluding Firefox / Zen / web browsers)
    property bool mediaPollTick: false
    Timer {
        interval: 1000
        running: islandCenter.hovered
        repeat: true
        triggeredOnStart: true
        onTriggered: islandCenter.mediaPollTick = !islandCenter.mediaPollTick
    }

    readonly property var activeMediaInfo: {
        const _ = islandCenter.mediaPollTick
        const __ = islandCenter.hovered
        const list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p) continue
            const ident = (p.identity || p.desktopEntry || p.dbusName || "").toLowerCase()
            // Ignore browsers (Firefox, Zen, Chrome, Chromium, Brave...) to avoid ads and video previews
            if (ident.indexOf("firefox") >= 0 || ident.indexOf("zen") >= 0
                || ident.indexOf("chromium") >= 0 || ident.indexOf("chrome") >= 0
                || ident.indexOf("brave") >= 0) {
                continue
            }
            if (p.isPlaying && p.trackTitle) {
                const title = p.trackTitle.trim()
                const artist = (p.trackArtist || p.trackAlbumArtist || "").trim()
                return {
                    title: title,
                    artist: artist,
                    label: artist ? (artist + " — " + title) : title
                }
            }
        }
        return null
    }

    readonly property string hoverDisplayText: {
        if (activeMediaInfo && activeMediaInfo.label) {
            return "🎵 " + activeMediaInfo.label
        }
        return hoverDateText
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

    // 42 cells (6 weeks x 7 days, Monday-first)
    readonly property var calendarCells: {
        const y = viewDate.getFullYear()
        const m = viewDate.getMonth()
        // JS getDay(): 0=Sun..6=Sat -> Monday=0..Sunday=6
        const firstDow = (new Date(y, m, 1).getDay() + 6) % 7
        const ty = nowDate.getFullYear()
        const tm = nowDate.getMonth()
        const td = nowDate.getDate()
        const evMap = islandCenter.eventsByDay || ({})

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
        if (calendarOpen) fetchMonthEvents(false)
    }
    onViewMonthChanged: {
        syncEventsForView()
        if (calendarOpen) fetchMonthEvents(false)
    }
    onSelectedDateStrChanged: {
        addingEvent = false
        addEventStatus = ""
    }
    onCalendarOpenChanged: {
        if (calendarOpen) {
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
            islandCenter.fetchMonthEvents(false)
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
                islandCenter.addEventBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.success) {
                        islandCenter.addEventStatus = "✓ " + (res.message || "Événement ajouté")
                        islandCenter.addingEvent = false
                        evTitleInput.text = ""
                        evStartInput.text = ""
                        evEndInput.text = ""
                        evLocInput.text = ""
                        islandCenter.fetchMonthEvents(true)
                    } else {
                        islandCenter.addEventStatus = "✕ " + (res.message || "Erreur lors de l'ajout")
                    }
                } catch (e) {
                    islandCenter.addEventStatus = "✕ Erreur de communication"
                }
            }
        }
    }

    Process {
        id: ncProc
        onExited: {
            if (islandCenter.ncQueued) {
                const force = islandCenter.ncQueuedForce
                islandCenter.ncQueued = false
                islandCenter.ncQueuedForce = false
                islandCenter.startMonthFetch(force)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (islandCenter.ncQueued) return // stale: a newer request is queued
                try {
                    const res = JSON.parse(text.trim())
                    islandCenter.syncStatus = res.status || "ok"

                    // Merge multi-month pre-cached data into local QML memory
                    const updatedCache = Object.assign({}, islandCenter.eventsCacheByMonth)
                    if (res.months && typeof res.months === "object") {
                        for (const mk in res.months) {
                            updatedCache[mk] = res.months[mk]
                        }
                    }
                    if (res.year && res.month && res.days) {
                        const k = islandCenter.currentMonthKey(res.year, res.month)
                        updatedCache[k] = res.days
                    }
                    islandCenter.eventsCacheByMonth = updatedCache

                    // Synchronize currently viewed month
                    const viewKey = islandCenter.currentMonthKey(islandCenter.viewYear, islandCenter.viewMonth)
                    if (updatedCache[viewKey]) {
                        islandCenter.eventsByDay = updatedCache[viewKey]
                    } else if (res.days) {
                        islandCenter.eventsByDay = res.days
                    }
                } catch (e) {
                    islandCenter.syncStatus = "error"
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 6: MAIN ISLAND BAR UI
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: background
        anchors.fill: parent
        color: Theme.surfaceBg
        radius: Theme.globalRadius
        border.color: islandCenter.calendarOpen ? Theme.accentMuted : Theme.accent
        border.width: 1
        clip: true

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 0

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 6.1: DIGITAL CLOCK (HH:MM)
            // ────────────────────────────────────────────────────────────────
            Text {
                id: clockText
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: 14
                font.bold: true
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        const n = new Date()
                        clockText.text = Qt.formatDateTime(n, "hh:mm")
                        if (n.toDateString() !== islandCenter.nowDate.toDateString()) {
                            islandCenter.nowDate = n
                        }
                    }
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 6.2: EXPANDABLE DATE / MPRIS TITLE ON HOVER
            // ────────────────────────────────────────────────────────────────
            Item {
                id: dateExpandBox
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                width: Math.round(islandCenter.expandProgress * (dateInnerRow.implicitWidth + 10))
                clip: true

                Row {
                    id: dateInnerRow
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    opacity: Math.max(0.0, Math.min(1.0, (islandCenter.expandProgress - 0.25) / 0.75))

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·"
                        color: Theme.accent
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: Math.min(dateText.implicitWidth, 340)
                        implicitHeight: dateText.implicitHeight
                        width: implicitWidth
                        height: implicitHeight

                        Text {
                            id: dateText
                            anchors.fill: parent
                            text: islandCenter.hoverDisplayText
                            color: islandCenter.activeMediaInfo ? Theme.accent : Theme.accentMuted
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ────────────────────────────────────────────────────────────────
            // SUB-SECTION 6.3: SYSTEM CONFIGURATION PANEL GEAR BUTTON
            // ────────────────────────────────────────────────────────────────
            Row {
                visible: Theme.showConfigButton
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Item { width: 10; height: 1 }

                Rectangle {
                    width: 1
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariant
                }

                Item { width: 10; height: 1 }

                Rectangle {
                    id: gearBtn
                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: Theme.configPanelVisible
                        ? Theme.accent
                        : (gearMa.containsMouse ? Theme.surfaceVariant : "transparent")

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: Theme.configPanelVisible ? Theme.bg : Theme.fg
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: gearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.configPanelVisible = !Theme.configPanelVisible
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // SUB-SECTION 6.4: CLOCK CLICK AREA (Toggles Calendar Popup)
        // ────────────────────────────────────────────────────────────────────
        MouseArea {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: Theme.showConfigButton ? 38 : 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: islandCenter.hovered = true
            onExited: islandCenter.hovered = false
            onClicked: {
                if (!islandCenter.calendarOpen) {
                    islandCenter.monthOffset = 0
                }
                Theme.togglePopup("calendar")
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 7: HYPRLAND OUTSIDE CLICK / FOCUS GRAB
    // ────────────────────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        active: islandCenter.calendarOpen
        windows: [calendarPopup, islandCenter.QsWindow.window]
        onCleared: {
            if (Theme.activePopup === "calendar") {
                Theme.activePopup = ""
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 8: INTERACTIVE CALENDAR & NEXTCLOUD POPUP WINDOW
    // ────────────────────────────────────────────────────────────────────────
    PopupWindow {
        id: calendarPopup
        readonly property var parentWin: islandCenter.QsWindow.window

        anchor.item: islandCenter
        anchor.rect.x: (islandCenter.width - implicitWidth) / 2
        anchor.rect.y: islandCenter.popupY(islandCenter)
        anchor.adjustment: PopupAdjustment.All
        anchor.onAnchoring: anchor.rect = Qt.rect(islandCenter.clampPopupX(islandCenter, (islandCenter.width - implicitWidth) / 2, implicitWidth), islandCenter.popupY(islandCenter), anchor.rect.width, anchor.rect.height)
        implicitWidth: 310
        implicitHeight: calMainCol.implicitHeight + 28
        color: "transparent"
        visible: islandCenter.calendarOpen
        grabFocus: visible && islandCenter.addingEvent

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

                        Text {
                            anchors.centerIn: parent
                            text: "◀"
                            color: Theme.fg
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                islandCenter.selectedDateStr = ""
                                islandCenter.monthOffset -= 1
                            }
                        }
                    }

                    // Month + Year title (click to reset to current month)
                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: islandCenter.monthNamesFr[islandCenter.viewDate.getMonth()] + " " + islandCenter.viewYear
                            color: titleResetMa.containsMouse ? Theme.accent : Theme.fg
                            font.pixelSize: 14
                            font.bold: true

                            MouseArea {
                                id: titleResetMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandCenter.selectedDateStr = ""
                                    islandCenter.monthOffset = 0
                                }
                            }
                        }

                        // Nextcloud sync status / refresh button
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: islandCenter.syncStatus === "loading" ? "⟳" : "☁"
                            color: islandCenter.syncStatus === "ok"
                                ? Theme.success
                                : islandCenter.syncStatus === "loading"
                                    ? Theme.info
                                    : Theme.warn
                            font.pixelSize: 13

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandCenter.fetchMonthEvents(true)
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

                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            color: Theme.fg
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                islandCenter.selectedDateStr = ""
                                islandCenter.monthOffset += 1
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
                        model: islandCenter.dayNamesShortFr
                        Text {
                            required property string modelData
                            width: calMainCol.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Theme.accentMuted
                            font.pixelSize: 11
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
                        model: islandCenter.calendarCells

                        Item {
                            id: dayCell
                            required property var modelData
                            width: daysGrid.width / 7
                            height: 34

                            readonly property bool isSelected: islandCenter.selectedDateStr === modelData.dateStr

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
                                    font.pixelSize: 12
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
                                    if (islandCenter.selectedDateStr === dayCell.modelData.dateStr) {
                                        islandCenter.selectedDateStr = ""
                                    } else {
                                        islandCenter.selectedDateStr = dayCell.modelData.dateStr
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
                    visible: islandCenter.selectedDateStr !== ""
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

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "📅 " + islandCenter.selectedDateStr
                            color: Theme.accent
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Rectangle {
                                width: 68
                                height: 22
                                radius: Theme.globalRadius
                                color: islandCenter.addingEvent
                                    ? Theme.accentMuted
                                    : (addEvToggleMa.containsMouse ? Theme.accent : Theme.surfaceVariant)
                                border.color: Theme.accent
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: islandCenter.addingEvent ? "Annuler" : "+ Ajouter"
                                    color: (islandCenter.addingEvent || addEvToggleMa.containsMouse) ? Theme.bg : Theme.fg
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                MouseArea {
                                    id: addEvToggleMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        islandCenter.addEventStatus = ""
                                        islandCenter.addingEvent = !islandCenter.addingEvent
                                    }
                                }
                            }

                            Rectangle {
                                width: 22
                                height: 22
                                radius: Theme.globalRadius
                                color: closeDayMa.containsMouse ? Theme.surfaceVariant : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.fg
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: closeDayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandCenter.selectedDateStr = ""
                                }
                            }
                        }
                    }

                    // Status feedback banner (after adding event or error)
                    Rectangle {
                        visible: islandCenter.addEventStatus !== ""
                        width: parent.width
                        height: 24
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant
                        border.color: islandCenter.addEventStatus.indexOf("✓") === 0
                            ? Theme.success
                            : (islandCenter.addEventStatus.indexOf("✕") === 0 ? Theme.error : Theme.info)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: islandCenter.addEventStatus
                            color: Theme.fg
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    // ────────────────────────────────────────────────────────
                    // SUB-SECTION 8.5: INLINE ADD EVENT FORM (Nextcloud CalDAV)
                    // ────────────────────────────────────────────────────────
                    Rectangle {
                        id: addEventFormBox
                        visible: islandCenter.addingEvent
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
                                    font.pixelSize: 11
                                }

                                TextInput {
                                    id: evTitleInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    focus: islandCenter.addingEvent
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: 11
                                    clip: true
                                    KeyNavigation.tab: evStartInput
                                    onAccepted: islandCenter.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: islandCenter.addingEvent = false
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
                                        font.pixelSize: 10
                                    }

                                    TextInput {
                                        id: evStartInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        selectByMouse: true
                                        color: Theme.fg
                                        font.pixelSize: 11
                                        clip: true
                                        KeyNavigation.tab: evEndInput
                                        onAccepted: islandCenter.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                        Keys.onEscapePressed: islandCenter.addingEvent = false
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
                                    font.pixelSize: 10
                                }

                                TextInput {
                                    id: evEndInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: 11
                                    clip: true
                                    KeyNavigation.tab: evLocInput
                                    onAccepted: islandCenter.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: islandCenter.addingEvent = false
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
                                    font.pixelSize: 10
                                }

                                TextInput {
                                    id: evLocInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    color: Theme.fg
                                    font.pixelSize: 11
                                    clip: true
                                    KeyNavigation.tab: evTitleInput
                                    onAccepted: islandCenter.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
                                    Keys.onEscapePressed: islandCenter.addingEvent = false
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
                                color: islandCenter.addEventBusy
                                    ? Theme.surfaceVariant
                                    : (createEvMa.containsMouse ? Theme.accentMuted : Theme.accent)

                                Text {
                                    anchors.centerIn: parent
                                    text: islandCenter.addEventBusy ? "..." : "Créer"
                                    color: islandCenter.addEventBusy ? Theme.fg : Theme.bg
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                MouseArea {
                                    id: createEvMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandCenter.submitNewEvent(evTitleInput.text, evStartInput.text, evEndInput.text, evLocInput.text)
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
                    visible: islandCenter.selectedDayEvents.length === 0
                    width: parent.width
                    text: islandCenter.syncStatus === "loading"
                        ? "Synchronisation Nextcloud en cours..."
                        : "Aucun événement Nextcloud prévu ce jour."
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: 11
                    font.italic: true
                }

                // List of Nextcloud events for the selected day
                Repeater {
                    model: islandCenter.selectedDayEvents

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
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            Text {
                                width: parent.width
                                text: modelData.summary || "Événement"
                                color: Theme.fg
                                font.pixelSize: 12
                                font.bold: true
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: Boolean(modelData.location && modelData.location !== "")
                                width: parent.width
                                text: "📍 " + (modelData.location || "")
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.pixelSize: 10
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
