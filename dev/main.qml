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

    // Fond de bureau en profondeur (parallaxe au changement de bureau). Déclaré
    // ici mais inerte tant que Theme.depthWallpaper est faux.
    FondProfondeur {
        id: fondProfondeur
    }


    // ────────────────────────────────────────────────────────────────────────
    // MODE PLACEMENT D'UN WIDGET (SUPER + clic sur le widget)
    // ────────────────────────────────────────────────────────────────────────
    // Le glisser direct est impossible : sur une petite surface layer, les
    // mouvements ne sont pas délivrés au client et le geste meurt dès que le
    // pointeur sort du rectangle (mesuré : press et release arrivent, pas les
    // déplacements). On passe donc par une surface plein écran qui reçoit le
    // pointeur partout : le widget suit le curseur en aperçu, et un clic le pose.
    property var placingWindow: null
    property real placingX: 0
    property real placingY: 0
    property real placingGrabX: 0
    property real placingGrabY: 0
    property bool placingArmed: false
    readonly property bool placing: placingWindow !== null

    // Fenêtres des widgets, pour retrouver laquelle est sous le curseur quand le
    // déclencheur vient de Hyprland (qui, lui, connaît le modificateur).
    property var widgetWindows: []

    // Menu du widget (clic milieu) : quelle entrée, et où poser la fenêtre.
    property string menuWidgetId: ""
    property real menuWidgetX: 0
    property real menuWidgetY: 0
    readonly property var menuWidget: {
        if (menuWidgetId === "") return ({})
        const l = Theme.widgets || []
        for (let i = 0; i < l.length; ++i)
            if (String(l[i].id) === menuWidgetId) return l[i]
        return ({})
    }

    // Un widget peut viser plusieurs bureaux (`workspaces: [1,3]`) ; 0 = tous.
    // `workspace` reste la forme historique : un widget écrit avant la liste
    // continue de s'afficher au même endroit, sans migration de fichier.
    function widgetVisible(w) {
        if (!w || w.enabled === false) return false
        // Une liste venue du JSON reste un tableau JS, mais on la reconstruit
        // élément par élément : `.map` n'existe pas si la valeur arrive en
        // QVariantList, et la liaison échouait alors en silence (widget invisible
        // quel que soit le réglage).
        const brut = (w.workspaces && w.workspaces.length > 0)
            ? w.workspaces : [w.workspace]
        const liste = []
        for (let i = 0; i < brut.length; ++i) {
            const n = Number(brut[i])
            if (!isNaN(n)) liste.push(n)
        }
        if (liste.length === 0) return true
        if (liste.indexOf(0) >= 0) return true
        const ici = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1
        return liste.indexOf(ici) >= 0
    }

    // Appelé par `quickshell ipc call shell placeWidget` (bind SUPER + SHIFT + clic).
    function startPlacementFromCursor() {
        if (placingWindow) { endPlacement(false); return }
        findWidgetProc.running = true
    }

    Process {
        id: findWidgetProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).trim().split(",")
                const cx = parseInt(parts[0], 10)
                const cy = parseInt(parts[1], 10)
                if (isNaN(cx) || isNaN(cy)) return
                for (let i = 0; i < root.widgetWindows.length; i++) {
                    const win = root.widgetWindows[i]
                    if (!win || !win.visible) continue
                    const wx = Number(win.w.x) || 0
                    const wy = Number(win.w.y) || 0
                    if (cx >= wx && cx <= wx + win.implicitWidth
                            && cy >= wy && cy <= wy + win.implicitHeight) {
                        root.beginPlacement(win, cx - wx, cy - wy)
                        return
                    }
                }
            }
        }
    }

    // Les deux crochets IPC du shell (placement d'un widget, lancement d'une
    // capture) : un seul gestionnaire, QML n'en accepte qu'un par objet.
    Component.onCompleted: {
        Theme.placeWidgetHook = function() { root.startPlacementFromCursor() }
        // Ouverture du menu d'un widget sans souris : l'IPC s'en sert, le clic
        // milieu passe par la même propriété d'état.
        Theme.widgetMenuHook = function(id) {
            // Un identifiant vide referme : c'est ce que fait l'IPC pour les tests,
            // et ça évite d'ajouter une seconde fonction au gestionnaire.
            if (String(id) === "") { root.menuWidgetId = ""; return }
            const l = Theme.widgets || []
            for (let i = 0; i < l.length; ++i) {
                if (String(l[i].id) !== String(id)) continue
                root.menuWidgetX = Number(l[i].x) || 0
                root.menuWidgetY = Number(l[i].y) || 0
                root.menuWidgetId = String(id)
                return
            }
        }
        Theme.captureHook = function(mode) { root.requestCapture(mode) }
    }

    // Changer de bureau referme le panneau ouvert. Le clic sur l'applet des
    // bureaux part de la barre, qui fait partie des fenêtres tenues par
    // l'attrapeur de focus : le grab ne se libérait donc pas, et le popup
    // restait affiché par-dessus le nouveau bureau — vu sur le panneau média.
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (Theme.activePopup !== "") Theme.activePopup = ""
        }
    }

    function beginPlacement(win, grabX, grabY) {
        placingWindow = win
        placingGrabX = grabX
        placingGrabY = grabY
        placingX = Number(win.w.x) || 0
        placingY = Number(win.w.y) || 0
        placingArmed = false
        placementArmTimer.restart()
    }

    function endPlacement(commit) {
        if (commit && placingWindow)
            moveWidget(placingWindow.w.id, Math.round(placingX), Math.round(placingY))
        placingWindow = null
    }

    // Le relâchement du clic qui a ouvert le mode ne doit pas poser le widget.
    Timer {
        id: placementArmTimer
        interval: 220
        onTriggered: root.placingArmed = true
    }

    // Certaines applications (ProtonVPN) ne se réenregistrent pas auprès d'un
    // nouveau StatusNotifierWatcher : après un redémarrage du shell leur icône
    // reste absente jusqu'au redémarrage de l'app. Ce gardien compare les services
    // SNI vivants à la liste du watcher et ré-enregistre les absents (une fois par
    // cycle, sans doublon). Il meurt avec le shell et se relance avec lui.
    Process {
        id: trayWatchdogProc
        running: true
        command: ["python3", Quickshell.shellPath("core/tray_watchdog.py"), "--interval", "10"]
    }

    // Mode nuit : la plage horaire s'applique **d'ici**, pas depuis l'applet
    // luminosité. Un minuteur posé dans un applet s'arrête avec lui, et la
    // modularisation permet de retirer cet applet : l'automatisme disparaissait
    // alors sans le moindre signe. `main.qml` est toujours monté, sur la tour
    // comme sur le portable, donc c'est le seul endroit qui garantit la règle.
    // `appliquer` est idempotent et ne fait rien tant que la plage est vide.
    Process {
        id: nuitApplyProc
        command: ["python3", Quickshell.shellPath("core/nuit_service.py"), "appliquer"]
    }
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (nuitApplyProc.running) return
            nuitApplyProc.running = true
        }
    }


    // Écrit la nouvelle position dans core/widgets.json (le shell la relira par
    // FileView : c'est le fichier qui fait foi, pas l'état local du glissement).
    Process {
        id: moveWidgetProc
    }

    function moveWidget(id, x, y) {
        if (!id) return
        moveWidgetProc.command = [
            "python3", Quickshell.shellPath("core/config_manager.py"),
            "widget_move", String(id), String(Math.round(x)), String(Math.round(y))
        ]
        moveWidgetProc.running = true
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
        // Le panneau réseau est celui de l'applet « reseau » depuis la mise en
        // modularité : c'est sa clé qu'il faut reconnaître, la saisie du mot de
        // passe Wi-Fi y a besoin du clavier.
        WlrLayershell.keyboardFocus: (Theme.activePopup === "applet:reseau"
                                      || Theme.activePopup === "calendar")
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
                visible: Theme.barMerged && !Theme.barGapsTransparent
                anchors.fill: parent
                radius: Theme.pillRadius
                color: Theme.barBg
                // Verre dépoli autonome : ne dessine rien tant que
                // Theme.shellFlouInterne vaut 0 (voir FlouFond.qml).
                FlouFond {
                    anchors.fill: parent
                    rayon: Theme.pillRadius
                    intensite: Theme.shellFlouInterne
                }
                border.color: Theme.accent
                border.width: Theme.barBorder ? 1 : 0

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
            }

            // 5c : capsule découpée — option « espaces entre les îlots en
            // transparence » (Theme.barGapsTransparent, clé bar_gaps_transparent).
            //
            // Le fond n'est peint que sous les trois zones ; les deux espaces
            // entre elles ne sont plus peints du tout. Transparent ne veut pas
            // dire flouté : l'alpha 0 tombe sous le seuil `ignore_alpha` de la
            // règle de flou de general.lua, donc le mur derrière s'y voit net.
            //
            // Ce n'est pas un retour aux trois îlots indépendants : un seul
            // conteneur, une seule mise en page, les mêmes ancres, et les deux
            // vides sont des régions nommées qui gardent leur géométrie
            // (slotGauche / slotDroit) — c'est là que se posera l'animation de
            // lecture média.
            //
            // L'arrondi est celui du panneau (global_radius, via pillRadius) sur
            // les bords extérieurs *et* intérieurs : les deux rives d'un espace
            // ont la même courbe, la barre ne se coupe pas à angle droit.
            Rectangle {
                id: zoneGauche
                visible: Theme.barMerged && Theme.barGapsTransparent
                x: 0
                width: Math.max(1, leftLoader.x + leftLoader.width)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                radius: Theme.pillRadius
                color: Theme.barBg
                FlouFond {
                    anchors.fill: parent
                    rayon: Theme.pillRadius
                    intensite: Theme.shellFlouInterne
                }
                border.color: Theme.accent
                border.width: Theme.barBorder ? 1 : 0

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
            }

            Rectangle {
                id: zoneCentre
                visible: Theme.barMerged && Theme.barGapsTransparent
                x: centerLoader.x
                width: Math.max(1, centerLoader.width)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                radius: Theme.pillRadius
                color: Theme.barBg
                FlouFond {
                    anchors.fill: parent
                    rayon: Theme.pillRadius
                    intensite: Theme.shellFlouInterne
                }
                border.color: Theme.accent
                border.width: Theme.barBorder ? 1 : 0

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
            }

            Rectangle {
                id: zoneDroite
                visible: Theme.barMerged && Theme.barGapsTransparent
                x: rightLoader.x
                width: Math.max(1, parent.width - rightLoader.x)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
                radius: Theme.pillRadius
                color: Theme.barBg
                FlouFond {
                    anchors.fill: parent
                    rayon: Theme.pillRadius
                    intensite: Theme.shellFlouInterne
                }
                border.color: Theme.accent
                border.width: Theme.barBorder ? 1 : 0

                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }
            }

            // Les deux espaces transparents, en tant que régions. Rien n'y est
            // dessiné en propre : ils portent x/width/height pour que les
            // animations s'y ancrent (ids volontairement stables).
            Item {
                id: slotGauche
                x: zoneGauche.x + zoneGauche.width
                width: Math.max(0, zoneCentre.x - x)
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.barHeight
            }

            Item {
                id: slotDroit
                x: zoneCentre.x + zoneCentre.width
                width: Math.max(0, zoneDroite.x - x)
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
                autorise: Theme.barGapsTransparent
            }

            Visualiseur {
                anchors.fill: slotDroit
                barre: "haut"
                autorise: Theme.barGapsTransparent
            }

            // La barre avale les clics, zones peintes comme espaces vides : un
            // clic dans une transparence ne doit pas traverser jusqu'à la fenêtre
            // d'en dessous. Déclaré avant les îlots, donc dessous.
            MouseArea {
                anchors.fill: parent
                enabled: Theme.barMerged
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
                visible: Theme.barMerged && !Theme.barGapsTransparent
                width: 1
                height: Theme.barHeight * 0.4
                x: leftLoader.x + leftLoader.width - Math.round(Theme.padH / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                opacity: 0.09
            }
            Rectangle {
                visible: Theme.barMerged && !Theme.barGapsTransparent
                width: 1
                height: Theme.barHeight * 0.4
                x: rightLoader.x + Math.round(Theme.padH / 2) - 1
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
        // Barre du bas affichée : la capsule remonte de 20 px pour ne pas s'y
        // coller. Les zones réservées ne la décalent pas — elle est sur la couche
        // `Bottom`, positionnée par ses marges.
        margins.bottom: atTop ? 0
            : Theme.barHeight + Theme.gutter + (Theme.barBottomVisible ? 20 : 0)
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
    // ÉCRAN DES RACCOURCIS (SUPER + K) — surface fixe, centrée, comme le panneau
    // de configuration. La liste vient de binds.lua (via config_manager.py state)
    // et ne retient que les binds qui portent une `description` : rien n'est
    // dupliqué ici, un raccourci ajouté dans le Lua apparaît tel quel.
    // ────────────────────────────────────────────────────────────────────────
    property var cheatsheetBinds: []

    Process {
        id: cheatsheetProc
        command: ["python3", Quickshell.shellPath("core/config_manager.py"), "state"]
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
            // Relire à chaque ouverture : un bind ajouté dans binds.lua apparaît
            // sans redémarrer la coquille.
            if (Theme.cheatsheetVisible)
                cheatsheetProc.running = true
        }
    }

    PanelWindow {
        id: cheatsheetWindow
        screen: topBarWindow.screen
        visible: Theme.cheatsheetVisible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusif tant qu'il est ouvert : sans ça Échap part à la fenêtre en
        // dessous et l'écran ne se ferme qu'au clic. La sortie est garantie par
        // le handler ci-dessous (piège classique : une surface qui avale le
        // clavier sans porte de sortie testée).
        WlrLayershell.keyboardFocus: Theme.cheatsheetVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-cheatsheet"

        Item {
            anchors.fill: parent
            focus: Theme.cheatsheetVisible
            Keys.onEscapePressed: Theme.cheatsheetVisible = false
        }

        // Fond cliquable : se referme comme le panneau.
        MouseArea {
            anchors.fill: parent
            onClicked: Theme.cheatsheetVisible = false
        }

        Loader {
            anchors.centerIn: parent
            source: Theme.cheatsheetVisible ? "Cheatsheet.qml" : ""
            onLoaded: {
                if (item) {
                    // Liaisons, pas des affectations : le Process peut répondre
                    // APRÈS le chargement du composant, et une affectation
                    // laisserait la liste vide pour toujours.
                    item.binds = Qt.binding(function () { return root.cheatsheetBinds })
                    item.surfaceColor = Qt.binding(function () {
                        return Qt.alpha(Theme.surface, Theme.cheatsheetOpacity)
                    })
                }
            }
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
        onCloseRequested: Theme.notifHistoryVisible = false
    }

    // ────────────────────────────────────────────────────────────────────────
    // ASSISTANT DE PREMIER LANCEMENT — cinq pages (clavier, dossiers, programmes,
    // widgets, astuce), affichées une seule fois. La surface et son état vivent
    // dans first_run.qml ; elle ne s'affiche que tant que `first_run_completed`
    // est faux dans style_vars.json.
    // ────────────────────────────────────────────────────────────────────────
    FirstRun {
        id: assistantPremierLancement
    }

    // ────────────────────────────────────────────────────────────────────────
    // BARRE DE CAPTURE (SUPER + SHIFT + S) — surface plein écran transparente :
    // elle attrape le clic extérieur et le clavier (Échap), tandis que la
    // pastille, elle, glisse depuis le bord gauche sans prendre la hauteur.
    // Le lancement de la capture attend que la surface ait disparu (340 ms),
    // sinon la barre figurerait sur la capture d'écran.
    // ────────────────────────────────────────────────────────────────────────
    property string pendingCapture: ""

    Timer {
        id: captureLaunchTimer
        interval: 340
        onTriggered: {
            if (root.pendingCapture === "") return
            Quickshell.execDetached([
                "bash", Quickshell.shellPath("core/screenshot.sh"), root.pendingCapture
            ])
            root.pendingCapture = ""
        }
    }

    function requestCapture(mode) {
        // Arrêter un enregistrement ne capture rien : attendre que la pastille
        // sorte n'ajouterait qu'un tiers de seconde de vidéo au fichier.
        if (mode === "record-stop") {
            Theme.screenshotPickerVisible = false
            Quickshell.execDetached([
                "bash", Quickshell.shellPath("core/screenshot.sh"), mode
            ])
            return
        }
        root.pendingCapture = mode
        Theme.screenshotPickerVisible = false
        captureLaunchTimer.restart()
    }

    PanelWindow {
        id: screenshotPickerWindow
        screen: topBarWindow.screen
        // Reste montée le temps de la sortie (220 ms + marge) : sinon la
        // pastille disparaîtrait d'un coup au lieu de rentrer à gauche.
        visible: Theme.screenshotPickerVisible || closeTimer.running
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Theme.screenshotPickerVisible
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-shotbar"

        property bool shown: false

        Timer { id: closeTimer; interval: 300 }

        // L'animation est armée une frame après le montage : la surface layer
        // n'est pas encore mappée quand la visibilité bascule, et l'animation
        // se jouerait dans le vide (première image déjà à l'arrivée).
        Timer {
            id: openTimer
            interval: 40
            onTriggered: screenshotPickerWindow.shown = true
        }

        Connections {
            target: Theme
            function onScreenshotPickerVisibleChanged() {
                if (Theme.screenshotPickerVisible) {
                    closeTimer.stop()
                    openTimer.restart()
                    recordingCheckProc.running = true
                } else {
                    openTimer.stop()
                    screenshotPickerWindow.shown = false
                    closeTimer.restart()
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: Theme.screenshotPickerVisible
            Keys.onEscapePressed: Theme.screenshotPickerVisible = false
        }

        // Fond cliquable : se referme comme le panneau et l'écran des raccourcis.
        MouseArea {
            anchors.fill: parent
            onClicked: Theme.screenshotPickerVisible = false
        }

        ScreenshotBar {
            id: shotBar
            anchors.verticalCenter: parent.verticalCenter
            x: screenshotPickerWindow.shown ? 18 : -(width + 24)
            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            onRegionRequested: root.requestCapture("region")
            onFullRequested: root.requestCapture("full")
            onRecordRegionRequested: root.requestCapture("record-region")
            onRecordFullRequested: root.requestCapture("record-full")
            onRecordStopRequested: root.requestCapture("record-stop")
        }

        // Un enregistrement peut être en cours depuis une ouverture précédente :
        // dans ce cas l'entrée vidéo devient « arrêter ».
        Process {
            id: recordingCheckProc
            command: ["pgrep", "-x", "wf-recorder"]
            stdout: StdioCollector {
                onStreamFinished: shotBar.recording = String(text).trim().length > 0
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
            visible: root.widgetVisible(w)

            anchors { top: true; left: true }
            // Glissement : les marges suivent le geste pendant qu'on déplace, puis
            // reprennent la valeur du fichier d'état une fois le relâchement écrit.
            property bool dragging: false
            property real dragStartX: 0
            property real dragStartY: 0
            property real liveX: Number(w.x) || 0
            property real liveY: Number(w.y) || 0
            // En mode placement, c'est l'aperçu qui pilote la position ; sinon le
            // fichier d'état fait foi.
            readonly property bool isPlacing: root.placingWindow === widgetWindow
            margins.top: widgetWindow.isPlacing ? Math.round(root.placingY) : (Number(w.y) || 0)
            margins.left: widgetWindow.isPlacing ? Math.round(root.placingX) : (Number(w.x) || 0)
            // La carte : transparence propre à chaque widget (0,35 par défaut,
            // donc au-dessus du seuil de flou 0,30). Le padding fait partie de
            // la surface : il consomme les clics, il reste donc serré (18 px).
            readonly property int pad: 18
            // L'opacité ne porte que le FOND de la carte. À 0 il n'y a plus de fond
            // du tout et le texte reste net, posé sur le wallpaper.
            readonly property bool hasOpacity: w.opacity !== undefined && w.opacity !== null
                                               && !isNaN(Number(w.opacity))
            readonly property real cardOpacity: hasOpacity
                ? Math.max(0, Math.min(1, Number(w.opacity))) : 0.35
            // Un type sans composant (meteo.qml absent, faute de frappe) donnait une
            // carte de pad*2 = 36×36 avec le rayon global : un rond vide, illisible
            // comme diagnostic. On affiche un libellé explicite à la place.
            readonly property bool broken: widgetLoader.status === Loader.Error
            implicitWidth: (broken ? brokenText.implicitWidth : widgetLoader.implicitWidth) + pad * 2
            implicitHeight: (broken ? brokenText.implicitHeight : widgetLoader.implicitHeight) + pad * 2
            Component.onCompleted: {
                const list = root.widgetWindows.slice()
                list.push(widgetWindow)
                root.widgetWindows = list
            }
            Component.onDestruction: {
                const i = root.widgetWindows.indexOf(widgetWindow)
                if (i >= 0) {
                    const list = root.widgetWindows.slice()
                    list.splice(i, 1)
                    root.widgetWindows = list
                }
            }

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
                // Seul le fond suit l'opacité ; 0 = carte invisible, texte intact.
                color: Qt.alpha(Theme.surface, widgetWindow.cardOpacity)
                border.width: widgetWindow.w.border === false ? 0 : 1
                border.color: Qt.alpha(Theme.accent, 0.16)

                // Clic milieu : les réglages de ce widget. Déclaré avant les
                // autres surfaces de la carte, donc dessous : le glissement
                // garde le bouton gauche, seul le milieu remonte jusqu'ici.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.menuWidgetX = Number(widgetWindow.w.x) || 0
                        root.menuWidgetY = Number(widgetWindow.w.y) || 0
                        root.menuWidgetId = String(widgetWindow.w.id || "")
                    }
                }

                // Déplacement à la souris.
                //
                // Constat mesuré sur une surface layer : `press`, `release` et
                // `enter` arrivent, mais **pas** les mouvements — ni MouseArea ni
                // DragHandler ne reçoivent de delta, et un PointHandler n'en reçoit
                // que tant que le pointeur reste au-dessus de la surface, donc pas
                // assez pour suivre le geste. On garde donc l'appui d'un PointHandler
                // (fiable) et on lit la position du curseur chez le compositeur.
                //
                // `hyprctl cursorpos` toutes les 30 ms pendant le geste : la surface
                // est repositionnée sous le pointeur, et comme on ne dépend plus des
                // événements de mouvement, le widget suit même quand le pointeur sort
                // de son rectangle.
                // Le widget lui-même ne capte plus rien : le déclencheur est le bind
                // Hyprland SUPER + SHIFT + clic (voir binds.lua), parce que
                // `mouse.modifiers` vaut 0 dans les événements souris de cette
                // surface — le modificateur y est invisible.

                Text {
                    id: brokenText
                    anchors.centerIn: parent
                    visible: widgetWindow.broken
                    text: "Widget « " + (widgetWindow.w.type || "?") + " » introuvable"
                    color: Qt.alpha(Theme.error, 0.9)
                    font.pixelSize: Theme.textXs
                }

                Loader {
                    id: widgetLoader
                    // Surtout pas `anchors.fill: parent` : le Loader imposerait sa
                    // taille (1×1 au premier paint) au widget, qui resterait écrasé
                    // (pitfall 68). Ici le contenu garde sa taille implicite et la
                    // fenêtre suit.
                    anchors.centerIn: parent
                    // Les widgets de compte partagent un seul composant : le
                    // fournisseur se déduit de l'id (« deepseek-3 » → deepseek),
                    // donc widgets.json, les positions et les réglages déjà
                    // enregistrés n'ont pas bougé.
                    source: {
                        const t = widgetWindow.w.type
                        if (!t) return ""
                        const partages = ["deepseek", "ollama", "antigravity"]
                        return "widgets/" + (partages.indexOf(t) >= 0 ? "llm" : t) + ".qml"
                    }
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

    // Surface de placement : plein écran, transparente, elle reçoit le pointeur
    // partout (contrairement au widget) et applique l'aperçu, puis pose au clic.
    PanelWindow {
        id: placementCatcher
        visible: root.placing
        screen: topBarWindow.screen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Namespace hors liste de flou : rien à flouter ici.
        WlrLayershell.namespace: "shell-widget-placement"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor

            onPositionChanged: mouse => {
                if (!root.placingWindow) return
                const maxX = parent.width - root.placingWindow.implicitWidth
                const maxY = parent.height - root.placingWindow.implicitHeight
                root.placingX = Math.max(0, Math.min(maxX, mouse.x - root.placingGrabX))
                root.placingY = Math.max(0, Math.min(maxY, mouse.y - root.placingGrabY))
            }

            onClicked: if (root.placingArmed) root.endPlacement(true)
            onWheel: if (root.placing) root.endPlacement(false)

            Keys.onEscapePressed: root.endPlacement(false)
            focus: true
        }
    }

    // Menu d'un widget du bureau (clic milieu) : retirer, ou choisir les bureaux.
    WidgetMenu {
        ouvert: root.menuWidgetId !== ""
        widget: root.menuWidget
        xEcran: root.menuWidgetX
        yEcran: root.menuWidgetY
        onFermer: root.menuWidgetId = ""
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
}
