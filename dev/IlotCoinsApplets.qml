import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// APPLETS SORTIS DE L'ÎLOT : condensés en un cercle sur la même ligne que
// la pilule (ExclusionMode.Ignore), s'étendant au survol de la souris sans
// redimensionner la surface Wayland à chaque image (mask: Region sur `pilule`).
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

    readonly property var svgIcones: (["cpu", "ram", "gpu", "temp", "disque", "reseau", "load", "swap"])

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
            readonly property bool groupes: Theme.ilotCoinsGroupes
            readonly property bool ancreADroite: (groupes && modelData.left) || (!groupes && modelData.right)
            readonly property int ecranW: screen ? screen.width : 1920
            readonly property string premiereIcone: (applets.length > 0 && applets[0].icone) ? String(applets[0].icone) : "apps"
            readonly property bool estSvg: root.svgIcones.indexOf(premiereIcone) >= 0
            readonly property real largeurEtendue: Math.max(Theme.barHeight, rangee.implicitWidth + Theme.padH * 2)
            readonly property bool popupDansCeCoin: {
                const p = String(Theme.activePopup || "")
                if (!p.startsWith("applet:")) return false
                return Theme.ilotAppletCornerFor(p.slice(7)) === modelData.id
            }
            property bool etendu: false

            onPopupDansCeCoinChanged: {
                if (popupDansCeCoin) {
                    timerReplier.stop()
                    etendu = true
                } else if (!survol.hovered) {
                    timerReplier.restart()
                }
            }

            screen: root.ecranPrincipal
            visible: Theme.barStyle === "island" && applets.length > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "shell-ilot-coin-" + modelData.id

            anchors {
                top: modelData.top
                bottom: modelData.bottom
                left: !coinWin.ancreADroite
                right: coinWin.ancreADroite
            }
            margins {
                top: modelData.top ? Theme.gutterV : 0
                bottom: modelData.bottom ? Theme.gutterV : 0
                left: {
                    if (coinWin.ancreADroite) return 0
                    if (coinWin.groupes) {
                        return modelData.top
                            ? Math.round((coinWin.ecranW + ShellState.ilotWidth) / 2 + 10)
                            : Math.round(coinWin.ecranW / 2 + 6)
                    }
                    return Theme.gutterH
                }
                right: {
                    if (!coinWin.ancreADroite) return 0
                    if (coinWin.groupes) {
                        return modelData.top
                            ? Math.round((coinWin.ecranW + ShellState.ilotWidth) / 2 + 10)
                            : Math.round(coinWin.ecranW / 2 + 6)
                    }
                    return Theme.gutterH
                }
            }

            // Taille de fenêtre constante : évite la réallocation du buffer Wayland
            // à chaque image pendant l'animation de déploiement.
            implicitWidth: coinWin.largeurEtendue
            implicitHeight: Theme.barHeight

            Region {
                id: masqueSaisie
                item: pilule
            }
            mask: masqueSaisie

            Timer {
                id: timerReplier
                interval: 220
                repeat: false
                onTriggered: {
                    if (!survol.hovered && !coinWin.popupDansCeCoin) coinWin.etendu = false
                }
            }

            Item {
                id: pilule
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: coinWin.ancreADroite ? undefined : parent.left
                anchors.right: coinWin.ancreADroite ? parent.right : undefined
                width: coinWin.etendu ? coinWin.largeurEtendue : Theme.barHeight
                clip: true

                Behavior on width {
                    NumberAnimation {
                        duration: Math.max(180, Theme.panelAnimDuration)
                        easing.type: Easing.OutCubic
                    }
                }

                SurfaceFloutee {
                    anchors.fill: parent
                    rayon: coinWin.etendu ? Theme.pillRadius : Math.round(Theme.barHeight / 2)
                    Behavior on rayon {
                        NumberAnimation {
                            duration: Math.max(160, Theme.panelAnimDuration)
                            easing.type: Easing.OutCubic
                        }
                    }
                    teinte: Theme.barBg
                    bordureCouleur: Theme.accent
                    bordureLargeur: Theme.barBorder ? 1 : 0
                    actif: false
                }

                // Icône condensée en cercle au repos
                Item {
                    anchors.centerIn: parent
                    width: Theme.barHeight
                    height: Theme.barHeight
                    opacity: coinWin.etendu ? 0.0 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    IconSvg {
                        anchors.centerIn: parent
                        visible: coinWin.estSvg
                        nom: coinWin.estSvg ? coinWin.premiereIcone : ""
                        size: Theme.iconSm
                        couleur: Theme.fg
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !coinWin.estSvg
                        glyph: coinWin.premiereIcone
                        size: Theme.iconSm
                        color: Theme.fg
                    }
                }

                // Contenu complet au survol (toujours monté pour garder largeurEtendue stable)
                AppletRow {
                    id: rangee
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    directModel: coinWin.applets
                    opacity: coinWin.etendu ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                HoverHandler {
                    id: survol
                    onHoveredChanged: {
                        if (hovered) {
                            timerReplier.stop()
                            coinWin.etendu = true
                        } else {
                            timerReplier.restart()
                        }
                    }
                }
            }
        }
    }
}
