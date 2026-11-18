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
    readonly property var _shellState: ShellState
    readonly property var _systemServices: SystemServices

    // Transitions de fond d'écran par shader (inspiré de diegoMalagrida/pocket-dots)
    WallpaperFx { id: wallpaperFx }

    // Fond de bureau en profondeur (parallaxe au changement de bureau). Déclaré
    // ici mais inerte tant que Theme.depthWallpaper est faux.
    FondProfondeur {
        id: fondProfondeur
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
        // La surface doit contenir la barre **et** sa marge extérieure, sinon la
        // pilule est rognée par le bas de la surface dès que la marge dépasse.
        // Les deux constantes valaient pour une marge de 8 px (8 + 6 et 8 + 2) :
        // elles suivent la marge **verticale** (`bar_gaps_out_v`) — le haut de
        // l'écran n'a que faire de la marge latérale.
        readonly property bool islandTallSurface: Theme.barStyle === "island"
            && (Theme.islandPanelOpen || (dynamicIslandLoader.item && dynamicIslandLoader.item.height > Theme.barHeight + 2))
        implicitHeight: (islandTallSurface ? 420 : barContainer.height) + Theme.gutterV + 6
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: Theme.barHeight + Theme.gutterV + 2
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        // Le panneau réseau est celui de l'applet « reseau » depuis la mise en
        // modularité : c'est sa clé qu'il faut reconnaître, la saisie du mot de
        // passe Wi-Fi y a besoin du clavier.
        WlrLayershell.keyboardFocus: (Theme.activePopup === "applet:reseau"
                                      || Theme.activePopup === "calendar"
                                      || (Theme.barStyle === "island" && (Theme.islandPanelOpen || Theme.wallpaperPickerOpen || Theme.themePickerOpen || Theme.islandLauncherOpen || Theme.islandNotesOpen || Theme.islandLiveActivityOpen)))
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-bar"

        Region {
            id: islandInputMask
            item: dynamicIslandLoader.item
        }
        mask: (Theme.barStyle === "island" && dynamicIslandLoader.item) ? islandInputMask : null

        Item {
            id: barContainer
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: Theme.gutterV
                leftMargin: Theme.gutterH
                rightMargin: Theme.gutterH
            }
            height: Theme.barHeight
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // 5a : surface unique derrière les trois groupes
            SurfaceFloutee {
                id: capsuleBg
                visible: Theme.barStyle !== "island" && Theme.barMerged && !Theme.barGapsTransparent
                anchors.fill: parent
                rayon: Theme.pillRadius
                teinte: Theme.barBg
                bordureCouleur: Theme.accent
                bordureLargeur: Theme.barBorder ? 1 : 0
            }

            // 5c : capsule découpée — option « espaces entre les îlots en
            // transparence » (Theme.barGapsTransparent, clé bar_gaps_transparent).
            SurfaceFloutee {
                id: zoneGauche
                visible: Theme.barStyle !== "island" && Theme.barMerged && Theme.barGapsTransparent
                x: 0
                width: Math.max(1, leftLoader.x + leftLoader.width)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                rayon: Theme.pillRadius
                teinte: Theme.barBg
                bordureCouleur: Theme.accent
                bordureLargeur: Theme.barBorder ? 1 : 0
            }

            SurfaceFloutee {
                id: zoneCentre
                visible: Theme.barStyle !== "island" && Theme.barMerged && Theme.barGapsTransparent
                x: centerLoader.x
                width: Math.max(1, centerLoader.width)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                rayon: Theme.pillRadius
                teinte: Theme.barBg
                bordureCouleur: Theme.accent
                bordureLargeur: Theme.barBorder ? 1 : 0
            }

            SurfaceFloutee {
                id: zoneDroite
                visible: Theme.barStyle !== "island" && Theme.barMerged && Theme.barGapsTransparent
                x: rightLoader.x
                width: Math.max(1, parent.width - rightLoader.x)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                rayon: Theme.pillRadius
                teinte: Theme.barBg
                bordureCouleur: Theme.accent
                bordureLargeur: Theme.barBorder ? 1 : 0
            }

            // Les deux espaces transparents, en tant que régions. Rien n'y est
            // dessiné en propre : ils portent x/width/height pour que les
            // animations s'y ancrent (ids volontairement stables).
            Item {
                id: slotGauche
                x: (Theme.barStyle === "island" && dynamicIslandLoader.item)
                    ? 0
                    : zoneGauche.x + zoneGauche.width
                width: (Theme.barStyle === "island" && dynamicIslandLoader.item)
                    ? Math.max(0, dynamicIslandLoader.x)
                    : Math.max(0, zoneCentre.x - x)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
            }

            Item {
                id: slotDroit
                x: (Theme.barStyle === "island" && dynamicIslandLoader.item)
                    ? dynamicIslandLoader.x + dynamicIslandLoader.width
                    : zoneCentre.x + zoneCentre.width
                width: (Theme.barStyle === "island" && dynamicIslandLoader.item)
                    ? Math.max(0, barContainer.width - x)
                    : Math.max(0, zoneDroite.x - x)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
            }

            // Visualiseur audio : un par espace, de part et d'autre de l'îlot
            // central. Ce n'est pas un applet plaçable — sa position *est* la
            // définition de l'espace transparent, donc il n'apparaît pas dans
            // les rangées d'applets et le registre ne le place jamais.
            Visualiseur {
                anchors.fill: slotGauche
                barre: "haut"
            }

            Visualiseur {
                anchors.fill: slotDroit
                barre: "haut"
            }

            // La barre avale les clics, zones peintes comme espaces vides : un
            // clic dans une transparence ne doit pas traverser jusqu'à la fenêtre
            // d'en dessous. Déclaré avant les îlots, donc dessous.
            MouseArea {
                anchors.fill: parent
                enabled: Theme.barStyle !== "island" && Theme.barMerged
            }

            // LEFT ISLAND: Launcher + Workspaces
            Loader {
                id: leftLoader
                visible: Theme.barStyle !== "island"
                active: Theme.barStyle !== "island"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                source: "island_left.qml"
            }

            // CENTER ISLAND: Clock, Date, Hover Weather, Calendar & Config Trigger
            Loader {
                id: centerLoader
                visible: Theme.barStyle !== "island"
                active: Theme.barStyle !== "island"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                source: "island_center.qml"
            }

            // RIGHT ISLAND: Systray, System Controls, Network & Power Menu
            Loader {
                id: rightLoader
                visible: Theme.barStyle !== "island"
                active: Theme.barStyle !== "island"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                source: "island_right.qml"
            }

            // DYNAMIC ISLAND: Îlot central dynamique unique (mode island)
            Loader {
                id: dynamicIslandLoader
                visible: Theme.barStyle === "island"
                active: Theme.barStyle === "island"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                source: "DynamicIsland.qml"
            }

            // Séparateurs de groupes : 9 % de la couleur de texte, 1 px.
            //
            // Placés à la moitié du padding de l'île, **vers l'intérieur**, et non
            // dehors : une valeur coupée (un titre de morceau qui défile) laissait
            // sinon une bande vide entre le dernier glyphe et le trait, et la
            // coupure se lisait comme un manque de place plutôt que comme la fin
            // du groupe. Le trait colle maintenant à l'endroit où le texte
            // disparaît.
            //
            // En mode « espaces transparents », le vide sépare déjà les zones :
            // le trait flotterait dans la transparence, il est masqué.
            Rectangle {
                visible: Theme.barStyle !== "island" && Theme.barMerged && !Theme.barGapsTransparent
                width: 1
                height: Theme.barHeight * 0.4
                x: leftLoader.x + leftLoader.width - Math.round(Theme.padH / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.09
            }
            Rectangle {
                visible: Theme.barStyle !== "island" && Theme.barMerged && !Theme.barGapsTransparent
                width: 1
                height: Theme.barHeight * 0.4
                x: rightLoader.x + Math.round(Theme.padH / 2) - 1
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.09
            }
        }
    }

    // Service permanent de notifications (D-Bus, toasts, historique, crochets IPC),
    // actif quel que soit le style de barre (classic ou island).
    NotifService {
        id: notifService
        anchorItem: barContainer
    }

    // OSD overlay (volume / brightness): temporary centered pill, auto-hides
    // En mode island, l'OSD est directement projeté dans l'îlot central
    PanelWindow {
        id: osdWindow
        screen: topBarWindow.screen
        visible: (Theme.barStyle !== "island") && (ShellState.osdVisible || osdBox.opacity > 0)
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
            opacity: ShellState.osdVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Row {
                anchors.centerIn: parent
                spacing: 14

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: ShellState.osdGlyph
                    size: Theme.textXxl
                    color: Theme.accent
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200
                    spacing: 6
                    Text {
                        text: ShellState.osdLabel
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                    }
                    Rectangle {
                        width: parent.width
                        height: 2
                        radius: 1
                        color: Theme.surfaceVariant
                        Rectangle {
                            width: parent.width * (ShellState.osdValue / 100)
                            height: parent.height
                            radius: 1
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ShellState.osdPercent
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }
            }
        }
    }

    // Floating Configuration Panel Window (couche Top pour laisser passer les boîtes modales polkit)
    FullscreenOverlay {
        id: configOverlayWindow
        property bool charge: false
        screen: topBarWindow.screen
        open: Theme.configPanelVisible && !Theme.configPanelYieldFocus
        layerLevel: WlrLayer.Top
        focusMode: WlrKeyboardFocus.OnDemand
        namespaceName: "shell-config"
        backdropClose: !Theme.configPanelYieldFocus
        fillLoader: false
        loaderWidth: 740
        loaderHeight: Math.min(height - Theme.barHeight - Theme.gutterV * 4, 900)
        loaderActive: charge
        loaderSource: "config_panel.qml"
        onCloseRequested: Theme.configPanelVisible = false

        Connections {
            target: Theme
            function onConfigPanelVisibleChanged() {
                if (Theme.configPanelVisible) configOverlayWindow.charge = true
            }
        }
    }

    MasqueParallaxe {
        screen: topBarWindow.screen
    }

    // Spotlight Pill: bottom-centre launcher (remplace fuzzel)
    FullscreenOverlay {
        id: spotlightWindow
        property bool loaded: false
        screen: topBarWindow.screen
        open: Theme.spotlightVisible
        aboveWindows: true
        namespaceName: "shell-spotlight"
        loaderActive: loaded
        loaderSource: "spotlight.qml"
        onCloseRequested: {
            if (Date.now() - Theme.spotlightOpenedAt > 300)
                Theme.spotlightVisible = false
        }

        Connections {
            target: Theme
            function onSpotlightVisibleChanged() {
                if (Theme.spotlightVisible) spotlightWindow.loaded = true
            }
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
        visible: !Theme.spotlightVisible && Theme.barStyle !== "island"

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
        // La barre occupe y (marge)..(marge + hauteur) : une capsule en haut
        // commence une marge verticale plus bas.
        margins.top: atTop ? Theme.barHeight + Theme.gutterV * 2 : 0
        // Barre du bas affichée : la capsule remonte de 20 px pour ne pas s'y
        // coller. Les zones réservées ne la décalent pas — elle est sur la couche
        // `Bottom`, positionnée par ses marges.
        margins.bottom: atTop ? 0
            : Theme.barHeight + Theme.gutterV + (Theme.barBottomVisible ? 20 : 0)
        margins.left: atCentre
            ? Math.round(((screen ? screen.width : 1920) - restWidth) / 2)
            : (atLeft ? Theme.gutterH
                      : (screen ? screen.width : 1920) - restWidth - Theme.gutterH)
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

    // ÉCRAN DES RACCOURCIS (SUPER + K)
    property var cheatsheetBinds: []

    Process {
        id: cheatsheetProc
        command: ["python3", Quickshell.shellPath("core/config_manager.py"), "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d && Array.isArray(d.binds))
                        root.cheatsheetBinds = d.binds
                } catch (e) {
                    console.warn("Cheatsheet: état illisible:", e)
                }
            }
        }
    }

    Connections {
        target: Theme
        function onCheatsheetVisibleChanged() {
            if (Theme.cheatsheetVisible)
                cheatsheetProc.running = true
        }
    }

    FullscreenOverlay {
        id: cheatsheetWindow
        screen: topBarWindow.screen
        open: Theme.cheatsheetVisible
        namespaceName: "shell-cheatsheet"
        escapeClose: true
        fillLoader: false
        loaderWidth: loaderItem ? loaderItem.implicitWidth : 0
        loaderHeight: loaderItem ? loaderItem.implicitHeight : 0
        loaderSource: Theme.cheatsheetVisible ? "Cheatsheet.qml" : ""
        onCloseRequested: Theme.cheatsheetVisible = false
        onContentLoaded: item => {
            item.binds = Qt.binding(function () { return root.cheatsheetBinds })
            item.surfaceColor = Qt.binding(function () { return Theme.surfaceBg })
        }
    }

    // WHICH-KEY PAR SUBMAP
    property var submapBinds: []

    Process {
        id: submapBindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const all = JSON.parse(text)
                    const cur = ShellState.activeSubmap
                    if (Array.isArray(all) && cur !== "") {
                        root.submapBinds = all.filter(b => b && String(b.submap || "") === cur)
                    } else {
                        root.submapBinds = []
                    }
                } catch (e) {
                    root.submapBinds = []
                }
            }
        }
    }

    Connections {
        target: ShellState
        function onActiveSubmapChanged() {
            if (ShellState.activeSubmap !== "") {
                if (!submapBindsProc.running) submapBindsProc.running = true
            } else {
                root.submapBinds = []
            }
        }
    }

    PanelWindow {
        id: submapWhichKeyWindow
        screen: topBarWindow.screen
        visible: ShellState.activeSubmap !== "" && root.submapBinds.length > 0
        anchors { bottom: true }
        margins.bottom: 24
        implicitWidth: whichKeyLoader.item ? whichKeyLoader.item.implicitWidth : 460
        implicitHeight: whichKeyLoader.item ? whichKeyLoader.item.implicitHeight : 140
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-whichkey"

        Loader {
            id: whichKeyLoader
            anchors.fill: parent
            source: (ShellState.activeSubmap !== "" && root.submapBinds.length > 0) ? "SubmapWhichKey.qml" : ""
            onLoaded: {
                if (!item) return
                item.submapName = Qt.binding(() => ShellState.activeSubmap)
                item.binds = Qt.binding(() => root.submapBinds)
            }
        }
    }

    // VUE D'ENSEMBLE DES FENÊTRES — MISSION CONTROL (SUPER + G)
    property var overviewClients: []

    Process {
        id: overviewClientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.overviewClients = Array.isArray(parsed) ? parsed : []
                } catch (e) {
                    root.overviewClients = []
                }
            }
        }
    }

    Connections {
        target: Theme
        function onOverviewVisibleChanged() {
            if (Theme.overviewVisible && !overviewClientsProc.running) {
                overviewClientsProc.running = true
            }
        }
    }

    FullscreenOverlay {
        id: overviewWindow
        screen: topBarWindow.screen
        open: Theme.overviewVisible
        namespaceName: "shell-overview"
        backdropClose: false
        loaderSource: Theme.overviewVisible ? "OverviewOverlay.qml" : ""
        onContentLoaded: item => {
            item.clients = Qt.binding(() => root.overviewClients)
            item.closeRequested.connect(() => { Theme.overviewVisible = false })
            item.refreshRequested.connect(() => {
                if (!overviewClientsProc.running) overviewClientsProc.running = true
            })
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // TIROIR DE L'HISTORIQUE DES NOTIFICATIONS — surface indépendante du panneau :
    // elle garde tout ce qui est arrivé, y compris ce qui a été effacé du panneau
    // ou fermé par l'application. Ouverture par l'icône de l'en-tête du panneau,
    // IPC shell toggleNotifHistory.
    // ────────────────────────────────────────────────────────────────────────
    NotifHistory {
        id: notifHistoryDrawer
        onCloseRequested: ShellState.notifHistoryVisible = false
    }

    // ────────────────────────────────────────────────────────────────────────
    // ASSISTANT DE PREMIER LANCEMENT — cinq pages (clavier, dossiers, programmes,
    // widgets, astuce), affichées une seule fois. La surface et son état vivent
    // dans first_run.qml ; elle ne s'affiche que tant que `first_run_completed`
    // est faux dans style_vars.json.
    // ────────────────────────────────────────────────────────────────────────
    Loader {
        id: assistantPremierLancement
        active: !Theme.firstRunCompleted || Theme.showKeyboardOnboarding
        source: "first_run.qml"
    }

    ScreenshotOverlay {
        targetScreen: topBarWindow.screen
    }

    DesktopWidgetsLayer {
        targetScreen: topBarWindow.screen
    }

    // Barres supplémentaires : bas et côtés. Elles ne s'affichent que si elles
    // sont allumées **et** portent un applet (voir bar_extra.qml).
    BarExtra {
        cote: "bas"
        screen: topBarWindow.screen
    }
    BarExtra {
        cote: "cote-gauche"
        screen: topBarWindow.screen
    }
    BarExtra {
        cote: "cote-droite"
        screen: topBarWindow.screen
    }
    // Masque de premier plan du fond (couche `bottom`) : déclaré en dernier
    // pour être empilé au-dessus des fenêtres de widgets, qui sont créées
    // plus haut dans ce fichier.
    CalqueProfondeur {
        id: calqueProfondeur
    }
}
