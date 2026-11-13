import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

// ══════════════════════════════════════════════════════════════════════
// ONGLET 3 DE L'ÎLOT : ALERTES & TÂCHES (icône bell)
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var todoItems: []
    property int todoOpenCount: 0
    property bool todoSurveillance: false
    property var upcomingEvents: []
    property var _curMonthDays: ({})

    function refreshTasks() {
        if (!todoProc.running) {
            todoProc.command = ["python3", Quickshell.shellPath("core/todo_applet.py")]
            todoProc.running = true
        }
        if (!calProc.running) {
            let now = new Date()
            calProc.command = [
                "python3", Quickshell.shellPath("core/nextcloud_service.py"),
                "month", String(now.getFullYear()), String(now.getMonth() + 1)
            ]
            calProc.running = true
        }
    }

    Component.onCompleted: refreshTasks()

    Connections {
        target: Theme
        function onTodoRevChanged() {
            if (!todoProc.running) {
                todoProc.command = ["python3", Quickshell.shellPath("core/todo_applet.py")]
                todoProc.running = true
            }
        }
    }

    Process {
        id: todoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    root.todoSurveillance = Boolean(d.surveillance)
                    let items = d.taches || d.items || []
                    let open = []
                    for (let i = 0; i < items.length; i++) {
                        if (!items[i].fait && !items[i].done) open.push(items[i])
                    }
                    root.todoOpenCount = open.length
                    root.todoItems = open.slice(0, Theme.notifCount === 0 ? 5 : 3)
                } catch (e) {
                    root.todoItems = []
                }
            }
        }
    }

    Process {
        id: todoActionProc
        onExited: root.refreshTasks()
    }

    function collecterProchainsEvenements(daysA, daysB, isoToday, maxCount) {
        let merged = []
        let sources = [daysA || ({}), daysB || ({})]
        let seen = ({})
        for (let s = 0; s < sources.length; s++) {
            let map = sources[s]
            let keys = Object.keys(map).sort()
            for (let i = 0; i < keys.length; i++) {
                let k = keys[i]
                if (k < isoToday) continue
                let arr = map[k] || []
                for (let j = 0; j < arr.length; j++) {
                    let ev = arr[j]
                    let summary = String(ev.summary || "Événement")
                    let dedup = k + "|" + summary + "|" + String(ev.time || "")
                    if (seen[dedup]) continue
                    seen[dedup] = true
                    let dateLabel = k
                    if (k === isoToday) {
                        dateLabel = "Aujourd'hui"
                    } else {
                        let parts = k.split("-")
                        if (parts.length === 3) {
                            let dt = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
                            dateLabel = Qt.formatDate(dt, "ddd d MMM")
                        }
                    }
                    merged.push({
                        sortKey: k + " " + String(ev.sort_key || "00:00"),
                        dateLabel: dateLabel,
                        summary: summary
                    })
                }
            }
        }
        merged.sort((a, b) => a.sortKey < b.sortKey ? -1 : (a.sortKey > b.sortKey ? 1 : 0))
        return merged.slice(0, maxCount || 3)
    }

    Process {
        id: calProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    let daysMap = d.days || d.events || ({})
                    root._curMonthDays = daysMap
                    let now = new Date()
                    let iso = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
                    let list = root.collecterProchainsEvenements(daysMap, null, iso, 3)
                    root.upcomingEvents = list
                    if (list.length < 3 && !calNextProc.running) {
                        let nm = now.getMonth() + 2
                        let ny = now.getFullYear()
                        if (nm > 12) { nm = 1; ny += 1 }
                        calNextProc.command = [
                            "python3", Quickshell.shellPath("core/nextcloud_service.py"),
                            "month", String(ny), String(nm)
                        ]
                        calNextProc.running = true
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: calNextProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    let nextMap = d.days || d.events || ({})
                    let now = new Date()
                    let iso = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
                    root.upcomingEvents = root.collecterProchainsEvenements(root._curMonthDays, nextMap, iso, 3)
                } catch (e) {}
            }
        }
    }

    Process {
        id: dndBridge
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // En-tête + boutons N.P.D. et Tout effacer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "ALERTES & TÂCHES"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textMd
                font.weight: Font.Bold
                color: Theme.fg
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: dndLbl.implicitWidth + 14
                radius: 7
                color: Theme.doNotDisturb ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)
                border.width: 1
                border.color: Theme.doNotDisturb ? Theme.accent : "transparent"

                Row {
                    id: dndLbl
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Theme.doNotDisturb ? "bell-off" : "bell"
                        size: 12
                        color: Theme.doNotDisturb ? Theme.accent : Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.doNotDisturb ? "N.P.D. ON" : "N.P.D."
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Theme.doNotDisturb ? Theme.accent : Theme.fg
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Theme.doNotDisturb = !Theme.doNotDisturb
                        dndBridge.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                                             "style", "do_not_disturb", Theme.doNotDisturb ? "true" : "false"]
                        dndBridge.running = true
                    }
                }
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: clearLbl.implicitWidth + 14
                radius: 7
                color: Theme.notifCount > 0 ? Qt.alpha(Theme.error, 0.18) : Qt.alpha(Theme.fg, 0.05)
                opacity: Theme.notifCount > 0 ? 1.0 : 0.45

                Text {
                    id: clearLbl
                    anchors.centerIn: parent
                    text: "Tout effacer"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.notifCount > 0 ? Theme.error : Theme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: Theme.notifCount > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Theme.notifOps && Theme.notifOps.clear) Theme.notifOps.clear()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // Sous-titre Notifications + Historique
        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "NOTIFICATIONS ACTIVES (" + Theme.notifCount + ")"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            Text {
                text: "Historique ↗"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: histMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                MouseArea {
                    id: histMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Theme.islandPanelOpen = false
                        Theme.notifHistoryVisible = true
                    }
                }
            }
        }

        // Liste Notifications
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.notifCount === 0 ? 40 : 126
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.25)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.07)

            Text {
                visible: Theme.notifCount === 0
                anchors.centerIn: parent
                text: "Aucune notification récente"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.55)
            }

            Flickable {
                visible: Theme.notifCount > 0
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: notifCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: notifCol
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Theme.notifList || []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 8
                            color: nMa.containsMouse ? Qt.alpha(Theme.accent, 0.14) : Qt.alpha(Theme.surfaceVariant, 0.45)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.appName || "Notification") + (modelData.summary ? (" · " + modelData.summary) : "")
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.textXs
                                        font.weight: Font.DemiBold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.body || ""
                                        font.family: Theme.fontUi
                                        font.pixelSize: 10
                                        color: Qt.alpha(Theme.fg, 0.7)
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    radius: 6
                                    color: closeNMa.containsMouse ? Qt.alpha(Theme.error, 0.25) : "transparent"
                                    z: 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font.pixelSize: 11
                                        color: closeNMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.6)
                                    }

                                    MouseArea {
                                        id: closeNMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (Theme.notifOps && Theme.notifOps.forget) {
                                                Theme.notifOps.forget(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: nMa
                                anchors.fill: parent
                                anchors.rightMargin: 28
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Theme.notifOps && Theme.notifOps.open) {
                                        Theme.notifOps.open(modelData, function() { Theme.islandPanelOpen = false })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Section Tâches & Agenda
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "TÂCHES (" + root.todoOpenCount + ") & AGENDA"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Qt.alpha(Theme.fg, 0.65)
            }

            // Taquet surveillance Hermès
            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: hermesRow.implicitWidth + 12
                radius: 6
                color: root.todoSurveillance
                    ? Qt.alpha(Theme.accent, 0.22)
                    : (hermesMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.7) : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.width: 1
                border.color: root.todoSurveillance ? Qt.alpha(Theme.accent, 0.55) : Qt.alpha(Theme.fg, 0.14)

                Row {
                    id: hermesRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hermès"
                        font.family: Theme.fontUi
                        font.pixelSize: 10
                        font.weight: root.todoSurveillance ? Font.DemiBold : Font.Normal
                        color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 13
                        radius: 7
                        color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.22)

                        Rectangle {
                            width: 9
                            height: 9
                            radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.todoSurveillance ? 13 : 2
                            color: root.todoSurveillance ? Theme.bg : Theme.fg
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                MouseArea {
                    id: hermesMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (todoActionProc.running) return
                        root.todoSurveillance = !root.todoSurveillance
                        todoActionProc.command = [
                            "python3", Quickshell.shellPath("core/todo_applet.py"),
                            "surveillance", root.todoSurveillance ? "on" : "off"
                        ]
                        todoActionProc.running = true
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 6
                color: Theme.islandSidePanel === "todo-add"
                    ? Theme.accent
                    : (addTodoMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.surfaceVariant, 0.45))
                border.width: 1
                border.color: Theme.islandSidePanel === "todo-add" ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.islandSidePanel === "todo-add" ? Theme.bg : (addTodoMa.containsMouse ? Theme.accent : Theme.fg)
                }

                MouseArea {
                    id: addTodoMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandSidePanel = (Theme.islandSidePanel === "todo-add" ? "" : "todo-add")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Math.max(10, Math.round(Theme.pillRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.30)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Text {
                    visible: root.todoItems.length === 0
                    text: "Aucune tâche ouverte"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Qt.alpha(Theme.fg, 0.55)
                }

                Repeater {
                    model: root.todoItems
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            radius: 4
                            color: "transparent"
                            border.width: 1.5
                            border.color: Theme.accent

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let tid = String(modelData.id || "")
                                    if (tid !== "") {
                                        todoActionProc.command = ["python3", Quickshell.shellPath("core/todo_applet.py"), "cocher", tid]
                                        todoActionProc.running = true
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(modelData.texte || modelData.text || modelData.titre || "")
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: Theme.fg
                            elide: Text.ElideRight
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.1)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            visible: root.upcomingEvents.length === 0
                            Layout.fillWidth: true
                            spacing: 6

                            Icon {
                                glyph: "calendar"
                                size: 12
                                color: Qt.alpha(Theme.fg, 0.55)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Aucun événement à venir"
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textXs
                                color: Qt.alpha(Theme.fg, 0.55)
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            model: root.upcomingEvents
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6

                                Icon {
                                    glyph: "calendar"
                                    size: 12
                                    color: Theme.accent
                                }

                                Text {
                                    text: String(modelData.dateLabel || "")
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

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        text: Theme.islandSidePanel === "calendar" ? "Agenda ×" : "Agenda →"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        font.weight: Theme.islandSidePanel === "calendar" ? Font.Bold : Font.Normal
                        color: (Theme.islandSidePanel === "calendar" || calLinkMa.containsMouse) ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        MouseArea {
                            id: calLinkMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.islandSidePanel = (Theme.islandSidePanel === "calendar" ? "" : "calendar")
                        }
                    }
                }
            }
        }
    }
}
