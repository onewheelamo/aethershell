import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// APPLETS SORTIS DE L'ÎLOT : affiche dans les quatre coins de l'écran les
// applets que l'utilisateur a choisi de détacher de l'îlot dynamique,
// alignés sur la même ligne et les mêmes règles de surface que la pilule.
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
                top: modelData.top ? Theme.gutterV : 0
                bottom: modelData.bottom ? Theme.gutterV : 0
                left: modelData.left ? Theme.gutterH : 0
                right: modelData.right ? Theme.gutterH : 0
            }

            implicitWidth: pilule.implicitWidth
            implicitHeight: Theme.barHeight

            Item {
                id: pilule
                implicitWidth: Math.max(Theme.barHeight, rangee.implicitWidth + Theme.padH * 2)
                implicitHeight: Theme.barHeight

                SurfaceFloutee {
                    anchors.fill: parent
                    rayon: Theme.pillRadius
                    teinte: Theme.barBg
                    bordureCouleur: Theme.accent
                    bordureLargeur: Theme.barBorder ? 1 : 0
                    actif: false
                }

                AppletRow {
                    id: rangee
                    anchors.centerIn: parent
                    directModel: coinWin.applets
                }
            }
        }
    }
}
