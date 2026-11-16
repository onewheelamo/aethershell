import QtQuick
import ".."
import Quickshell
import Quickshell.Io

// NOTES RAPIDES / POST-IT — affiche et suit les notes de ~/.cache/quickshell/quick_notes.json.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    property int activeIdx: Math.max(0, Number(options && options.note_index) || 0)
    property var notesList: []

    readonly property string noteText: {
        if (!notesList || notesList.length === 0) return ""
        const idx = Math.max(0, Math.min(notesList.length - 1, activeIdx))
        return String((notesList[idx] && notesList[idx].text) || "")
    }

    FileView {
        id: notesFile
        path: (Quickshell.env("HOME") || "/home") + "/.cache/quickshell/quick_notes.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const arr = JSON.parse(text())
                root.notesList = Array.isArray(arr) ? arr : []
                if (root.activeIdx >= root.notesList.length && root.notesList.length > 0) {
                    root.activeIdx = root.notesList.length - 1
                }
            } catch (e) {
                root.notesList = []
            }
        }
    }

    Connections {
        target: Theme
        function onIslandNotesOpenChanged() {
            if (!Theme.islandNotesOpen) notesFile.reload()
        }
    }

    implicitWidth: Math.round(240 * echelle)
    implicitHeight: noteCol.implicitHeight

    Column {
        id: noteCol
        width: parent.width
        spacing: Math.round(6 * echelle)

        Row {
            width: parent.width
            spacing: Math.round(6 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "widgets"
                size: Math.round(Theme.iconSm * echelle)
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "POST-IT"
                color: Theme.accent
                font.family: Theme.fontUi
                font.pixelSize: Math.round(Theme.text2xs * echelle)
                font.bold: true
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: root.notesList.length > 1

                Repeater {
                    model: root.notesList.slice(0, 5)
                    delegate: Rectangle {
                        required property int index
                        readonly property bool sel: index === root.activeIdx
                        width: Math.round(18 * root.echelle)
                        height: Math.round(16 * root.echelle)
                        radius: 4
                        color: sel ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                        Text {
                            anchors.centerIn: parent
                            text: String(index + 1)
                            color: sel ? Theme.bg : Theme.fg
                            font.pixelSize: Math.round(9 * root.echelle)
                            font.bold: sel
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeIdx = index
                        }
                    }
                }
            }

            Item { width: 1; height: 1 }

            Rectangle {
                visible: Theme.barStyle === "island"
                anchors.verticalCenter: parent.verticalCenter
                width: editNoteLbl.implicitWidth + 10
                height: Math.round(18 * root.echelle)
                radius: 5
                color: editNoteMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : Qt.alpha(Theme.fg, 0.1)

                Text {
                    id: editNoteLbl
                    anchors.centerIn: parent
                    text: "✎"
                    color: editNoteMa.containsMouse ? Theme.accent : Theme.fg
                    font.pixelSize: Math.round(10 * root.echelle)
                }

                MouseArea {
                    id: editNoteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.islandNotesOpen = true
                }
            }
        }

        Text {
            width: parent.width
            text: root.noteText.trim() !== "" ? root.noteText : "Aucune note (SUPER + N pour écrire)"
            color: root.noteText.trim() !== "" ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
            font.family: Theme.fontUi
            font.pixelSize: Math.round(Theme.textSm * echelle)
            wrapMode: Text.WordWrap
            maximumLineCount: 12
            elide: Text.ElideRight
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }
    }
}
