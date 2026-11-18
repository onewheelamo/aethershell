import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Tiroir de notes rapides inline de l'Îlot dynamique (SUPER + N).
Item {
    id: root
    property bool open: false
    property int fadeDuration: 240
    property var quickNotes: []
    property int activeNoteIdx: 0
    property bool _notesSyncing: false

    anchors.fill: parent
    clip: true
    opacity: root.open ? 1.0 : 0.0
    visible: opacity > 0.05
    Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

    Process {
        id: notesLoadProc
        command: [
            "python3", "-c",
            "import os, json\n"
            + "p = os.path.expanduser('~/.cache/quickshell/quick_notes.json')\n"
            + "try:\n"
            + "    d = json.loads(open(p).read())\n"
            + "    print(json.dumps(d if isinstance(d, list) and d else [{'id': 1, 'text': ''}]))\n"
            + "except Exception:\n"
            + "    print(json.dumps([{'id': 1, 'text': ''}]))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text.trim())
                    root.quickNotes = (Array.isArray(arr) && arr.length > 0) ? arr : [{ id: 1, text: "" }]
                } catch (e) {
                    root.quickNotes = [{ id: 1, text: "" }]
                }
                root.activeNoteIdx = Math.max(0, Math.min(root.quickNotes.length - 1, root.activeNoteIdx))
                root._notesSyncing = true
                noteEditor.text = String((root.quickNotes[root.activeNoteIdx] && root.quickNotes[root.activeNoteIdx].text) || "")
                root._notesSyncing = false
            }
        }
    }

    Process { id: notesSaveProc }

    function activate() {
        if (!notesLoadProc.running) notesLoadProc.running = true
        noteEditor.forceActiveFocus()
    }

    function saveQuickNotes() {
        notesSaveProc.environment = ({ "QS_NOTES_JSON": JSON.stringify(root.quickNotes) })
        notesSaveProc.command = [
            "python3", "-c",
            "import os, pathlib\n"
            + "p = pathlib.Path(os.path.expanduser('~/.cache/quickshell/quick_notes.json'))\n"
            + "p.parent.mkdir(parents=True, exist_ok=True)\n"
            + "p.write_text(os.environ.get('QS_NOTES_JSON', '[]'))"
        ]
        if (!notesSaveProc.running) notesSaveProc.running = true
    }

    Timer {
        id: notesSaveTimer
        interval: 300
        repeat: false
        onTriggered: root.saveQuickNotes()
    }

    function selectNote(idx) {
        if (idx < 0 || idx >= root.quickNotes.length) return
        root.activeNoteIdx = idx
        root._notesSyncing = true
        noteEditor.text = String(root.quickNotes[idx].text || "")
        root._notesSyncing = false
        noteEditor.forceActiveFocus()
    }

    function addQuickNote() {
        const list = root.quickNotes.slice()
        list.push({ id: Date.now(), text: "" })
        root.quickNotes = list
        selectNote(list.length - 1)
        root.saveQuickNotes()
    }

    function deleteQuickNote(idx) {
        if (root.quickNotes.length <= 1) {
            root.quickNotes = [{ id: 1, text: "" }]
            selectNote(0)
            root.saveQuickNotes()
            return
        }
        const list = root.quickNotes.slice()
        list.splice(idx, 1)
        root.quickNotes = list
        selectNote(Math.max(0, Math.min(list.length - 1, idx)))
        root.saveQuickNotes()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Icon {
                glyph: "widgets"
                size: Theme.iconSm
                color: Theme.accent
            }

            Text {
                text: "NOTES"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.accent
            }

            Row {
                Layout.fillWidth: true
                spacing: 4
                clip: true

                Repeater {
                    model: root.quickNotes
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool active: index === root.activeNoteIdx
                        width: noteTabLbl.implicitWidth + 14
                        height: 22
                        radius: 6
                        color: active ? Theme.accent : (noteTabMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07))

                        Text {
                            id: noteTabLbl
                            anchors.centerIn: parent
                            text: "#" + (index + 1)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.bold: active
                            color: active ? Theme.bg : Theme.fg
                        }

                        MouseArea {
                            id: noteTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectNote(index)
                        }
                    }
                }

                Rectangle {
                    width: 22
                    height: 22
                    radius: 6
                    color: addNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        font.bold: true
                        color: addNoteMa.containsMouse ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: addNoteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.addQuickNote()
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: pinNoteLbl.implicitWidth + 14
                Layout.preferredHeight: 22
                radius: 6
                color: pinNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.08)

                Text {
                    id: pinNoteLbl
                    anchors.centerIn: parent
                    text: "Bureau"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    font.weight: Font.DemiBold
                    color: pinNoteMa.containsMouse ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: pinNoteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.saveQuickNotes()
                        const list = ShellState.widgets || []
                        let existing = null
                        for (let i = 0; i < list.length; i++) {
                            if (list[i] && list[i].type === "notes") {
                                existing = list[i]
                                break
                            }
                        }
                        const cm = Quickshell.shellPath("core/config_manager.py")
                        if (existing && existing.id) {
                            Quickshell.execDetached([
                                "sh", "-c",
                                "python3 \"$1\" widget_set \"$2\" enabled true && python3 \"$1\" widget_set \"$2\" note_index \"$3\"",
                                "sh", cm, String(existing.id), String(root.activeNoteIdx)
                            ])
                        } else {
                            const wsId = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1
                            Quickshell.execDetached([
                                "python3", cm, "widget_add", "notes", String(wsId > 0 ? wsId : 1), "120", "160"
                            ])
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: copyNoteLbl.implicitWidth + 14
                Layout.preferredHeight: 22
                radius: 6
                color: copyNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)

                Text {
                    id: copyNoteLbl
                    anchors.centerIn: parent
                    text: "Copier"
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    color: copyNoteMa.containsMouse ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: copyNoteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["wl-copy", noteEditor.text])
                }
            }

            Rectangle {
                Layout.preferredWidth: delNoteLbl.implicitWidth + 14
                Layout.preferredHeight: 22
                radius: 6
                color: delNoteMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : Qt.alpha(Theme.fg, 0.08)

                Text {
                    id: delNoteLbl
                    anchors.centerIn: parent
                    text: "Suppr."
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.text2xs
                    color: delNoteMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.75)
                }

                MouseArea {
                    id: delNoteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.deleteQuickNote(root.activeNoteIdx)
                }
            }

            Item {
                width: 22
                height: 22
                Icon {
                    anchors.centerIn: parent
                    glyph: "close"
                    size: 13
                    color: notesCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                    opacityLevel: 1
                }
                MouseArea {
                    id: notesCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandNotesOpen = false
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Math.max(8, Math.round(Theme.globalRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.35)
            border.width: 1
            border.color: noteEditor.activeFocus ? Qt.alpha(Theme.accent, 0.6) : Qt.alpha(Theme.fg, 0.1)

            Flickable {
                id: noteFlick
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, noteEditor.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: noteEditor
                    width: noteFlick.width
                    height: Math.max(noteFlick.height, implicitHeight)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    color: Theme.fg
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    Keys.onEscapePressed: Theme.islandNotesOpen = false
                    onTextChanged: {
                        if (root._notesSyncing) return
                        if (root.activeNoteIdx >= 0 && root.activeNoteIdx < root.quickNotes.length) {
                            const list = root.quickNotes.slice()
                            list[root.activeNoteIdx] = Object.assign({}, list[root.activeNoteIdx], { text: text })
                            root.quickNotes = list
                            notesSaveTimer.restart()
                        }
                    }

                    Text {
                        visible: noteEditor.text === ""
                        text: "Écrire une note rapide… (sauvegarde automatique)"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        color: Qt.alpha(Theme.fg, 0.42)
                    }
                }
            }
        }
    }
}
