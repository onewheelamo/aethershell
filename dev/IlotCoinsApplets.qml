import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

// APPLETS SORTIS DE L'ÎLOT : un rond par applet (ordonné via ‹/› dans
// OngletIlot), de plus en plus petit par cran de 25 % (min 50 %) à mesure
// qu'on s'éloigne de l'îlot, et qui s'étend individuellement au survol.
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
    readonly property var iconesDefaut: ({
        "reseau": "wifi",
        "systray": "widgets",
        "nuit": "weather-night",
        "luminosite": "brightness",
        "batterie": "battery",
        "minimise": "monitor",
        "volume": "volume",
        "notifications": "bell",
        "maj": "download",
        "todo": "check",
        "meteo": "weather-cloud",
        "presse-papiers": "clipboard",
        "usb": "usb",
        "systeme": "cpu",
        "disques": "disque",
        "homelab": "speedometer",
        "comptes": "wallet",
        "hermes": "robot",
        "flotte": "rocket"
    })

    function iconePour(applet) {
        if (!applet) return "widgets"
        const ic = String(applet.icone || "")
        if (ic !== "") return ic
        return root.iconesDefaut[String(applet.id || "")] || "widgets"
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
            readonly property bool groupes: Theme.ilotCoinsGroupes
            readonly property bool ancreADroite: (groupes && modelData.left) || (!groupes && modelData.right)
            readonly property int ecranW: screen ? screen.width : 1920
            readonly property int espacement: 6
            readonly property int margeH: Math.max(6, Theme.gutterH)
            // Largeur au repos calculée de façon synchrone dès la création de la
            // fenêtre (évite que Hyprland ne mappe la surface à 28 px avant le Repeater).
            readonly property real largeurRepos: {
                const n = applets.length
                if (n <= 0) return Theme.barHeight
                let total = (n - 1) * espacement
                for (let i = 0; i < n; ++i) {
                    const dist = ancreADroite ? Math.max(0, n - 1 - i) : i
                    const ratio = Math.max(0.50, 1.0 - dist * 0.25)
                    total += Math.max(12, Math.round(Theme.barHeight * ratio))
                }
                return Math.max(Theme.barHeight, total)
            }
            // Largeur de fenêtre stable suffisante pour éviter toute réallocation
            // du buffer Wayland pendant l'animation d'extension au survol.
            readonly property real largeurSurface: Math.max(
                Theme.barHeight,
                applets.length * 360 + Math.max(0, applets.length - 1) * espacement
            )

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
                    return coinWin.margeH
                }
                right: {
                    if (!coinWin.ancreADroite) return 0
                    if (coinWin.groupes) {
                        return modelData.top
                            ? Math.round((coinWin.ecranW + ShellState.ilotWidth) / 2 + 10)
                            : Math.round(coinWin.ecranW / 2 + 6)
                    }
                    return coinWin.margeH
                }
            }

            // Taille constante de la surface Wayland + masque dynamique sur rangeeRonds :
            // zéro réallocation Wayland et zéro saut visuel à la rétractation.
            implicitWidth: coinWin.largeurSurface
            implicitHeight: Theme.barHeight

            mask: Region {
                item: rangeeRonds
            }

            Item {
                id: conteneur
                anchors.fill: parent

                Row {
                    id: rangeeRonds
                    x: coinWin.ancreADroite ? (conteneur.width - width) : 0
                    height: conteneur.height
                    spacing: coinWin.espacement

                Repeater {
                    model: coinWin.applets

                    delegate: Item {
                        id: bulle
                        required property var modelData
                        required property int index

                        readonly property int distIdx: coinWin.ancreADroite
                            ? Math.max(0, coinWin.applets.length - 1 - index)
                            : index
                        readonly property real ratio: Math.max(0.50, 1.0 - distIdx * 0.25)
                        readonly property int diametre: Math.max(12, Math.round(Theme.barHeight * ratio))
                        readonly property string icone: root.iconePour(modelData)
                        readonly property bool estSvg: root.svgIcones.indexOf(icone) >= 0
                        readonly property bool popupOuvert: Theme.activePopup === ("applet:" + String(modelData.id || ""))
                        readonly property real largeurEtendue: Math.max(Theme.barHeight, itemApplet.implicitWidth + Theme.padH * 2 + 4)
                        property bool etendu: false

                        onPopupOuvertChanged: {
                            if (popupOuvert) {
                                timerReplier.stop()
                                etendu = true
                            } else if (!survol.hovered) {
                                timerReplier.restart()
                            }
                        }

                        anchors.verticalCenter: parent.verticalCenter
                        width: etendu ? largeurEtendue : diametre
                        height: etendu ? Theme.barHeight : diametre
                        clip: true

                        Behavior on width {
                            NumberAnimation { duration: Math.max(180, Theme.panelAnimDuration); easing.type: Easing.OutCubic }
                        }
                        Behavior on height {
                            NumberAnimation { duration: Math.max(160, Theme.panelAnimDuration); easing.type: Easing.OutCubic }
                        }

                        Timer {
                            id: timerReplier
                            interval: 220
                            repeat: false
                            onTriggered: {
                                if (!survol.hovered && !bulle.popupOuvert) bulle.etendu = false
                            }
                        }

                        SurfaceFloutee {
                            anchors.fill: parent
                            rayon: bulle.etendu ? Theme.pillRadius : Math.round(bulle.diametre / 2)
                            Behavior on rayon {
                                NumberAnimation { duration: Math.max(160, Theme.panelAnimDuration); easing.type: Easing.OutCubic }
                            }
                            teinte: Theme.barBg
                            bordureCouleur: Theme.accent
                            bordureLargeur: Theme.barBorder ? 1 : 0
                            actif: false
                        }

                        // Icône condensée dans le rond au repos
                        Item {
                            anchors.centerIn: parent
                            width: bulle.diametre
                            height: bulle.diametre
                            opacity: bulle.etendu ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            IconSvg {
                                anchors.centerIn: parent
                                visible: bulle.estSvg
                                nom: bulle.estSvg ? bulle.icone : ""
                                size: Math.max(9, Math.round(Theme.iconSm * bulle.ratio))
                                couleur: Theme.fg
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: !bulle.estSvg
                                glyph: bulle.icone
                                size: Math.max(9, Math.round(Theme.iconSm * bulle.ratio))
                                color: Theme.fg
                            }
                        }

                        // Applet complet au survol (toujours monté pour garder largeurEtendue stable)
                        Applet {
                            id: itemApplet
                            anchors.centerIn: parent
                            applet: bulle.modelData
                            opacity: bulle.etendu ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }

                        HoverHandler {
                            id: survol
                            onHoveredChanged: {
                                if (hovered) {
                                    timerReplier.stop()
                                    bulle.etendu = true
                                } else {
                                    timerReplier.restart()
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
