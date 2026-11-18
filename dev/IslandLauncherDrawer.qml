import QtQuick
import QtQuick.Layouts

// Tiroir lanceur d'applications inline de l'Îlot dynamique (SUPER + R).
Item {
    id: root
    property bool open: false
    property int fadeDuration: 240
    property var results: []
    property bool searching: false
    property int selectedIdx: 0

    signal queryEdited(string q)
    signal selectedIdxChangedRequested(int idx)
    signal entryActivated(var entry)

    function setText(t) {
        launcherInput.text = String(t)
        launcherInput.cursorPosition = launcherInput.text.length
    }

    function clearAndFocus() {
        launcherInput.text = ""
        launcherInput.forceActiveFocus()
    }

    anchors.fill: parent
    clip: true
    opacity: root.open ? 1.0 : 0.0
    visible: opacity > 0.05
    Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Math.max(8, Math.round(Theme.globalRadius * 0.65))
            color: Qt.alpha(Theme.surfaceVariant, 0.45)
            border.width: 1
            border.color: launcherInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Icon {
                    glyph: "search"
                    size: Theme.iconSm
                    color: Theme.accent
                }

                TextInput {
                    id: launcherInput
                    Layout.fillWidth: true
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    color: Theme.fg
                    selectByMouse: true
                    clip: true
                    onTextChanged: root.queryEdited(text)
                    Keys.onEscapePressed: Theme.islandLauncherOpen = false
                    Keys.onUpPressed: {
                        if (root.results.length > 0) {
                            const next = (root.selectedIdx - 1 + root.results.length) % root.results.length
                            root.selectedIdxChangedRequested(next)
                            launcherListView.positionViewAtIndex(next, ListView.Contain)
                        }
                    }
                    Keys.onDownPressed: {
                        if (root.results.length > 0) {
                            const next = (root.selectedIdx + 1) % root.results.length
                            root.selectedIdxChangedRequested(next)
                            launcherListView.positionViewAtIndex(next, ListView.Contain)
                        }
                    }
                    Keys.onReturnPressed: {
                        if (root.results.length > 0) {
                            const idx = Math.max(0, Math.min(root.results.length - 1, root.selectedIdx))
                            root.entryActivated(root.results[idx])
                        }
                    }

                    Text {
                        visible: launcherInput.text === ""
                        text: "Rechercher une application (> cmd, = calcul, / fichier)…"
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textSm
                        color: Qt.alpha(Theme.fg, 0.45)
                    }
                }

                Item {
                    width: 22
                    height: 22
                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: 13
                        color: launcherCloseMa.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
                        opacityLevel: 1
                    }
                    MouseArea {
                        id: launcherCloseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.islandLauncherOpen = false
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                visible: root.results.length === 0
                anchors.centerIn: parent
                text: root.searching ? "Recherche…" : "Aucun résultat"
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                color: Qt.alpha(Theme.fg, 0.5)
            }

            ListView {
                id: launcherListView
                anchors.fill: parent
                spacing: 4
                clip: true
                visible: root.results.length > 0
                model: root.results

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIdx
                    width: launcherListView.width
                    height: 40
                    radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                    color: selected
                        ? Qt.alpha(Theme.accent, 0.22)
                        : (lItemMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.45) : "transparent")
                    border.width: selected ? 1 : 0
                    border.color: Qt.alpha(Theme.accent, 0.55)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Icon {
                            glyph: "rocket"
                            size: Theme.iconSm
                            color: selected ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.name || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.textSm
                                font.weight: selected ? Font.Bold : Font.Medium
                                color: selected ? Theme.accent : Theme.fg
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: Boolean(modelData.desc || modelData.generic)
                                Layout.fillWidth: true
                                text: String(modelData.desc || modelData.generic || "")
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.text2xs
                                color: Qt.alpha(Theme.fg, 0.58)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: lItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIdxChangedRequested(index)
                        onClicked: root.entryActivated(modelData)
                    }
                }
            }
        }
    }
}
