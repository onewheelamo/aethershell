import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════════
// ONGLET « CONNEXION » : THÈMES DU GREETER
// ═══════════════════════════════════════════════════════════════════════════════
// - Grille de miniatures (une capture réelle par configuration du thème)
// - Clic sur une miniature : sélection + aperçu plein écran (mode test SDDM)
// - « Appliquer » écrit la sélection via /usr/local/bin/greeter-palette (polkit)
// Le backend est core/greeter_manager.py ; les miniatures vivent dans
// ~/.cache/quickshell/greeter-thumbs et se régénèrent à la demande.
Item {
    id: greeterTab

    implicitHeight: content.implicitHeight
    height: implicitHeight

    property var presets: []
    property string activeId: ""
    // La sélection vit sur la racine du panneau : ce composant est déchargé
    // quand on quitte l'onglet, la racine non.
    property string selectedId: root.greeterSelected
    onSelectedIdChanged: if (root.greeterSelected !== selectedId) root.greeterSelected = selectedId
    property string status: ""
    property bool busy: false
    property string lastThumbStamp: ""

    readonly property var selectedPreset: {
        for (let i = 0; i < presets.length; i++)
            if (presets[i].id === selectedId) return presets[i]
        return null
    }
    readonly property real cellWidth: Math.floor((width - 2 * Theme.space3) / 3)
    readonly property real cellHeight: Math.round(cellWidth * 9 / 16)

    function reload() {
        if (!listProc.running) listProc.running = true
    }

    function nameOf(id) {
        for (let i = 0; i < presets.length; i++)
            if (presets[i].id === id) return presets[i].name
        return id
    }

    // Aperçu plein écran : on ferme le panneau pour laisser voir le greeter.
    function preview(id) {
        selectedId = id
        status = "Aperçu de " + nameOf(id) + " — il se ferme seul (ou SUPER + Q)"
        // execDetached : le greeter est un processus détaché qui ne rend rien.
        // Un Process dont la command est assignée à l'exécution ne démarre pas ici.
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/greeter_manager.py"),
                                 "preview", id])
        Theme.configPanelVisible = false
    }

    function applySelected() {
        if (!selectedId || busy) return
        busy = true
        pendingId = selectedId
        status = "Application de " + nameOf(selectedId) + "…"
        // execDetached plutôt qu'un Process : la commande dépend de la sélection,
        // et une `command` assignée à l'exécution ne démarre pas ici.
        Quickshell.execDetached(["python3", Quickshell.shellPath("core/greeter_manager.py"),
                                 "apply", selectedId])
        // La sélection est écrite sur disque : on relit l'état réel ensuite.
        applyTimer.restart()
    }

    function regenerateThumbs() {
        if (busy) return
        busy = true
        status = "Génération des aperçus (quelques secondes par thème)…"
        thumbsProc.running = true
    }

    Component.onCompleted: reload()

    Process {
        id: listProc
        command: ["python3", Quickshell.shellPath("core/greeter_manager.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    greeterTab.presets = d.presets || []
                    greeterTab.activeId = d.active || ""
                    // Sélection orpheline (thème retiré) : on retombe sur l'actif.
                    let known = false
                    for (let i = 0; i < greeterTab.presets.length; i++)
                        if (greeterTab.presets[i].id === greeterTab.selectedId) known = true
                    if (!known) greeterTab.selectedId = d.active || ""
                    if (greeterTab.pendingId !== "") {
                        const ok = d.active === greeterTab.pendingId
                        greeterTab.status = ok
                            ? "Appliqué : " + greeterTab.nameOf(greeterTab.pendingId)
                            : "Échec de l'application (thème actif : "
                              + greeterTab.nameOf(d.active) + ")"
                        greeterTab.pendingId = ""
                        greeterTab.busy = false
                    }
                } catch (e) {
                    greeterTab.status = "Lecture des thèmes impossible"
                }
            }
        }
    }

    // Résultat de l'application : lu sur l'état réel, pas sur la sortie du script.
    property string pendingId: ""
    Timer {
        id: applyTimer
        interval: 1600
        onTriggered: greeterTab.reload()
    }

    Process {
        id: thumbsProc
        command: ["python3", Quickshell.shellPath("core/greeter_manager.py"), "thumbnails"]
        stdout: StdioCollector {
            onStreamFinished: {
                greeterTab.busy = false
                greeterTab.status = "Aperçus régénérés"
                greeterTab.reload()
            }
        }
    }

    Column {
        id: content
        width: parent.width
        spacing: Theme.space3

        CollapsibleSection {
            id: secGreeter
            title: "Écran de connexion"
            icon: "lock"
            expanded: true

            Column {
                width: parent.width
                spacing: Theme.space3

                Text {
                    width: parent.width
                    text: "Le thème choisi s'applique à la prochaine ouverture de session."
                    color: Qt.alpha(Theme.fg, 0.62)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                Grid {
                    width: parent.width
                    columns: 3
                    spacing: Theme.space3

                    Repeater {
                        model: greeterTab.presets

                        Item {
                            id: cell
                            required property var modelData
                            readonly property bool selected: greeterTab.selectedId === modelData.id
                            readonly property bool active: modelData.active

                            width: greeterTab.cellWidth
                            height: greeterTab.cellHeight + 24

                            Rectangle {
                                id: frame
                                width: parent.width
                                height: greeterTab.cellHeight
                                radius: Theme.globalRadius
                                color: Theme.surfaceVariant
                                border.width: cell.selected ? 2 : 1
                                border.color: cell.selected
                                    ? Theme.accent
                                    : Qt.alpha(Theme.fg, 0.10)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: cell.modelData.thumb !== ""
                                        ? "file://" + cell.modelData.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                // Pas encore de capture : vignette typographique.
                                Text {
                                    anchors.centerIn: parent
                                    visible: cell.modelData.thumb === ""
                                    text: "Aperçu à générer"
                                    color: Qt.alpha(Theme.fg, 0.40)
                                    font.pixelSize: Theme.textXs
                                }

                                // Thème actuellement sélectionné dans sddm.
                                Rectangle {
                                    visible: cell.active
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 6
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: Theme.bg
                                        font.pixelSize: Theme.textXs
                                        font.bold: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: greeterTab.preview(cell.modelData.id)
                                }
                            }

                            Text {
                                anchors.top: frame.bottom
                                anchors.topMargin: 5
                                width: parent.width
                                text: cell.modelData.name
                                color: cell.selected ? Theme.accent : Qt.alpha(Theme.fg, 0.78)
                                font.pixelSize: Theme.textXs
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.space2

                    Rectangle {
                        id: applyBtn
                        width: applyText.implicitWidth + 28
                        height: 32
                        radius: Theme.globalRadius
                        color: greeterTab.busy
                            ? Qt.alpha(Theme.accent, 0.25)
                            : (applyMa.containsMouse ? Qt.lighter(Theme.accent, 1.15) : Theme.accent)

                        Text {
                            id: applyText
                            anchors.centerIn: parent
                            text: "Appliquer"
                            color: Theme.bg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }

                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !greeterTab.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: greeterTab.applySelected()
                        }
                    }

                    Rectangle {
                        id: previewBtn
                        width: previewText.implicitWidth + 28
                        height: 32
                        radius: Theme.globalRadius
                        color: previewMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55)
                        border.color: Theme.surfaceVariant
                        border.width: 1

                        Text {
                            id: previewText
                            anchors.centerIn: parent
                            text: "Aperçu plein écran"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                        }

                        MouseArea {
                            id: previewMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (greeterTab.selectedId !== "")
                                    greeterTab.preview(greeterTab.selectedId)
                            }
                        }
                    }

                    // Pousse « Aperçus » à droite (4 enfants, donc 3 espacements).
                    Item {
                        width: Math.max(0, parent.width - applyBtn.width - previewBtn.width
                                        - regenBtn.width - parent.spacing * 3)
                        height: 1
                    }

                    Rectangle {
                        id: regenBtn
                        width: regenText.implicitWidth + 22
                        height: 32
                        radius: Theme.globalRadius
                        color: regenMa.containsMouse ? Theme.surfaceVariant : "transparent"
                        border.color: Qt.alpha(Theme.fg, 0.12)
                        border.width: 1

                        Text {
                            id: regenText
                            anchors.centerIn: parent
                            text: "Aperçus"
                            color: Qt.alpha(Theme.fg, 0.62)
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            id: regenMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !greeterTab.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: greeterTab.regenerateThumbs()
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: greeterTab.status !== ""
                    text: greeterTab.status
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
