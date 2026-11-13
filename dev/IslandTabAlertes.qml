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
    property string nextEventText: "Aucun événement à venir"

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

    Process {
        id: todoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
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

    Process {
        id: calProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    let now = new Date()
                    let iso = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
                    let evs = (d.events && d.events[iso]) ? d.events[iso] : []
                    if (evs.length > 0) {
                        let ev = evs[0]
                        root.nextEventText = (ev.time ? (ev.time + " · ") : "") + String(ev.summary || "Événement")
                    } else {
                        root.nextEventText = "Aucun rendez-vous aujourd'hui"
                    }
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

                Text {
                    id: dndLbl
                    anchors.centerIn: parent
                    text: Theme.doNotDisturb ? "🔕 N.P.D. ON" : "🔔 N.P.D."
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.doNotDisturb ? Theme.accent : Theme.fg
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
        Text {
            text: "TÂCHES (" + root.todoOpenCount + ") & AGENDA"
            font.family: Theme.fontUi
            font.pixelSize: Theme.textXs
            font.weight: Font.Bold
            color: Qt.alpha(Theme.fg, 0.65)
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

                    Text {
                        Layout.fillWidth: true
                        text: "📅 " + root.nextEventText
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Agenda ↗"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: calLinkMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        MouseArea {
                            id: calLinkMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.islandPanelOpen = false
                                Theme.activePopup = "calendar"
                            }
                        }
                    }
                }
            }
        }
    }
}
