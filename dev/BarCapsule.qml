import QtQuick
import Quickshell
import "."

// Capsule unifiée des 3 îlots de la barre haute (gauche, centre, droite).
Item {
    id: capsule

    property string ile: "haut:debut"
    property int rowSpacing: Theme.space2
    property bool centerMode: false
    property bool rightMode: false
    property bool tabletMode: false

    readonly property bool calendarOpen: centerMode && Theme.activePopup === "calendar"

    implicitWidth: contentRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function synchroniserSystemInfo() {
        if (!rightMode) return
        const d = SystemServices.systemInfo
        if (d && typeof d.tablet_mode === "boolean")
            capsule.tabletMode = d.tablet_mode
    }

    Component.onCompleted: capsule.synchroniserSystemInfo()

    Connections {
        target: SystemServices
        enabled: capsule.rightMode
        function onSystemInfoChanged() { capsule.synchroniserSystemInfo() }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: capsule.calendarOpen ? Theme.accentMuted : Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)
        clip: capsule.centerMode

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: capsule.rowSpacing

            Item { visible: capsule.centerMode; width: 10; height: 1 }

            AppletRow {
                ile: capsule.ile
                anchors.verticalCenter: parent.verticalCenter
            }

            Item { visible: capsule.centerMode; width: 4; height: 1 }

            Row {
                visible: capsule.centerMode && Theme.showConfigButton
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
                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: Theme.configPanelVisible
                        ? Theme.accent
                        : (gearMa.containsMouse ? Theme.surfaceVariant : "transparent")

                    Icon {
                        anchors.centerIn: parent
                        glyph: "cog"
                        size: Math.max(8, Math.round(Theme.iconMd * Theme.barScale))
                        color: Theme.configPanelVisible ? Theme.bg : Theme.fg
                        opacityLevel: 1
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

            Rectangle {
                visible: capsule.rightMode && capsule.tabletMode
                width: 26
                height: 26
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Icon {
                    anchors.centerIn: parent
                    glyph: "keyboard"
                    size: Math.max(8, Math.round(Theme.iconSm * Theme.barScale))
                    color: Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "wvkbd-mobintl || cosmic-osk || wvkbd"])
                }
            }
        }
    }
}
