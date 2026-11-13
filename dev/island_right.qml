import QtQuick
import Quickshell

// ════════════════════════════════════════════════════════════════════════════
// ÎLOT DROIT — conteneur des applets de fin de barre et bouton tablette.
// ════════════════════════════════════════════════════════════════════════════
// Le serveur de notifications, les toasts et `Theme.notifOps` vivent désormais
// dans `NotifService.qml` afin de rester actifs en mode `island`.
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandRight

    implicitWidth: mainRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Visible seulement en mode tablette Lenovo Yoga
    property bool tabletMode: false

    function synchroniserSystemInfo() {
        const d = Theme.systemInfo
        if (d && typeof d.tablet_mode === "boolean")
            islandRight.tabletMode = d.tablet_mode
    }

    Component.onCompleted: islandRight.synchroniserSystemInfo()

    Connections {
        target: Theme
        function onSystemInfoChanged() {
            islandRight.synchroniserSystemInfo()
        }
    }

    Rectangle {
        id: islandBg
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Row {
            id: mainRow
            anchors.centerIn: parent
            spacing: 12

            // Applets posés sur l'îlot droit (registre bar_applets.json).
            AppletRow {
                ile: "haut:fin"
                anchors.verticalCenter: parent.verticalCenter
            }

            // Bouton clavier virtuel (mode tablette uniquement)
            Rectangle {
                id: keyboardBtn
                visible: islandRight.tabletMode
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
                    size: Theme.iconSm
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
