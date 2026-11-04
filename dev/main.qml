//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Racine du contenu : un Item, instancié par le Loader de shell.qml. Garder ici
// un ShellRoot créerait un ShellRoot imbriqué, et un ShellRoot à la place de ce
// Item n'est pas nécessaire (ShellRoot est optionnel).
Item {
    id: root

    property string pendingKbLayout: Theme.kbLayout || "fr"

    Process {
        id: applyKbProc
        stdout: StdioCollector {
            onStreamFinished: {
                Theme.showKeyboardOnboarding = false
                Theme.firstRunCompleted = true
            }
        }
    }

    function applyInitialKeyboard(layoutCode) {
        applyKbProc.command = [
            "python3",
            Quickshell.shellPath("core/config_manager.py"),
            "kb_layout",
            layoutCode
        ]
        applyKbProc.running = true
    }

    // Top Bar Window hosting the 3 distinct islands (Left, Center, Right)
    PanelWindow {
        id: topBarWindow
        screen: {
            if (Theme.primaryMonitor && Quickshell.screens) {
                for (let i = 0; i < Quickshell.screens.length; i++) {
                    if (Quickshell.screens[i].name === Theme.primaryMonitor) {
                        return Quickshell.screens[i]
                    }
                }
            }
            return (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null
        }
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: barContainer.height + 14
        exclusionMode: ExclusionMode.Auto
        exclusiveZone: barContainer.height + 10
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: (Theme.activePopup === "wifi" || Theme.activePopup === "calendar")
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-bar"

        Item {
            id: barContainer
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: Theme.gutter
                leftMargin: Theme.gutter
                rightMargin: Theme.gutter
            }
            height: Theme.barHeight
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // 5a : surface unique derrière les trois groupes
            Rectangle {
                id: capsuleBg
                visible: Theme.barMerged
                anchors.fill: parent
                radius: Theme.pillRadius
                color: Theme.barBg
                border.color: Theme.accent
                border.width: 1

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }

                // Déclaré avant les îlots pour rester dessous.
                MouseArea {
                    anchors.fill: parent
                }
            }

            // LEFT ISLAND: Launcher + Workspaces
            Loader {
                id: leftLoader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                source: "island_left.qml"
            }

            // CENTER ISLAND: Clock, Date, Hover Weather, Calendar & Config Trigger
            Loader {
                id: centerLoader
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                source: "island_center.qml"
            }

            // RIGHT ISLAND: Systray, System Controls, Network & Power Menu
            Loader {
                id: rightLoader
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                source: "island_right.qml"
            }

            // Séparateurs de groupes : 6 % de la couleur de texte, 1 px
            Rectangle {
                visible: Theme.barMerged
                width: 1
                height: Theme.barHeight * 0.4
                x: leftLoader.x + leftLoader.width + Theme.gutter
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.09
            }
            Rectangle {
                visible: Theme.barMerged
                width: 1
                height: Theme.barHeight * 0.4
                x: rightLoader.x - Theme.gutter - 1
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.09
            }
        }
    }

    // OSD overlay (volume / brightness): temporary centered pill, auto-hides
    PanelWindow {
        id: osdWindow
        screen: topBarWindow.screen
        visible: Theme.osdVisible || osdBox.opacity > 0
        anchors {
            bottom: true
            left: true
            right: true
        }
        // PanelWindow anchors don't support margins: offset the pill inside instead
        implicitHeight: osdBox.height + osdBox.anchors.bottomMargin + 20
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        aboveWindows: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-osd"

        Rectangle {
            id: osdBox
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 90   // lift the pill above the bottom edge
            width: 300
            height: 56
            radius: Theme.globalRadius + 4
            color: Theme.surfaceBg
            border.color: Theme.accent
            border.width: 1
            opacity: Theme.osdVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                anchors.centerIn: parent
                spacing: 14

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Theme.osdKind === "brightness" ? "brightness"
                        : Theme.osdKind === "mute" ? "volume-off"
                        : (Theme.osdValue <= 0 ? "mute" : Theme.osdValue < 50 ? "volume-medium" : "volume-high")
                    size: Theme.textXxl
                    color: Theme.accent
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    spacing: 6
                    Text {
                        text: Theme.osdKind === "brightness" ? "Luminosité"
                            : Theme.osdKind === "mute" ? "Micro coupé"
                            : (Theme.osdValue <= 0 ? "Volume coupé" : "Volume")
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                    }
                    Rectangle {
                        width: parent.width
                        height: 2
                        radius: 1
                        color: Theme.surfaceVariant
                        Rectangle {
                            width: parent.width * (Theme.osdValue / 100)
                            height: parent.height
                            radius: 1
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(Theme.osdValue) + "%"
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }
            }
        }
    }

    // Floating Configuration Panel Overlay Window
    PanelWindow {
        id: configOverlayWindow
        screen: topBarWindow.screen
        visible: Theme.configPanelVisible
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        aboveWindows: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Theme.configPanelVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-config"

        MouseArea {
            anchors.fill: parent
            onClicked: Theme.configPanelVisible = false
        }

        Loader {
            id: configLoader
            anchors.centerIn: parent
            width: 620
            // Hauteur bornée : le panneau flotte au centre au lieu de coller à
            // la barre et au bas de l'écran.
            height: Math.min(parent.height - Theme.barHeight - Theme.gutter * 4, 900)
            source: "config_panel.qml"
        }
    }

    // Spotlight Pill: bottom-centre launcher (remplace fuzzel)
    PanelWindow {
        id: spotlightWindow
        screen: topBarWindow.screen
        visible: Theme.spotlightVisible
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        aboveWindows: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Theme.spotlightVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-spotlight"

        // Un clic hors de la pilule ferme la surface — sauf juste après
        // l'ouverture, où le relâchement du clic d'invocation arrive ici.
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (Date.now() - Theme.spotlightOpenedAt > 300)
                    Theme.spotlightVisible = false
            }
        }

        Loader {
            id: spotlightLoader
            anchors.fill: parent
            source: "spotlight.qml"
        }
    }


    // Lanceur au repos : la même capsule, toujours posée en bas au centre, à 0,2.
    // Fenêtre étroite (720 px) et non plein écran : hors de la capsule les clics
    // continuent d'aller à la fenêtre en dessous. Un clic dessus ouvre la pilule.
    // Couche `Bottom` : la capsule passe derrière les fenêtres Hyprland et ne
    // réapparaît que sur un bureau nu (workspace vide, fenêtre déplacée).
    PanelWindow {
        id: spotlightRestWindow
        screen: topBarWindow.screen
        visible: !Theme.spotlightVisible

        // Six positions prédéfinies (PROPOSITION_widgets.md §3.5) : bord haut ou
        // bas, centre ou tiers gauche/droit — jamais une position libre.
        // Largeur 600 : elle tient dans un tiers (640), là où 720 débordait.
        readonly property int restWidth: 600
        readonly property string restPos: Theme.launcherPosition
        readonly property bool atTop: restPos.indexOf("haut") === 0
        readonly property bool atLeft: restPos.indexOf("gauche") >= 0
        readonly property bool atCentre: restPos.indexOf("centre") >= 0

        anchors {
            top: atTop
            bottom: !atTop
            left: true
        }
        // La barre occupe y 8..44 : une capsule en haut commence 8 px plus bas.
        margins.top: atTop ? Theme.barHeight + Theme.gutter * 2 : 0
        margins.bottom: atTop ? 0 : Theme.barHeight + Theme.gutter
        margins.left: atCentre
            ? Math.round(((screen ? screen.width : 1920) - restWidth) / 2)
            : (atLeft ? Theme.gutter
                      : (screen ? screen.width : 1920) - restWidth - Theme.gutter)
        implicitWidth: restWidth
        implicitHeight: 62
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Couche `Bottom` : la capsule reste en permanence sous les fenêtres Hyprland,
        // sur le fond d'écran, et reçoit les clics dès que la zone est découverte.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-spotlight-rest"

        Rectangle {
            anchors.fill: parent
            radius: 26
            color: Theme.spotlightRestBg
            border.color: Qt.alpha(Theme.accent, 0.16)
            border.width: 1

            Icon {
                id: restLens
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                glyph: "search"
                size: Theme.iconMd
                color: Theme.accent
                opacityLevel: 0.35
            }

            Text {
                anchors.left: restLens.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Rechercher une application…"
                color: Qt.alpha(Theme.fg, 0.30)
                font.pixelSize: Theme.textLg
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.spotlightVisible = true
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // WIDGETS DE BUREAU — une surface layer par entrée de core/widgets.json.
    // Couche `Bottom`, jamais le clavier : le widget vit derrière les fenêtres et
    // n'est cliquable que là où rien ne le couvre. Sa taille suit son contenu :
    // une surface layer consomme les clics sur toute son étendue, donc une
    // fenêtre plus grande que le widget rendrait le bureau incliquable.
    // ────────────────────────────────────────────────────────────────────────
    Variants {
        model: Theme.widgets

        PanelWindow {
            id: widgetWindow
            required property var modelData

            readonly property var w: modelData || ({})

            screen: topBarWindow.screen
            visible: w.enabled !== false
                     && (Number(w.workspace) === 0
                         || (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === Number(w.workspace)))

            anchors { top: true; left: true }
            margins.top: Number(w.y) || 0
            margins.left: Number(w.x) || 0
            // La carte : transparence propre à chaque widget (0,35 par défaut,
            // donc au-dessus du seuil de flou 0,30). Le padding fait partie de
            // la surface : il consomme les clics, il reste donc serré (18 px).
            readonly property int pad: 18
            readonly property real cardOpacity: Number(w.opacity) > 0 ? Number(w.opacity) : 0.35
            implicitWidth: widgetLoader.implicitWidth + pad * 2
            implicitHeight: widgetLoader.implicitHeight + pad * 2
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Un namespace par widget : c'est lui qui porte la règle de flou
            // (voir build_shell_blur_block dans core/config_manager.py).
            WlrLayershell.namespace: "shell-widget-" + (w.id || "x")

            Rectangle {
                anchors.fill: parent
                radius: Theme.globalRadius
                color: Qt.alpha(Theme.surface, widgetWindow.cardOpacity)
                border.width: 1
                border.color: Qt.alpha(Theme.accent, 0.16)

                Loader {
                    id: widgetLoader
                    // Surtout pas `anchors.fill: parent` : le Loader imposerait sa
                    // taille (1×1 au premier paint) au widget, qui resterait écrasé
                    // (pitfall 68). Ici le contenu garde sa taille implicite et la
                    // fenêtre suit.
                    anchors.centerIn: parent
                    source: widgetWindow.w.type ? ("widgets/" + widgetWindow.w.type + ".qml") : ""
                    onLoaded: {
                        if (item) {
                            item.options = widgetWindow.w.options || ({})
                            item.widgetId = widgetWindow.w.id || ""
                        }
                    }
                }
            }
        }
    }

    // First-Run Keyboard Layout Selection Window (100% Mouse Operated)
    PanelWindow {
        id: firstRunOverlayWindow
        screen: topBarWindow.screen
        visible: Theme.showKeyboardOnboarding
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Qt.alpha("#000000", 0.55)
        aboveWindows: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-onboarding"

        Rectangle {
            id: onboardingCard
            width: 540
            height: onboardingCol.implicitHeight + 44
            anchors.centerIn: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 2

            Column {
                id: onboardingCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 22
                spacing: 16

                Text {
                    text: "⌨ Premier Lancement — Disposition du Clavier"
                    color: Theme.accent
                    font.pixelSize: Theme.textXl
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: "Sélectionnez la langue de votre clavier à la souris (Français AZERTY par défaut).\nCe choix configure Hyprland (input.lua) et adapte automatiquement la nomenclature des raccourcis Workspaces 1 à 5 dans binds.lua pour éviter tout conflit."
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    wrapMode: Text.WordWrap
                }

                // Mouse-selectable keyboard layout cards
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    Repeater {
                        model: [
                            { code: "fr", title: "🇫🇷 Français (AZERTY)", sub: "Défaut — Workspaces : &  é  \"  '  (" },
                            { code: "us", title: "🇺🇸 English (US QWERTY)", sub: "Workspaces : 1  2  3  4  5" },
                            { code: "be", title: "🇧🇪 Belge (AZERTY)", sub: "Workspaces : &  é  \"  '  (" },
                            { code: "gb", title: "🇬🇧 English (UK QWERTY)", sub: "Workspaces : 1  2  3  4  5" },
                            { code: "de", title: "🇩🇪 Deutsch (QWERTZ)", sub: "Workspaces : 1  2  3  4  5" },
                            { code: "ch", title: "🇨🇭 Suisse (QWERTZ)", sub: "Workspaces : 1  2  3  4  5" }
                        ]

                        Rectangle {
                            id: kbCard
                            required property var modelData
                            readonly property bool selected: root.pendingKbLayout === modelData.code
                            width: (parent.width - 12) / 2
                            height: 58
                            radius: Theme.globalRadius
                            color: selected
                                ? Qt.alpha(Theme.accent, 0.25)
                                : (kbCardMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55))
                            border.color: selected ? Theme.accent : Theme.surfaceVariant
                            border.width: selected ? 2 : 1

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    text: kbCard.modelData.title
                                    color: kbCard.selected ? Theme.accent : Theme.fg
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }

                                Text {
                                    text: kbCard.modelData.sub
                                    color: Qt.alpha(Theme.fg, 0.75)
                                    font.pixelSize: Theme.textXs
                                }
                            }

                            MouseArea {
                                id: kbCardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pendingKbLayout = kbCard.modelData.code
                            }
                        }
                    }
                }

                // Summary box showing exact binds.lua nomenclature
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: Theme.globalRadius
                    color: Theme.bg
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: (root.pendingKbLayout === "fr" || root.pendingKbLayout === "be")
                            ? "Nomenclature binds.lua : ampersand, eacute, quotedbl, apostrophe, parenleft"
                            : "Nomenclature binds.lua : 1, 2, 3, 4, 5 (aucun conflit QWERTY)"
                        color: Theme.info
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }
                }

                // Confirm & Apply button (Mouse only)
                Rectangle {
                    width: parent.width
                    height: 40
                    radius: Theme.globalRadius
                    color: confirmKbMa.containsMouse ? Theme.accentMuted : Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "✓ Valider la disposition « " + root.pendingKbLayout.toUpperCase() + " » et Appliquer"
                        color: Theme.bg
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    MouseArea {
                        id: confirmKbMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyInitialKeyboard(root.pendingKbLayout)
                    }
                }
            }
        }
    }
}
