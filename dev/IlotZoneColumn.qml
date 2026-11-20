import QtQuick
import "."

// Colonne de zone de l'Îlot dynamique (Haut Gauche / Îlot / Haut Droite / Bas Gauche / Bas Droite).
Rectangle {
    id: zCol
    required property var modelData
    property var ilotBloc
    property var panelRoot
    property real colWidth: 200
    property real minHeight: 104

    readonly property string zoneCode: modelData.code
    readonly property var items: ilotBloc ? ilotBloc.ilotAppletsInZone(zoneCode) : []
    readonly property bool isDropTarget: Boolean(panelRoot && ilotBloc && panelRoot.dragCapsuleId !== "" && ilotBloc.hoverIlotZone === zoneCode)

    width: colWidth
    height: Math.max(minHeight, zColInner.implicitHeight + 16)
    radius: Theme.globalRadius
    color: isDropTarget ? Qt.alpha(Theme.accent, 0.10) : Qt.alpha(Theme.surfaceVariant, 0.35)
    border.color: isDropTarget ? Theme.accent : Qt.alpha(Theme.fg, 0.12)
    border.width: isDropTarget ? 2 : 1

    Component.onCompleted: {
        if (!ilotBloc) return
        const r = Object.assign({}, ilotBloc.zoneRefs)
        r[zCol.zoneCode] = zCol
        ilotBloc.zoneRefs = r
    }

    Column {
        id: zColInner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 5

        Item {
            width: parent.width
            height: 22

            Text {
                id: zTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: zCol.modelData.label
                color: Theme.fg
                font.pixelSize: Theme.textXs
                font.bold: true
            }

            Rectangle {
                anchors.left: zTitle.right
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(18, zCnt.implicitWidth + 8)
                height: 16
                radius: 8
                color: Qt.alpha(Theme.fg, 0.12)

                Text {
                    id: zCnt
                    anchors.centerIn: parent
                    text: String(zCol.items.length)
                    color: Qt.alpha(Theme.fg, 0.8)
                    font.pixelSize: 10
                    font.bold: true
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 5
                color: zAddMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.10)

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: zAddMa.containsMouse ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: zAddMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!zCol.ilotBloc) return
                        zCol.ilotBloc.ilotAddZone = zCol.zoneCode
                        zCol.ilotBloc.ilotAddingOpen = true
                    }
                }
            }
        }

        Text {
            visible: zCol.items.length === 0
            width: parent.width
            height: 36
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: "Vide · Glisser ou +"
            color: Qt.alpha(Theme.fg, 0.38)
            font.pixelSize: Theme.text2xs
        }

        Repeater {
            model: zCol.items

            delegate: Column {
                id: cardWrap
                required property var modelData
                required property int index
                width: parent.width
                spacing: 2

                Rectangle {
                    visible: zCol.isDropTarget && zCol.ilotBloc && zCol.ilotBloc.hoverIlotIdx === cardWrap.index
                    width: parent.width
                    height: 2
                    radius: 1
                    color: Theme.accent
                }

                Rectangle {
                    id: appCard
                    width: parent.width
                    height: 32
                    radius: Math.max(6, Math.round(Theme.globalRadius * 0.6))
                    color: cardMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.95) : Theme.surfaceVariant
                    border.color: Qt.alpha(Theme.fg, 0.10)
                    border.width: 1

                    MouseArea {
                        id: cardMa
                        anchors.left: parent.left
                        anchors.right: modePill.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 2
                        hoverEnabled: true
                        preventStealing: dragging
                        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property real startX: 0
                        property real startY: 0
                        property bool dragging: false

                        onPressed: mouse => {
                            startX = mouse.x
                            startY = mouse.y
                            dragging = false
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || !zCol.panelRoot || !zCol.ilotBloc) return
                            if (!dragging && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                                dragging = true
                                zCol.panelRoot.dragCapsuleId = cardWrap.modelData.id
                                zCol.panelRoot.dragCapsuleLabel = cardWrap.modelData.label
                            }
                            if (dragging) {
                                const pt = appCard.mapToItem(zCol.panelRoot, mouse.x, mouse.y)
                                zCol.panelRoot.dragPointerX = pt.x
                                zCol.panelRoot.dragPointerY = pt.y
                                const hit = zCol.ilotBloc.findIlotZoneDrop(pt.x, pt.y)
                                zCol.ilotBloc.hoverIlotZone = hit ? hit.zone : "__none__"
                                zCol.ilotBloc.hoverIlotIdx = hit ? hit.idx : -1
                            }
                        }

                        onReleased: {
                            if (dragging && zCol.panelRoot && zCol.ilotBloc) {
                                const sk = zCol.ilotBloc.ilotStyleKeyForId(cardWrap.modelData.id)
                                if (!sk) {
                                    const hit = zCol.ilotBloc.findIlotZoneDrop(zCol.panelRoot.dragPointerX, zCol.panelRoot.dragPointerY)
                                    if (hit) {
                                        const cArg = hit.zone === "" ? "ilot" : hit.zone
                                        zCol.panelRoot.runConfigCmd(["ilot_applet_move_to", cardWrap.modelData.id, cArg, String(hit.idx)])
                                    }
                                }
                                zCol.panelRoot.dragCapsuleId = ""
                                zCol.panelRoot.dragCapsuleLabel = ""
                                zCol.ilotBloc.hoverIlotZone = "__none__"
                                zCol.ilotBloc.hoverIlotIdx = -1
                                dragging = false
                                return
                            }
                            dragging = false
                            if (cardWrap.modelData.id === "maj" && zCol.ilotBloc) zCol.ilotBloc.majOptsOpen = !zCol.ilotBloc.majOptsOpen
                        }

                        onCanceled: {
                            dragging = false
                            if (zCol.ilotBloc) {
                                zCol.ilotBloc.hoverIlotZone = "__none__"
                                zCol.ilotBloc.hoverIlotIdx = -1
                            }
                            if (zCol.panelRoot) {
                                zCol.panelRoot.dragCapsuleId = ""
                                zCol.panelRoot.dragCapsuleLabel = ""
                            }
                        }
                    }

                    Text {
                        id: grip
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⋮⋮"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: 10
                    }

                    Text {
                        anchors.left: grip.right
                        anchors.leftMargin: 6
                        anchors.right: majOptBtn.visible ? majOptBtn.left : modePill.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: cardWrap.modelData.label
                        color: Theme.fg
                        font.pixelSize: Theme.text2xs
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: majOptBtn
                        visible: cardWrap.modelData.id === "maj"
                        anchors.right: modePill.left
                        anchors.rightMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 4
                        color: (zCol.ilotBloc && zCol.ilotBloc.majOptsOpen) ? Theme.accent : Qt.alpha(Theme.fg, 0.08)

                        Icon {
                            anchors.centerIn: parent
                            glyph: "cog"
                            size: 11
                            color: (zCol.ilotBloc && zCol.ilotBloc.majOptsOpen) ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (zCol.ilotBloc) zCol.ilotBloc.majOptsOpen = !zCol.ilotBloc.majOptsOpen
                        }
                    }

                    Rectangle {
                        id: modePill
                        anchors.right: remBtn.left
                        anchors.rightMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: modeTxt.implicitWidth + 10
                        height: 18
                        radius: 4
                        color: Qt.alpha(Theme.accent, 0.18)
                        border.color: Qt.alpha(Theme.accent, 0.45)
                        border.width: 1

                        Text {
                            id: modeTxt
                            anchors.centerIn: parent
                            text: zCol.ilotBloc ? zCol.ilotBloc.ilotModeShort(cardWrap.modelData.mode) : ""
                            color: Theme.accent
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (zCol.panelRoot && zCol.ilotBloc) {
                                const sk = zCol.ilotBloc.ilotStyleKeyForId(cardWrap.modelData.id)
                                const nm = zCol.ilotBloc.nextIlotMode(cardWrap.modelData.mode)
                                if (sk) zCol.panelRoot.runConfigCmd(["style", sk, nm])
                                else zCol.panelRoot.runConfigCmd(["ilot_applet_mode", cardWrap.modelData.id, nm])
                            }
                        }
                    }

                    Rectangle {
                        id: remBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        radius: 4
                        color: remMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: remMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: remMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (zCol.panelRoot && zCol.ilotBloc) {
                                const sk = zCol.ilotBloc.ilotStyleKeyForId(cardWrap.modelData.id)
                                if (sk) zCol.panelRoot.runConfigCmd(["style", sk, "off"])
                                else zCol.panelRoot.runConfigCmd(["ilot_applet_mode", cardWrap.modelData.id, "off"])
                            }
                        }
                    }
                }

                // Options rattachées à la carte « Mises à jour »
                Rectangle {
                    visible: cardWrap.modelData.id === "maj" && Boolean(zCol.ilotBloc && zCol.ilotBloc.majOptsOpen)
                    width: parent.width
                    height: visible ? majSubCol.implicitHeight + 12 : 0
                    radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                    color: Qt.alpha(Theme.bg, 0.35)
                    border.color: Qt.alpha(Theme.accent, 0.4)
                    border.width: 1

                    Column {
                        id: majSubCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 22

                            Text {
                                anchors.left: parent.left
                                anchors.right: majSw.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Si MAJ dispo"
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.pixelSize: Theme.text2xs
                                elide: Text.ElideRight
                            }

                            ConfigSwitch {
                                id: majSw
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: Theme.majSeulementSiDispo
                                onToggled: if (zCol.panelRoot) zCol.panelRoot.runConfigCmd(["style", "maj_seulement_si_dispo", String(!Theme.majSeulementSiDispo)])
                            }
                        }

                        Item {
                            width: parent.width
                            height: 22

                            Text {
                                anchors.left: parent.left
                                anchors.right: majSeg.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Terminal"
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.pixelSize: Theme.text2xs
                                elide: Text.ElideRight
                            }

                            ConfigSegmented {
                                id: majSeg
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                itemHeight: 18
                                choices: [
                                    { code: "float", label: "Flott." },
                                    { code: "tiling", label: "Tiling" }
                                ]
                                currentCode: Theme.majTerminalMode
                                onSelected: code => {
                                    if (zCol.panelRoot) zCol.panelRoot.runConfigCmd(["style", "maj_terminal_mode", code])
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: zCol.isDropTarget && zCol.ilotBloc && zCol.ilotBloc.hoverIlotIdx >= zCol.items.length
            width: parent.width
            height: 2
            radius: 1
            color: Theme.accent
        }
    }
}
