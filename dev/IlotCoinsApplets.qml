import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// APPLETS SORTIS DE L'ÎLOT : affiche dans les quatre coins de l'écran les
// applets que l'utilisateur a choisi de détacher de l'îlot dynamique.
Scope {
    id: root

    readonly property var ecranPrincipal: {
        if (Theme.primaryMonitor && Quickshell.screens) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === Theme.primaryMonitor) {
                    return Quickshell.screens[i]
                }
            }
        }
        return (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null
    }

    Variants {
        model: [
            { id: "top-left",     top: true,  bottom: false, left: true,  right: false },
            { id: "top-right",    top: true,  bottom: false, left: false, right: true  },
            { id: "bottom-left",  top: false, bottom: true,  left: true,  right: false },
            { id: "bottom-right", top: false, bottom: true,  left: false, right: true  }
        ]

        PanelWindow {
            id: coinWin
            required property var modelData
            readonly property var applets: ShellState.appletsPourCoinIlot(modelData.id)
            readonly property int marge: Math.max(8, Theme.barMarginTop)

            screen: root.ecranPrincipal
            visible: Theme.barStyle === "island" && applets.length > 0
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "shell-ilot-coin-" + modelData.id

            anchors {
                top: modelData.top
                bottom: modelData.bottom
                left: modelData.left
                right: modelData.right
            }
            margins {
                top: modelData.top ? marge : 0
                bottom: modelData.bottom ? marge : 0
                left: modelData.left ? marge : 0
                right: modelData.right ? marge : 0
            }

            implicitWidth: pilule.implicitWidth
            implicitHeight: pilule.implicitHeight

            Rectangle {
                id: pilule
                implicitWidth: Math.max(Theme.barHeight, rangee.implicitWidth + Theme.space4)
                implicitHeight: Math.max(Theme.barHeight, rangee.implicitHeight + Theme.space2)
                radius: Theme.barRadius
                color: Theme.islandBg
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.10)

                AppletRow {
                    id: rangee
                    anchors.centerIn: parent
                    directModel: coinWin.applets
                }
            }
        }
    }
}
