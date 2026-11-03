import QtQuick
import Quickshell
import Quickshell.Io

// ════════════════════════════════════════════════════════════════════════════
// SYSTEM CONFIGURATION PANEL (config_panel.qml)
// ════════════════════════════════════════════════════════════════════════════
// Architecture Overview:
//   • Section 1: Backend IPC & State Synchronization
//       - Communicates with core/config_manager.py (CLI commands and state queries)
//       - Watches core/app_vars.json via FileView
//       - Synchronized command queue (cmdQueue) to prevent race conditions
//   • Section 2: Header Frame & Close Control (panelHeader)
//   • Section 3: Navigation Tabs Bar (panelTabs: Esthétique, Système & Écrans, Contrôles, Applications)
//   • Section 4: Tab Content Area (tabContentArea + mainFlickable with auto-scroll reset on tab switch)
//       - Tab 0: Esthétique & Personnalisation
//           * CollapsibleSection secTheme: Themes, Matugen presets, palette hex editor, wallpaper directory
//           * CollapsibleSection secAspect: Technical appearance (Gaps, Borders, Rounding, Quickshell radius,
//             Opacity, Bar height, Blur passes/size, Resize step, and quick toggles using Stepper components)
//       - Tab 1: Système & Écrans
//           * Host detection (desktop vs laptop), multi-monitor grid, resolution/refresh modes, scaling,
//             and time synchronization (Timezone & NTP toggle)
//       - Tab 2: Contrôles, Clavier & Raccourcis
//           * Keyboard layout preview & switcher, Hyprland binds viewer/editor, workspace shortcuts
//       - Tab 3: Applications & Démarrage
//           * CollapsibleSection secApps: Default applications (terminal, browser, editor, file manager)
//           * CollapsibleSection secAutostart: Managed user background daemons & autostart entries
// ════════════════════════════════════════════════════════════════════════════

Rectangle {
    id: root
    width: 680
    height: 560
    color: Theme.surfaceBg
    radius: Theme.globalRadius
    border.color: Theme.accent
    border.width: 1

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: BACKEND IPC & STATE PROPERTIES
    // ────────────────────────────────────────────────────────────────────────
    property int currentTab: 0 // 0: Esthétique, 1: Système & Écrans, 2: Contrôles, 3: Applications

    // State synced with config_manager.py & FileViews
    property string hostName: "Station"
    property bool isLaptop: false
    property string kbLayout: Theme.kbLayout || "fr"
    property var workspaceKeys: ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft"]

    property int gapsIn: 2
    property int gapsOut: 8
    property int borderSize: 2
    property int hyprRounding: 2
    property var monitorsList: []
    property string selectedMonitorName: "HDMI-A-1"
    property string timezoneStr: "Europe/Paris"
    property bool ntpSynced: true
    property var bindsList: []
    property var appVarsModel: []
    property var autostartModel: []
    property bool batLimit80: false

    // Selected color key for live hex editing in Appearance tab
    property string selectedColorKey: "accent"
    property string selectedColorHex: Theme.accent
    property string wallpaperDir: Theme.wallpaperDir || "$HOME/Images/wallpapers/"
    property string matugenScheme: "scheme-tonal-spot"
    property real matugenContrast: 0
    property bool blurEnabled: true
    property int blurSize: 3
    property int blurPasses: 3
    property real blurVibrancy: 0.17
    property int resizeStep: 15
    property var panelSections: ({})

    function setPanelSection(name, expanded) {
        let s = root.panelSections
        s[name] = expanded
        root.panelSections = s
        root.runConfigCmd(["panel_section", name, String(expanded)])
    }

    function refreshConfigState() {
        if (!stateProc.running) stateProc.running = true
    }

    // Commands run one at a time, in order: clicks made while one is running are queued
    // instead of being silently dropped.
    property var cmdQueue: []

    function startConfigCmd(args) {
        cmdProc.command = ["python3", Quickshell.shellPath("core/config_manager.py")].concat(args)
        cmdProc.running = true
    }

    function runConfigCmd(args) {
        if (!cmdProc.running) {
            startConfigCmd(args)
            return
        }
        const q = cmdQueue.slice()
        q.push(args)
        cmdQueue = q
    }

    function applyStateJson(data) {
        if (!data) return
        if (typeof data.hostname === "string" && data.hostname.length > 0) {
            root.hostName = data.hostname.charAt(0).toUpperCase() + data.hostname.slice(1)
        }
        if (typeof data.is_laptop === "boolean") {
            root.isLaptop = data.is_laptop
        }
        if (typeof data.kb_layout === "string") {
            root.kbLayout = data.kb_layout
        }
        if (typeof data.wallpaper_dir === "string" && data.wallpaper_dir.length > 0) {
            root.wallpaperDir = data.wallpaper_dir
        }
        if (typeof data.matugen_scheme === "string" && data.matugen_scheme.length > 0) {
            root.matugenScheme = data.matugen_scheme
        }
        if (typeof data.matugen_contrast === "number") {
            root.matugenContrast = data.matugen_contrast
        }
        if (typeof data.blur_enabled === "boolean") root.blurEnabled = data.blur_enabled
        if (typeof data.blur_size === "number") root.blurSize = data.blur_size
        if (typeof data.blur_passes === "number") root.blurPasses = data.blur_passes
        if (typeof data.blur_vibrancy === "number") root.blurVibrancy = data.blur_vibrancy
        if (typeof data.resize_step === "number") root.resizeStep = data.resize_step
        if (data.panel_sections) root.panelSections = data.panel_sections
        if (Array.isArray(data.workspace_keys)) {
            root.workspaceKeys = data.workspace_keys
        }
        if (data.gaps) {
            if (typeof data.gaps.gaps_in === "number") root.gapsIn = data.gaps.gaps_in
            if (typeof data.gaps.gaps_out === "number") root.gapsOut = data.gaps.gaps_out
            if (typeof data.gaps.border_size === "number") root.borderSize = data.gaps.border_size
        }
        if (typeof data.hypr_rounding === "number") root.hyprRounding = data.hypr_rounding
        if (data.display) {
            root.monitorsList = data.display.monitors || []
            if (root.monitorsList.length > 0) {
                let found = false
                for (let i = 0; i < root.monitorsList.length; i++) {
                    if (root.monitorsList[i].name === root.selectedMonitorName) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    root.selectedMonitorName = root.monitorsList[0].name
                }
            }
            if (data.display.timezone) root.timezoneStr = data.display.timezone
            if (typeof data.display.ntp === "boolean") root.ntpSynced = data.display.ntp
        }
        if (Array.isArray(data.binds)) {
            root.bindsList = data.binds
        }
        if (data.apps) {
            const arr = []
            for (const k in data.apps) {
                arr.push({ alias: k, cmd: data.apps[k] })
            }
            root.appVarsModel = arr
        }
        if (Array.isArray(data.autostart)) {
            root.autostartModel = data.autostart
        }
    }

    readonly property var currentMonitorObj: {
        for (let i = 0; i < root.monitorsList.length; i++) {
            if (root.monitorsList[i].name === root.selectedMonitorName) {
                return root.monitorsList[i]
            }
        }
        return root.monitorsList.length > 0 ? root.monitorsList[0] : null
    }

    readonly property var currentMonitorModes: {
        const m = root.currentMonitorObj
        if (m && Array.isArray(m.availableModes) && m.availableModes.length > 0) {
            return m.availableModes.slice(0, 6).concat(["preferred"])
        }
        return ["1920x1080@60", "2560x1440@60", "3840x2160@60", "preferred"]
    }

    Process {
        id: stateProc
        command: ["python3", Quickshell.shellPath("core/config_manager.py"), "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyStateJson(JSON.parse(text.trim()))
                } catch (e) {}
            }
        }
    }

    Process {
        id: cmdProc
        onExited: {
            if (root.cmdQueue.length > 0) {
                const q = root.cmdQueue.slice()
                const next = q.shift()
                root.cmdQueue = q
                root.startConfigCmd(next)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // Intermediate result: a newer command is queued, its own output will be applied
                if (root.cmdQueue.length > 0) return
                try {
                    root.applyStateJson(JSON.parse(text.trim()))
                } catch (e) {
                    root.refreshConfigState()
                }
            }
        }
    }

    FileView {
        id: appVarsFile
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const obj = JSON.parse(text())
                const arr = []
                for (const k in obj) {
                    arr.push({ alias: k, cmd: obj[k] })
                }
                root.appVarsModel = arr
            } catch (e) {}
        }
    }

    Connections {
        target: Theme
        function onConfigPanelVisibleChanged() {
            if (Theme.configPanelVisible) {
                root.refreshConfigState()
            }
        }
    }

    Component.onCompleted: refreshConfigState()

    // Absorb mouse clicks inside the panel so they don't close the overlay
    MouseArea {
        anchors.fill: parent
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 2: HEADER FRAME & CLOSE CONTROL
    // ────────────────────────────────────────────────────────────────────────
    Item {
        id: panelHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 30

        Text {
            text: "⚙ Panneau de Configuration — " + root.hostName
            color: Theme.fg
            font.pixelSize: 18
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: Theme.globalRadius
            color: closeMa.containsMouse ? Theme.error : Theme.surfaceVariant
            border.color: Theme.error
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: closeMa.containsMouse ? Theme.bg : Theme.error
                font.pixelSize: 13
                font.bold: true
            }

            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.configPanelVisible = false
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: NAVIGATION TABS BAR
    // ────────────────────────────────────────────────────────────────────────
    Row {
        id: panelTabs
        anchors.top: panelHeader.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 34
        spacing: 8

        Repeater {
            model: [
                { icon: "🎨", label: "Esthétique" },
                { icon: "🖥", label: root.isLaptop ? "Système & TV" : "Système & Écrans" },
                { icon: "⌨", label: "Contrôles" },
                { icon: "🚀", label: "Applications" }
            ]

            Rectangle {
                id: tabBtn
                required property int index
                required property var modelData
                readonly property bool active: root.currentTab === index

                width: (parent.width - 24) / 4
                height: 34
                radius: Theme.globalRadius
                color: active
                    ? Theme.accent
                    : (tabMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55))
                border.color: active ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: tabBtn.modelData.icon
                        font.pixelSize: 13
                    }

                    Text {
                        text: tabBtn.modelData.label
                        color: tabBtn.active ? Theme.bg : Theme.fg
                        font.pixelSize: 12
                        font.bold: tabBtn.active
                    }
                }

                MouseArea {
                    id: tabMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.currentTab = tabBtn.index
                }
            }
        }
    }

    Rectangle {
        id: panelDivider
        anchors.top: panelTabs.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 1
        color: Theme.surfaceVariant
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: TAB CONTENT AREA (Scrollable & Clipped)
    // ────────────────────────────────────────────────────────────────────────
    Item {
        id: tabContentArea
        anchors.top: panelDivider.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.bottomMargin: 20
        clip: true

        Flickable {
            id: mainFlickable
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: {
                if (root.currentTab === 0) return tabEsthetiqueCol.implicitHeight
                if (root.currentTab === 1) return tabSystemeCol.implicitHeight
                if (root.currentTab === 2) return tabControlesCol.implicitHeight
                if (root.currentTab === 3) return tabAppsCol.implicitHeight
                return 0
            }

            Connections {
                target: root
                function onCurrentTabChanged() {
                    mainFlickable.contentY = 0
                }
            }

            // ═══════════════════════════════════════════════════════════════════════════
            // TAB 0: ESTHÉTIQUE (Fond d'écran, Matugen, Thèmes, Gaps, Arrondis, Opacité)
            // ═══════════════════════════════════════════════════════════════════════════
            Column {
                id: tabEsthetiqueCol
                visible: root.currentTab === 0
                width: mainFlickable.width
                spacing: 11

                // 1+2. Thème & Fond d'écran (jeux de couleurs, wallpaper, matugen, palette hex custom)
            CollapsibleSection {
                id: secTheme
                title: "Thème & Fond d'écran"
                icon: "🎨"
                expanded: root.panelSections["esthetique_theme"] === true
                onToggled: expanded => root.setPanelSection("esthetique_theme", expanded)

                Text {
                    text: "Jeux de couleurs & Fond d'écran"
                    color: Theme.accent
                    font.pixelSize: 14
                    font.bold: true
                    width: parent.width
                }

            Row {
                spacing: 8
                width: parent.width

                Repeater {
                    model: ["dynamic", "tokyo-night", "catppuccin"]
                    Rectangle {
                        required property string modelData
                        readonly property bool isCurrent: Theme.activeTheme === modelData

                        width: 115
                        height: 32
                        radius: Theme.globalRadius
                        color: isCurrent ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: isCurrent ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.isCurrent ? Theme.bg : Theme.fg
                            font.pixelSize: 12
                            font.bold: parent.isCurrent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([
                                "python3",
                                Quickshell.shellPath("core/theme_manager.py"),
                                parent.modelData
                            ])
                        }
                    }
                }

                Rectangle {
                    width: 135
                    height: 32
                    radius: Theme.globalRadius
                    color: wpPickMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "🖼 Fonds d'écran"
                        color: wpPickMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: wpPickMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.configPanelVisible = false
                            Quickshell.execDetached([
                                "quickshell",
                                "-n",
                                "-p",
                                Quickshell.env("HOME") + "/.config/quickshell/hyprquickpaper"
                            ])
                        }
                    }
                }

                Rectangle {
                    width: 130
                    height: 32
                    radius: Theme.globalRadius
                    color: matugenMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✨ Sync Matugen"
                        color: matugenMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: matugenMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached([
                            "bash",
                            Quickshell.shellPath("core/generate_colors.sh")
                        ])
                    }
                }
            }

            // Matugen scheme & contrast (regenerates the dynamic palette from the current wallpaper)
            Row {
                spacing: 8
                width: parent.width

                Text {
                    width: 132
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Schéma Matugen :"
                    color: Theme.fg
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        { id: "scheme-tonal-spot", label: "Doux" },
                        { id: "scheme-vibrant", label: "Vif" },
                        { id: "scheme-expressive", label: "Expressif" },
                        { id: "scheme-neutral", label: "Neutre" },
                        { id: "scheme-fruit-salad", label: "Fruité" },
                        { id: "scheme-monochrome", label: "Mono" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool active: root.matugenScheme === modelData.id
                        width: 74; height: 24
                        radius: Theme.globalRadius
                        color: active ? Theme.accent : Theme.surfaceVariant
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: parent.active ? Theme.bg : Theme.fg
                            font.pixelSize: 10
                            font.bold: parent.active
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.matugenScheme = parent.modelData.id
                                root.runConfigCmd(["style", "matugen_scheme", parent.modelData.id])
                                Quickshell.execDetached(["bash", Quickshell.shellPath("core/generate_colors.sh")])
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 6
                width: parent.width

                Text {
                    width: 132
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Contraste :"
                    color: Theme.fg
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        // Libellés d'origine (Pastel → Max), valeurs conservées dans l'ordre
                        // actuel (+0.8 → -0.8).
                        { v: 0.8, label: "Pastel" },
                        { v: 0.6, label: "Doux-" },
                        { v: 0.3, label: "Standard" },
                        { v: 0.0, label: "Foncé+" },
                        { v: -0.4, label: "Contrasté" },
                        { v: -0.8, label: "Max" }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool active: Math.abs(root.matugenContrast - modelData.v) < 0.05
                        width: 62; height: 24
                        radius: Theme.globalRadius
                        color: active ? Theme.accent : Theme.surfaceVariant
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: parent.active ? Theme.bg : Theme.fg
                            font.pixelSize: 10
                            font.bold: parent.active
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.matugenContrast = parent.modelData.v
                                root.runConfigCmd(["style", "matugen_contrast", String(parent.modelData.v)])
                                Quickshell.execDetached(["bash", Quickshell.shellPath("core/generate_colors.sh")])
                            }
                        }
                    }
                }
            }

            // Wallpaper Directory Path
            Row {
                spacing: 8
                width: parent.width

                Text {
                    width: 145
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dossier wallpapers :"
                    color: Theme.fg
                    font.pixelSize: 12
                    font.bold: true
                }

                Rectangle {
                    width: 394
                    height: 28
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: wpDirInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1
                    clip: true

                    TextInput {
                        id: wpDirInput
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        text: Theme.wallpaperDir || root.wallpaperDir
                        color: Theme.fg
                        font.pixelSize: 11
                        onAccepted: {
                            if (wpDirInput.text.trim() !== "") {
                                root.runConfigCmd(["style", "wallpaper_dir", wpDirInput.text.trim()])
                            }
                        }
                    }
                }

                Rectangle {
                    width: 85
                    height: 28
                    radius: Theme.globalRadius
                    color: wpDirSaveMa.containsMouse ? Theme.accentMuted : Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Appliquer"
                        color: Theme.bg
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: wpDirSaveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (wpDirInput.text.trim() !== "") {
                                root.runConfigCmd(["style", "wallpaper_dir", wpDirInput.text.trim()])
                            }
                        }
                    }
                }
            }

            // 2. Active Palette Swatches & Custom Color Override
            Text {
                text: "Palette active (cliquer sur une pastille pour ajuster sa couleur hex)"
                color: Theme.accent
                font.pixelSize: 13
                font.bold: true
                width: parent.width
            }

            Row {
                spacing: 8
                width: parent.width

                Repeater {
                    model: [
                        { key: "bg", label: "Fond", col: Theme.bg },
                        { key: "surface", label: "Surface", col: Theme.surface },
                        { key: "surface_variant", label: "Variante", col: Theme.surfaceVariant },
                        { key: "fg", label: "Texte", col: Theme.fg },
                        { key: "accent", label: "Accent", col: Theme.accent },
                        { key: "accent_muted", label: "Second.", col: Theme.accentMuted },
                        { key: "warn", label: "Alerte", col: Theme.warn },
                        { key: "error", label: "Erreur", col: Theme.error }
                    ]

                    Column {
                        required property var modelData
                        spacing: 3
                        width: 56

                        Rectangle {
                            width: 52
                            height: 26
                            radius: Theme.globalRadius
                            color: parent.modelData.col
                            border.color: root.selectedColorKey === parent.modelData.key ? Theme.fg : Theme.surfaceVariant
                            border.width: root.selectedColorKey === parent.modelData.key ? 2 : 1

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedColorKey = parent.parent.modelData.key
                                    hexInput.text = String(parent.parent.modelData.col)
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.modelData.label
                            color: Qt.alpha(Theme.fg, 0.8)
                            font.pixelSize: 10
                        }
                    }
                }

                // Inline Hex Editor for selected swatch
                Column {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Clé : " + root.selectedColorKey
                        color: Theme.accentMuted
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Row {
                        spacing: 4
                        Rectangle {
                            width: 85
                            height: 26
                            color: Theme.bg
                            radius: Theme.globalRadius
                            border.color: Theme.accent
                            border.width: 1

                            TextInput {
                                id: hexInput
                                anchors.fill: parent
                                anchors.margins: 4
                                verticalAlignment: TextInput.AlignVCenter
                                text: "#b4befe"
                                color: Theme.fg
                                font.pixelSize: 11
                                onAccepted: root.runConfigCmd(["style", root.selectedColorKey, hexInput.text])
                            }
                        }

                        Rectangle {
                            width: 36
                            height: 26
                            radius: Theme.globalRadius
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: "OK"
                                color: Theme.bg
                                font.pixelSize: 10
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["style", root.selectedColorKey, hexInput.text])
                            }
                        }
                    }
                }
            }
            }   // end CollapsibleSection secTheme

            // 3. Desktop Aspect: Gaps, Borders, Rounding, Opacity, Blur, Bar (catégorie technique)
            CollapsibleSection {
                id: secAspect
                title: "Aspect technique du bureau"
                icon: "⚙️"
                expanded: root.panelSections["esthetique_aspect"] === true
                onToggled: expanded => root.setPanelSection("esthetique_aspect", expanded)

            Text {
                text: "Aspect du Bureau (Hyprland & Quickshell unifiés)"
                color: Theme.accent
                font.pixelSize: 14
                font.bold: true
                width: parent.width
            }

            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 14
                rowSpacing: 12

                // 1. Gaps In
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gaps internes (in) :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.gapsIn
                        minimumValue: 0
                        maximumValue: 30
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.gapsIn = newVal
                            root.runConfigCmd(["gaps", "gaps_in", String(newVal)])
                        }
                    }
                }

                // 2. Gaps Out
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gaps externes (out) :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.gapsOut
                        minimumValue: 0
                        maximumValue: 40
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.gapsOut = newVal
                            root.runConfigCmd(["gaps", "gaps_out", String(newVal)])
                        }
                    }
                }

                // 3. Bordures fenêtres
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bordures fenêtres :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.borderSize
                        minimumValue: 0
                        maximumValue: 10
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.borderSize = newVal
                            root.runConfigCmd(["gaps", "border_size", String(newVal)])
                        }
                    }
                }

                // 4. Arrondis fenêtres (Hyprland)
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Arrondis fenêtres :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.hyprRounding
                        minimumValue: 0
                        maximumValue: 35
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.hyprRounding = newVal
                            root.runConfigCmd(["style", "hypr_rounding", String(newVal)])
                        }
                    }
                }

                // 5. Arrondis îlots (Quickshell)
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Arrondis îlots (QS) :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Theme.globalRadius
                        minimumValue: 0
                        maximumValue: 30
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.runConfigCmd(["style", "global_radius", String(newVal)])
                        }
                    }
                }

                // 6. Global Opacity
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Opacité générale :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Theme.globalOpacity
                        minimumValue: 0.30
                        maximumValue: 1.00
                        stepSize: 0.05
                        decimals: 2
                        textFormatter: v => Math.round(v * 100) + " %"
                        onValueModified: newVal => {
                            root.runConfigCmd(["style", "global_opacity", String(newVal)])
                        }
                    }
                }

                // 7. Bar Height
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hauteur de barre :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Theme.barHeight
                        minimumValue: 28
                        maximumValue: 60
                        stepSize: 2
                        suffix: " px"
                        onValueModified: newVal => {
                            root.runConfigCmd(["style", "bar_height", String(newVal)])
                        }
                    }
                }

                // 8. Pas de redimensionnement clavier
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pas redimensionnement :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.resizeStep
                        minimumValue: 5
                        maximumValue: 50
                        stepSize: 5
                        suffix: " px"
                        onValueModified: newVal => {
                            root.resizeStep = newVal
                            root.runConfigCmd(["style", "resize_step", String(newVal)])
                        }
                    }
                }

                // 9. Blur Size
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Taille du flou :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.blurSize
                        minimumValue: 1
                        maximumValue: 20
                        stepSize: 1
                        suffix: " px"
                        onValueModified: newVal => {
                            root.blurSize = newVal
                            root.runConfigCmd(["style", "blur_size", String(newVal)])
                        }
                    }
                }

                // 10. Blur Passes
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Passes du flou :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.blurPasses
                        minimumValue: 1
                        maximumValue: 8
                        stepSize: 1
                        onValueModified: newVal => {
                            root.blurPasses = newVal
                            root.runConfigCmd(["style", "blur_passes", String(newVal)])
                        }
                    }
                }

                // 11. Blur Toggle (Actif / Désactivé)
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Flou Hyprland :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 140
                        height: 26
                        radius: Theme.globalRadius
                        color: root.blurEnabled ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.blurEnabled ? "✓ Flou Actif" : "✕ Désactivé"
                            color: root.blurEnabled ? Theme.bg : Theme.fg
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.blurEnabled = !root.blurEnabled
                                root.runConfigCmd(["style", "blur_enabled", root.blurEnabled ? "true" : "false"])
                            }
                        }
                    }
                }

                // 12. Bouton ⚙ Îlot Central Toggle
                Row {
                    width: (parent.width - 14) / 2
                    spacing: 8

                    Text {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bouton ⚙ central :"
                        color: Theme.fg
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 140
                        height: 26
                        radius: Theme.globalRadius
                        color: Theme.showConfigButton ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Theme.showConfigButton ? "✓ Affiché" : "Masqué (SUPER+H)"
                            color: Theme.showConfigButton ? Theme.bg : Theme.fg
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runConfigCmd(["style", "show_config_button", String(!Theme.showConfigButton)])
                        }
                    }
                }
            }   // end Grid
        }   // end CollapsibleSection secAspect
    }   // end Column tabEsthetiqueCol

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 1: SYSTÈME & ÉCRANS (Adaptatif : Tour Station vs Laptop Portable)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabSystemeCol
            visible: root.currentTab === 1
            width: mainFlickable.width
            spacing: 12

            Text {
                text: "Moniteurs détectés (" + root.hostName + ") — Cliquer pour sélectionner un écran"
                color: Theme.accent
                font.pixelSize: 14
                font.bold: true
            }

            // Dynamic list of connected monitors (e.g. HDMI-A-1 on Station, DP-1 / eDP-1 on Portable)
            Row {
                spacing: 10
                width: parent.width

                Repeater {
                    model: root.monitorsList

                    Rectangle {
                        id: monCard
                        required property var modelData
                        readonly property bool isSel: root.selectedMonitorName === modelData.name
                        width: Math.min(310, (parent.width - 10) / Math.max(1, root.monitorsList.length))
                        height: 54
                        radius: Theme.globalRadius
                        color: isSel ? Qt.alpha(Theme.accent, 0.22) : Theme.surfaceVariant
                        border.color: isSel ? Theme.accent : Theme.accentMuted
                        border.width: isSel ? 2 : 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "🖥 " + monCard.modelData.name + " (" + monCard.modelData.width + "x" + monCard.modelData.height + "@" + monCard.modelData.refreshRate + "Hz)"
                                color: monCard.isSel ? Theme.accent : Theme.fg
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: monCard.modelData.description || "Sortie vidéo active"
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: monCard.width - 16
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedMonitorName = monCard.modelData.name
                        }
                    }
                }
            }

            // Resolution & Refresh Rate selector for selected monitor
            Text {
                text: "Résolution & Fréquence pour « " + root.selectedMonitorName + " » (persistant dans hardware-" + root.hostName.toLowerCase() + ".lua)"
                color: Theme.accent
                font.pixelSize: 13
                font.bold: true
            }

            Flow {
                width: parent.width
                spacing: 8

                Repeater {
                    model: root.currentMonitorModes

                    Rectangle {
                        required property string modelData
                        width: 148
                        height: 30
                        radius: Theme.globalRadius
                        color: resMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accentMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData === "preferred" ? "Auto (Preferred)" : modelData + "Hz"
                            color: resMa.containsMouse ? Theme.bg : Theme.fg
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: resMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const curScale = root.currentMonitorObj ? String(root.currentMonitorObj.scale || 1) : "1"
                                root.runConfigCmd(["monitor_mode", root.selectedMonitorName, modelData, curScale])
                            }
                        }
                    }
                }
            }

            // Scale factor selector (Mouse only)
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mise à l'échelle (Scale) de " + root.selectedMonitorName + " :"
                    color: Theme.fg
                    font.pixelSize: 12
                }

                Repeater {
                    model: ["1", "1.25", "1.5"]
                    Rectangle {
                        required property string modelData
                        readonly property bool activeScale: root.currentMonitorObj && Math.abs(Number(root.currentMonitorObj.scale) - Number(modelData)) < 0.05
                        width: 58
                        height: 26
                        radius: Theme.globalRadius
                        color: activeScale ? Theme.accent : Theme.surfaceVariant
                        Text {
                            anchors.centerIn: parent
                            text: modelData + "x"
                            color: parent.activeScale ? Theme.bg : Theme.fg
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const m = root.currentMonitorObj
                                const curMode = m ? (m.width + "x" + m.height + "@" + m.refreshRate) : "preferred"
                                root.runConfigCmd(["monitor_mode", root.selectedMonitorName, curMode, modelData])
                            }
                        }
                    }
                }
            }

            // Laptop-only section: Multi-screen TV presets & Tablet rotation (Portable)
            Column {
                visible: root.isLaptop
                width: parent.width
                spacing: 10

                Text {
                    text: "Profils Multi-Écrans & Mode Tablette (Laptop Portable uniquement)"
                    color: Theme.accent
                    font.pixelSize: 13
                    font.bold: true
                }

                Row {
                    spacing: 8
                    width: parent.width

                    Repeater {
                        model: [
                            { id: "dual", title: "🖥 + 💻 Étendu (TV + Laptop)" },
                            { id: "tv", title: "📺 TV Uniquement (Dock)" },
                            { id: "laptop", title: "💻 Nomade (Laptop seul)" }
                        ]

                        Rectangle {
                            required property var modelData
                            width: (parent.width - 16) / 3
                            height: 32
                            radius: Theme.globalRadius
                            color: profMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                            Text {
                                anchors.centerIn: parent
                                text: modelData.title
                                color: profMa.containsMouse ? Theme.bg : Theme.fg
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: profMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["monitor_profile", modelData.id])
                            }
                        }
                    }
                }

                Row {
                    spacing: 8
                    Repeater {
                        model: [
                            { t: "0", label: "0° Normal" },
                            { t: "2", label: "180° Tablette" },
                            { t: "1", label: "90° Portrait G" },
                            { t: "3", label: "270° Portrait D" }
                        ]

                        Rectangle {
                            required property var modelData
                            width: 152
                            height: 28
                            radius: Theme.globalRadius
                            color: rotMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: rotMa.containsMouse ? Theme.bg : Theme.fg
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: rotMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["rotate", modelData.t])
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.surfaceVariant
            }

            // System Time, Network Shortcut (& Battery 80% Limiter if Laptop)
            Row {
                width: parent.width
                spacing: 14

                Rectangle {
                    width: root.isLaptop ? 230 : 320
                    height: 46
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: "🕒 Fuseau : " + root.timezoneStr
                            color: Theme.fg
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            text: root.ntpSynced ? "✓ Horloge NTP synchronisée" : "⚠ NTP non synchronisé"
                            color: root.ntpSynced ? Theme.success : Theme.warn
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    width: root.isLaptop ? 190 : 300
                    height: 46
                    radius: Theme.globalRadius
                    color: openWifiMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "📶 Ouvrir le panneau Réseau / WiFi"
                        color: openWifiMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        id: openWifiMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.configPanelVisible = false
                            Theme.activePopup = "wifi"
                        }
                    }
                }

                Rectangle {
                    visible: root.isLaptop
                    width: 180
                    height: 46
                    radius: Theme.globalRadius
                    color: root.batLimit80 ? Theme.success : Theme.surfaceVariant
                    border.color: Theme.success
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.batLimit80 ? "🔋 Limite 80% : ACTIVE" : "🔋 Activer Limite 80%"
                        color: root.batLimit80 ? Theme.bg : Theme.fg
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.batLimit80 = !root.batLimit80
                            root.runConfigCmd(["battery", root.batLimit80 ? "80" : "100"])
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 2: CONTRÔLES, CLAVIER & RACCOURCIS (binds.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabControlesCol
            visible: root.currentTab === 2
            width: mainFlickable.width
            spacing: 10

            // Top bar: Current Keyboard Layout + Button to reopen First-Run Keyboard Selector
            Rectangle {
                width: parent.width
                height: 42
                radius: Theme.globalRadius
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌨ Disposition active : " + root.kbLayout.toUpperCase()
                        color: Theme.accent
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "(Workspaces 1..10 : " + root.workspaceKeys.slice(0, 5).join(", ") + " …)"
                        color: Qt.alpha(Theme.fg, 0.8)
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    width: 215
                    height: 28
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: reopenKbMa.containsMouse ? Theme.accent : Theme.bg
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "🌍 Assistant Langue Clavier"
                        color: reopenKbMa.containsMouse ? Theme.bg : Theme.accent
                        font.pixelSize: 11
                        font.bold: true
                    }

                    MouseArea {
                        id: reopenKbMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.configPanelVisible = false
                            Theme.showKeyboardOnboarding = true
                        }
                    }
                }
            }

            Text {
                text: "Raccourcis Clavier Hyprland (cliquer sur une ligne pour l'éditer)"
                color: Theme.accent
                font.pixelSize: 13
                font.bold: true
            }

            Flickable {
                width: parent.width
                height: 245
                contentWidth: width
                contentHeight: bindsCol.implicitHeight
                clip: true

                Column {
                    id: bindsCol
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.bindsList

                        Rectangle {
                            required property var modelData
                            width: bindsCol.width
                            height: 30
                            radius: Theme.globalRadius
                            color: bindRowMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.5)

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12

                                Rectangle {
                                    width: 170
                                    height: 22
                                    radius: Theme.globalRadius
                                    color: Theme.bg
                                    border.color: Theme.accentMuted
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.mod + " + " + modelData.key
                                        color: Theme.accent
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "→  " + modelData.target
                                    color: Theme.fg
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                id: bindRowMa
                                anchors.fill: parent
                                anchors.rightMargin: 36
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bindKeyInput.text = modelData.key
                                    bindCmdInput.text = modelData.target
                                }
                            }

                            // Delete bind button
                            Rectangle {
                                width: 24
                                height: 24
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.globalRadius
                                color: "transparent"
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["bind_del", modelData.key])
                                }
                            }
                        }
                    }
                }
            }

            // Add / Update Keybind Bar
            Row {
                spacing: 8
                width: parent.width

                Rectangle {
                    width: 75
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    Text {
                        anchors.centerIn: parent
                        text: "SUPER +"
                        color: Theme.accent
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Rectangle {
                    width: 150
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.bg
                    border.color: bindKeyInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: bindKeyInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: "Touche (ex: Return, M)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: bindKeyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    width: 280
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.bg
                    border.color: bindCmdInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: bindCmdInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: "Commande ou variable (ex: terminal)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: bindCmdInput
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: 12
                        onAccepted: {
                            if (bindKeyInput.text !== "" && bindCmdInput.text !== "") {
                                root.runConfigCmd(["bind_set", bindKeyInput.text, bindCmdInput.text])
                            }
                        }
                    }
                }

                Rectangle {
                    width: 110
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Enregistrer"
                        color: Theme.bg
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (bindKeyInput.text !== "" && bindCmdInput.text !== "") {
                                root.runConfigCmd(["bind_set", bindKeyInput.text, bindCmdInput.text])
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 3: VARIABLES DYNAMIQUES & APPLICATIONS (app_vars.json <-> programs.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabAppsCol
            visible: root.currentTab === 3
            width: mainFlickable.width
            spacing: 12

            // Programs par défaut des raccourcis (app_vars.json <-> programs.lua)
            CollapsibleSection {
                id: secApps
                title: "Programmes par défaut des raccourcis"
                icon: "🚀"
                expanded: root.panelSections["apps_programs"] === true
                onToggled: expanded => root.setPanelSection("apps_programs", expanded)

            Text {
                text: "Variables d'Applications par défaut (Synchronisées à la volée avec Hyprland)"
                color: Theme.accent
                font.pixelSize: 14
                font.bold: true
                width: parent.width
            }

            Flickable {
                width: parent.width
                height: 290
                contentWidth: width
                contentHeight: appList.implicitHeight
                clip: true

                Column {
                    id: appList
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.appVarsModel

                        Row {
                            id: appRow
                            required property var modelData
                            spacing: 10
                            width: appList.width

                            // Variable Name (Alias)
                            Rectangle {
                                width: 170
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: appRow.modelData.alias
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                            }

                            // Editable Command Field
                            Rectangle {
                                width: 360
                                height: 32
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: editCmdInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                TextInput {
                                    id: editCmdInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: appRow.modelData.cmd
                                    color: Theme.info
                                    font.pixelSize: 12
                                    onAccepted: root.runConfigCmd(["app_set", appRow.modelData.alias, editCmdInput.text])
                                }
                            }

                            // Save Button
                            Rectangle {
                                width: 36
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.success
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.success
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["app_set", appRow.modelData.alias, editCmdInput.text])
                                }
                            }

                            // Delete Button
                            Rectangle {
                                width: 36
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["app_del", appRow.modelData.alias])
                                }
                            }
                        }
                    }
                }
            }

            // Add New Application Variable Row
            Row {
                spacing: 10
                width: parent.width

                Rectangle {
                    width: 170
                    height: 34
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: newAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: newAlias.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "Nom (ex: Mail)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: newAlias
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    width: 340
                    height: 34
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: newCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: newCmd.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "Programme (ex: thunderbird)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: newCmd
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: 12
                        onAccepted: {
                            if (newAlias.text !== "" && newCmd.text !== "") {
                                root.runConfigCmd(["app_set", newAlias.text, newCmd.text])
                                newAlias.text = ""
                                newCmd.text = ""
                            }
                        }
                    }
                }

                Rectangle {
                    width: 110
                    height: 34
                    radius: Theme.globalRadius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (newAlias.text !== "" && newCmd.text !== "") {
                                root.runConfigCmd(["app_set", newAlias.text, newCmd.text])
                                newAlias.text = ""
                                newCmd.text = ""
                            }
                        }
                    }
                }
            }
            }   // end CollapsibleSection secApps

            // Autostart géré par le panneau (autostart.json -> autostart_managed.lua)
            CollapsibleSection {
                id: secAutostart
                title: "Programmes lancés au démarrage"
                icon: "⏻"
                expanded: root.panelSections["apps_autostart"] === true
                onToggled: expanded => root.setPanelSection("apps_autostart", expanded)

            Text {
                text: "Autostart Hyprland (effectif au prochain démarrage de session)"
                color: Theme.accent
                font.pixelSize: 13
                font.bold: true
                width: parent.width
            }

            Flickable {
                width: parent.width
                height: 150
                contentWidth: width
                contentHeight: autostartList.implicitHeight
                clip: true

                Column {
                    id: autostartList
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.autostartModel

                        Row {
                            id: asRow
                            required property var modelData
                            spacing: 10
                            width: autostartList.width

                            Rectangle {
                                width: 40
                                height: 32
                                radius: Theme.globalRadius
                                color: asRow.modelData.enabled ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.4)
                                border.color: asRow.modelData.enabled ? Theme.success : Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: asRow.modelData.enabled ? "✓" : "✕"
                                    color: asRow.modelData.enabled ? Theme.success : Theme.error
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["autostart_set", asRow.modelData.name, String(!asRow.modelData.enabled)])
                                }
                            }

                            Rectangle {
                                width: 200
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: asRow.modelData.name
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: 12
                                }
                            }

                            Rectangle {
                                width: 330
                                height: 32
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: Theme.surfaceVariant
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    text: asRow.modelData.cmd
                                    elide: Text.ElideRight
                                    color: Theme.info
                                    font.pixelSize: 11
                                }
                            }

                            Rectangle {
                                width: 36
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["autostart_del", asRow.modelData.name])
                                }
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 10
                width: parent.width

                Rectangle {
                    width: 190
                    height: 34
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: newAsName.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: newAsName.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "Nom (ex: Discord)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: newAsName
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    width: 320
                    height: 34
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: newAsCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    Text {
                        visible: newAsCmd.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "Commande (ex: discord &)"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: newAsCmd
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: 12
                        onAccepted: {
                            if (newAsName.text !== "" && newAsCmd.text !== "") {
                                root.runConfigCmd(["autostart_add", newAsName.text, newAsCmd.text])
                                newAsName.text = ""
                                newAsCmd.text = ""
                            }
                        }
                    }
                }

                Rectangle {
                    width: 110
                    height: 34
                    radius: Theme.globalRadius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: 12
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (newAsName.text !== "" && newAsCmd.text !== "") {
                                root.runConfigCmd(["autostart_add", newAsName.text, newAsCmd.text])
                                newAsName.text = ""
                                newAsCmd.text = ""
                            }
                        }
                    }
                }
            }
            }   // end CollapsibleSection secAutostart
        }   // end Column tabAppsCol
    }   // end Flickable mainFlickable
    }   // end Item tabContentArea
}
