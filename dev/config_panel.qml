import QtQuick
import Quickshell
import Quickshell.Io

// ════════════════════════════════════════════════════════════════════════════
// SYSTEM CONFIGURATION PANEL (config_panel.qml)
// ════════════════════════════════════════════════════════════════════════════
// Choix du contrôle numérique (règle du 05/11) :
//   • plage > 12 unités  → Slider (curseur) : viser une valeur dans une large
//     plage au glissement est plus rapide qu'au clic.
//   • plage ≤ 12 unités  → Stepper (compteur [−] valeur [+]) : plus précis, et
//     la valeur exacte reste lisible.
//   • exceptions assumées : la position x/y des widgets (plage de 1800 px, mais
//     on veut du pas régulier), et l'opacité « Fond » des cartes de widgets
//     (coincée entre trois interrupteurs dans une rangée à largeur calculée).
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
    width: 620
    height: parent ? parent.height : 600
    color: Theme.surfaceBg
    radius: Theme.globalRadius
    border.color: Theme.accent
    border.width: 1

    // Thème du greeter sélectionné dans l'onglet Connexion. Porté ici parce que
    // le composant de l'onglet est déchargé dès qu'on le quitte.
    property string greeterSelected: ""

    // Recherche : requête courante, alimentée par le champ de la §3.
    property string searchQuery: ""
    // Résultats calculés (label, tab, section, target) — voir searchIndex.
    property var searchResults: []

    // Index d'ancres : une entrée par réglage notable. Le champ redirige vers
    // l'onglet et la section, puis fait défiler jusqu'à la ligne ciblée.
    readonly property var searchIndex: [
        { label: "Thème de l'écran de connexion", words: "connexion greeter sddm ecran login theme de connexion",
          tab: 5, section: "greeter_theme", target: "secGreeter" },
        { label: "Accès API", words: "cle api token deepseek ollama secrets connexion fournisseur", tab: 1,
          section: "widgets_api", target: "secApiKeys" },
        { label: "Widgets du bureau", words: "widgets bureau horloge date meteo workspace",
          tab: 1, section: "widgets", target: "secWidgets" },
        { label: "Position du lanceur", words: "lanceur position capsule haut bas centre gauche droite",
          tab: 1, section: "widgets", target: "secWidgets" },
        { label: "Thème et fond d'écran", words: "theme fond ecran wallpaper couleur",
          tab: 0, section: "esthetique_theme", target: "secTheme" },
        { label: "Jeux de couleurs Matugen", words: "matugen palette preset couleurs saturation",
          tab: 0, section: "esthetique_theme", target: "matugenRow" },
        { label: "Palette hexadécimale", words: "hex couleur personnalisee accent",
          tab: 0, section: "esthetique_theme", target: "secTheme" },
        { label: "Dossier des fonds d'écran", words: "dossier wallpaper repertoire images",
          tab: 0, section: "esthetique_theme", target: "wallpaperDirRow" },
        { label: "Dossier des captures d'écran", words: "capture ecran screenshot dossier chemin enregistrement image",
          tab: 0, section: "esthetique_theme", target: "screenshotsDirRow" },
        { label: "Gaps internes et externes", words: "gaps espacement interieur exterieur marge",
          tab: 0, section: "esthetique_aspect", target: "gapsRow" },
        { label: "Bordures des fenêtres", words: "bordure border epaisseur",
          tab: 0, section: "esthetique_aspect", target: "borderRow" },
        { label: "Arrondis des fenêtres", words: "arrondi rounding rayon fenetre",
          tab: 0, section: "esthetique_aspect", target: "roundingWinRow" },
        { label: "Forme des coins", words: "arrondi rounding power chanfrein squircle forme coin courbe",
          tab: 0, section: "esthetique_aspect", target: "roundingPowerRow" },
        { label: "Arrondis des îlots", words: "arrondi rayon ilot quickshell barre",
          tab: 0, section: "esthetique_quickshell", target: "roundingIslandRow" },
        { label: "Hauteur de la barre", words: "hauteur barre taille bar",
          tab: 0, section: "esthetique_quickshell", target: "barHeightRow" },
        { label: "Pas de redimensionnement", words: "pas redimensionnement resize step",
          tab: 0, section: "esthetique_aspect", target: "resizeRow" },
        { label: "Opacité des fenêtres", words: "opacite fenetres transparence hyprland",
          tab: 0, section: "esthetique_aspect", target: "winOpacityRow" },
        { label: "Opacité des surfaces du shell", words: "opacite surfaces shell verre barre panneau",
          tab: 0, section: "esthetique_quickshell", target: "shellOpacityRow" },
        { label: "Taille et passes du flou", words: "flou blur taille passes intensite",
          tab: 0, section: "esthetique_aspect", target: "blurRow" },
        { label: "Flou des surfaces du shell", words: "flou shell layer rule seuil ignore alpha popups",
          tab: 0, section: "esthetique_quickshell", target: "shellBlurRow" },
        { label: "Écrans, résolution, taux de rafraîchissement", words: "ecran moniteur resolution taux hz echelle scale",
          tab: 2, section: "", target: "monitorsRow" },
        { label: "Fuseau horaire et synchronisation NTP", words: "fuseau timezone heure ntp synchronisation horloge",
          tab: 2, section: "", target: "timezoneRow" },
        { label: "Disposition du clavier", words: "clavier layout azerty qwerty langue",
          tab: 3, section: "", target: "kbdRow" },
        { label: "Raccourcis Hyprland", words: "raccourcis binds touches clavier hyprland",
          tab: 3, section: "", target: "bindsCol" },
        { label: "Programmes par défaut des raccourcis", words: "applications variables programmes defaut terminal navigateur editeur fichiers chemins",
          tab: 4, section: "apps_programs", target: "secApps" },
        { label: "Historique des lancements", words: "historique lancements recents pilule spotlight memoire",
          tab: 4, section: "apps_programs", target: "launchHistoryRow" },
        { label: "Cible du clic sur une notification", words: "notification notifications clic titre cible lien fichier video image dossier commande", 
          tab: 4, section: "apps_notif_targets", target: "secNotifTargets" },
        { label: "Programmes lancés au démarrage", words: "applications autostart demarrage lancement daemon",
          tab: 4, section: "apps_autostart", target: "secAutostart" }
    ]

    // Redirige vers l'onglet et la section du réglage, puis défile jusqu'à lui.
    function jumpToResult(entry) {
        if (!entry) return
        root.currentTab = entry.tab
        if (entry.section && entry.section !== "") root.setPanelSection(entry.section, true)
        root.searchQuery = ""
        searchInput.text = ""
        // Une frame pour laisser la section se déplier et le Flickable se
        // recalculer avant de mesurer la position de la cible.
        // Le dépliage de la section et le changement d'onglet ne sont pas
        // encore mesurables à la frame suivante : on réessaie trois fois.
        scrollTargetName = entry.target
        scrollTries = 0
        scrollTimer.restart()
    }

    function updateSearch(query) {
        const q = String(query).toLowerCase().trim()
        if (q.length < 2) { root.searchResults = []; return }
        const hits = []
        for (let i = 0; i < root.searchIndex.length; ++i) {
            const e = root.searchIndex[i]
            const hay = (e.label + " " + e.words).toLowerCase()
            if (hay.indexOf(q) >= 0) hits.push(e)
            if (hits.length >= 6) break
        }
        root.searchResults = hits
    }

    // Cibles d'ancrage de la recherche : QML n'expose pas QObject::findChild,
    // donc on tient la table id -> item à la main.
    readonly property var targetMap: ({
        "secTheme": secTheme,
        "matugenRow": matugenRow,
        "wallpaperDirRow": wallpaperDirRow,
        "screenshotsDirRow": screenshotsDirRow,
        "gapsRow": gapsRow,
        "borderRow": borderRow,
        "roundingWinRow": roundingWinRow,
        "roundingIslandRow": roundingIslandRow,
        "barHeightRow": barHeightRow,
        "resizeRow": resizeRow,
        "winOpacityRow": winOpacityRow,
        "shellOpacityRow": shellOpacityRow,
        "blurRow": blurRow,
        "shellBlurRow": shellBlurRow,
        "monitorsRow": monitorsRow,
        "timezoneRow": timezoneRow,
        "kbdRow": kbdRow,
        "bindsCol": bindsCol,
        "secApps": secApps,
        "launchHistoryRow": launchHistoryRow,
        "secAutostart": secAutostart
    })

    function scrollToAnchor(name) {
        const target = root.targetMap[name]
        if (!target) return
        const y = target.mapToItem(mainFlickable.contentItem, 0, 0).y
        const maxY = Math.max(0, mainFlickable.contentHeight - mainFlickable.height)
        mainFlickable.contentY = Math.max(0, Math.min(y - 12, maxY))
    }

    property string scrollTargetName: ""
    property int scrollTries: 0
    Timer {
        id: scrollTimer
        interval: 90
        repeat: true
        onTriggered: {
            root.scrollToAnchor(root.scrollTargetName)
            root.scrollTries += 1
            if (root.scrollTries >= 3) running = false
        }
    }

    property string highlightTarget: ""
    Timer { id: highlightTimer; interval: 700; onTriggered: root.highlightTarget = "" }

    // Sections dépliées par défaut : tout est visible sous le champ de recherche,
    // sauf ce que l'utilisateur a explicitement replié.
    function sectionOpen(name, fallback) {
        const v = root.panelSections[name]
        return (typeof v === "boolean") ? v : fallback
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: BACKEND IPC & STATE PROPERTIES
    // ────────────────────────────────────────────────────────────────────────
    property int currentTab: 0 // 0: Esthétique, 1: Widgets, 2: Système & Écrans, 3: Contrôles, 4: Applications, 5: Connexion

    // State synced with config_manager.py & FileViews
    property string hostName: "Station"
    property bool isLaptop: false
    property string screenshotsDir: "$HOME/Images/Screenshots/"
    property string kbLayout: Theme.kbLayout || "fr"
    property var workspaceKeys: ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft"]

    property int gapsIn: 2
    property int gapsOut: 8
    property int borderSize: 2
    property int hyprRounding: 2
    property real hyprRoundingPower: 2.0
    // Clés d'API : le panneau ne connaît que leur présence et leurs 4 derniers
    // caractères — la valeur elle-même ne remonte jamais du fichier.
    property var apiKeys: ({})
    // Fournisseurs LLM (core/llm_providers.json) : une ligne par entrée, dans
    // l'ordre du fichier. Ajouter un service ne touche pas à ce panneau.
    property var llmProviders: []
    // Message par fournisseur : un état partagé ferait apparaître « clé refusée »
    // sous Ollama alors qu'on vient d'enregistrer celle de DeepSeek.
    property var cleEtats: ({})
    property var pendingProvider: null
    property var pendingChamp: null

    function etatCle(id, message) {
        const copie = ({})
        for (const k in root.cleEtats) copie[k] = root.cleEtats[k]
        copie[id] = message
        root.cleEtats = copie
    }
    property var monitorsList: []
    property string selectedMonitorName: "HDMI-A-1"
    property string timezoneStr: "Europe/Paris"
    property bool ntpSynced: true
    property var bindsList: []
    // Widgets de bureau (core/widgets.json) et position de la capsule du lanceur.
    property var widgetsList: []
    // Une seule instance par nature de widget : elle est posée sur un bureau
    // ou sur tous (workspace 0), jamais deux fois. Le sélecteur du panneau est
    // donc une liste de cases à cocher, pas des boutons « ajouter ».
    readonly property var widgetTypes: [
        { type: "horloge", label: "Horloge" },
        { type: "date",    label: "Date" },
        { type: "meteo",   label: "Météo" },
        { type: "combo",   label: "Combo" },
        { type: "musique", label: "Musique" },
        { type: "deepseek", label: "DeepSeek" },
        { type: "ollama",   label: "Ollama Cloud" }
    ]
    readonly property var widgetTypeRows: {
        const poses = ({})
        for (let i = 0; i < widgetsList.length; i++) {
            const nature = String(widgetsList[i].type || "")
            poses[nature] = (poses[nature] || 0) + 1
        }
        return widgetTypes.map(function (nature) {
            const combien = poses[nature.type] || 0
            return { type: nature.type, label: nature.label, count: combien, present: combien > 0 }
        })
    }

    // Cocher pose le widget (bureau 1, position par défaut) ; décocher retire
    // toutes ses instances — il ne doit pas y en avoir plusieurs.
    function toggleWidgetType(nature, present) {
        if (present) {
            for (let i = 0; i < widgetsList.length; i++) {
                if (String(widgetsList[i].type) === String(nature))
                    root.runConfigCmd(["widget_remove", widgetsList[i].id])
            }
            return
        }
        root.runConfigCmd(["widget_add", String(nature), "1", "120", "160"])
    }
    property string launcherPosition: "bas-centre"
    property var appVarsModel: []
    // Cible du clic sur une notification (core/notif_targets.json) : lignes
    // dérivées pour la section « Cible du clic sur une notification ».
    property var notifTargets: ({ "apps": ({}), "types": ({}), "url": "Browser" })
    readonly property var notifTypeRows: [
        { nature: "video",  label: "Vidéo",   alias: String(root.notifTargets.types.video || "") },
        { nature: "image",  label: "Image",   alias: String(root.notifTargets.types.image || "") },
        { nature: "folder", label: "Dossier", alias: String(root.notifTargets.types.folder || "") },
        { nature: "text",   label: "Texte",   alias: String(root.notifTargets.types.text || "") }
    ]
    readonly property var notifAppRows: {
        const out = []
        const apps = root.notifTargets.apps || ({})
        for (const key in apps) {
            const rule = apps[key]
            const command = (rule && typeof rule === "object") ? String(rule.run || "") : String(rule || "")
            out.push({ key: key, command: command,
                       terminal: Boolean(rule && typeof rule === "object" && rule.terminal) })
        }
        return out
    }
    property var autostartModel: []
    property bool batLimit80: false

    // Selected color key for live hex editing in Appearance tab
    property string selectedColorKey: "accent"
    property string selectedColorHex: Theme.accent
    property string wallpaperDir: Theme.wallpaperDir || "$HOME/Images/wallpapers/"
    property string matugenScheme: "scheme-tonal-spot"
    property real matugenContrast: 0
    property bool blurEnabled: true
    property bool launchHistory: false
    property int blurSize: 3
    property int blurPasses: 3
    property real blurVibrancy: 0.17
    // Flou des surfaces layer-shell du shell (layer rules de general.lua)
    property bool shellBlurEnabled: true
    property bool barBorder: true
    property real shellBlurAlpha: 0.4
    property bool shellBlurPopups: true
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

    // Vide core/launch_history.json (bouton « Vider » du panneau).
    Process {
        id: clearHistoryProc
        command: ["python3", Quickshell.shellPath("core/launch_history.py"), "clear"]
    }

    function clearLaunchHistory() {
        if (!clearHistoryProc.running) clearHistoryProc.running = true
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
        if (typeof data.screenshots_dir === "string" && data.screenshots_dir.length > 0) {
            root.screenshotsDir = data.screenshots_dir
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
        if (typeof data.shell_blur_enabled === "boolean") root.shellBlurEnabled = data.shell_blur_enabled
        if (typeof data.bar_border === "boolean") root.barBorder = data.bar_border
        if (typeof data.shell_blur_alpha === "number") root.shellBlurAlpha = data.shell_blur_alpha
        if (typeof data.shell_blur_popups === "boolean") root.shellBlurPopups = data.shell_blur_popups
        if (typeof data.launch_history === "boolean") root.launchHistory = data.launch_history
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
        if (data.api_keys && typeof data.api_keys === "object") root.apiKeys = data.api_keys
        if (Array.isArray(data.llm_providers)) root.llmProviders = data.llm_providers
        if (typeof data.hypr_rounding_power === "number")
            root.hyprRoundingPower = data.hypr_rounding_power
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
        if (Array.isArray(data.widgets)) root.widgetsList = data.widgets
        if (typeof data.launcher_position === "string") root.launcherPosition = data.launcher_position
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

    property bool resDropdownOpen: false

    readonly property var currentMonitorModes: {
        const m = root.currentMonitorObj
        if (m && Array.isArray(m.availableModes) && m.availableModes.length > 0) {
            return m.availableModes
        }
        return ["preferred", "3840x2160@30", "1920x1080@120", "1920x1080@60", "1280x720@60"]
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

    // Clé d'API : écrite dans un fichier du répertoire runtime, puis remise à
    // config_manager qui la range dans secrets.json et supprime le fichier.
    FileView {
        id: cleApiFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-api-key.json"
        atomicWrites: true
        printErrors: true
        onSaved: root.envoyerCleApi()
        onSaveFailed: err => {
            if (root.pendingProvider) root.etatCle(root.pendingProvider.id, "écriture impossible (" + err + ")")
        }
    }

    // `provider` est une entrée de core/llm_providers.json : sa référence de clé
    // (« section.nom ») dit où ranger la valeur dans secrets.json.
    function enregistrerCleApi(provider, champ) {
        const valeur = champ.text.trim()
        if (valeur === "") {
            root.etatCle(provider.id, "clé vide")
            return
        }
        const ref = String(provider.key || "").split(".")
        if (ref.length < 2) {
            root.etatCle(provider.id, "référence de clé invalide dans llm_providers.json")
            return
        }
        root.pendingProvider = provider
        root.pendingChamp = champ
        root.etatCle(provider.id, "enregistrement…")
        cleApiFile.setText(JSON.stringify({
            section: ref[0], nom: ref.slice(1).join("."), valeur: valeur
        }))
    }

    function envoyerCleApi() {
        cleApiProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                              "api_key_set_file", cleApiFile.path]
        cleApiProc.running = true
    }

    Process {
        id: cleApiProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = ({})
                try { r = JSON.parse(text.trim()) } catch (e) {}
                const provider = root.pendingProvider
                if (!provider) return
                if (r.ok) {
                    root.etatCle(provider.id, "enregistrée (…" + r.tail + "), vérification…")
                    if (root.pendingChamp) root.pendingChamp.text = ""
                    root.refreshConfigState()
                    // Une clé mal copiée (préfixe perdu, jeton d'un autre champ) ne
                    // se voit qu'à l'usage : on interroge l'API dans la foulée, via
                    // le script que le fournisseur déclare.
                    testCleProc.command = ["python3", Quickshell.shellPath(provider.service), "--force"]
                    testCleProc.running = true
                } else {
                    root.etatCle(provider.id, "refusé : " + (r.erreur || "valeur invalide"))
                }
            }
        }
    }

    Process {
        id: testCleProc
        stdout: StdioCollector {
            onStreamFinished: {
                const provider = root.pendingProvider
                if (!provider) return
                let r = ({})
                try { r = JSON.parse(text.trim()) } catch (e) {}
                if (r.ok) {
                    const sym = r.currency === "CNY" ? "¥" : (r.currency === "USD" ? "$" : "")
                    let msg = (r.total !== undefined && r.total !== null)
                        ? "clé acceptée · solde " + sym + Number(r.total).toFixed(2)
                        : "clé acceptée · service joignable"
                    if (r.available === false || (r.total !== undefined && Number(r.total) <= 0))
                        msg += " — crédit épuisé"
                    root.etatCle(provider.id, msg)
                } else {
                    root.etatCle(provider.id, "l'API refuse cette clé : " + (r.error || "raison inconnue"))
                }
            }
        }
    }

    FileView {
        id: notifTargetsFile
        path: Quickshell.shellPath("core/notif_targets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const obj = JSON.parse(text())
                root.notifTargets = {
                    "apps": (obj && typeof obj.apps === "object") ? obj.apps : ({}),
                    "types": (obj && typeof obj.types === "object") ? obj.types : ({}),
                    "url": (obj && typeof obj.url === "string") ? obj.url : "Browser"
                }
            } catch (e) {}
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
        anchors.topMargin: Theme.space4
        anchors.leftMargin: Theme.space4
        anchors.rightMargin: Theme.space4
        height: 30

        Text {
            text: "Réglages · " + root.hostName
            color: Theme.fg
            font.pixelSize: Theme.textLg
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

            Icon {
                anchors.centerIn: parent
                glyph: "close"
                size: Theme.iconSm
                color: closeMa.containsMouse ? Theme.bg : Theme.error
                opacityLevel: 1
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
    // SECTION 3: RECHERCHE & RAIL DE NAVIGATION
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: searchBar
        anchors.top: panelHeader.bottom
        anchors.topMargin: Theme.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.space4
        anchors.rightMargin: Theme.space4
        height: 34
        radius: Theme.globalRadius
        color: Theme.surfaceVariant
        border.color: searchInput.activeFocus ? Theme.accent : Qt.alpha(Theme.fg, 0.08)
        border.width: 1

        Icon {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            glyph: "search"
            size: Theme.iconSm
            color: Theme.accent
            opacityLevel: 0.9
        }

        TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: Theme.space2
            anchors.right: parent.right
            anchors.rightMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.textSm
            selectByMouse: true
            clip: true

            onTextChanged: {
                root.searchQuery = text
                root.updateSearch(text)
            }

            // Le tiroir s'ouvre pour chercher : le champ prend le focus clavier
            // dès l'affichage, sinon la surface layer n'obtient jamais
            // l'interactivité clavier (WlrKeyboardFocus.OnDemand).
            Connections {
                target: Theme
                function onConfigPanelVisibleChanged() {
                    if (Theme.configPanelVisible) searchInput.forceActiveFocus()
                }
            }

            Component.onCompleted: {
                if (Theme.configPanelVisible) forceActiveFocus()
            }

            Keys.onEscapePressed: {
                if (text !== "") { text = ""; root.searchResults = [] }
                else Theme.configPanelVisible = false
            }
            Keys.onDownPressed: {
                if (root.searchResults.length > 0) searchResultsCol.currentIndex = 0
            }
            // TextInput consomme la touche Entrée (signal accepted) : c'est ici
            // qu'il faut sauter au premier résultat, pas dans Keys.onReturnPressed.
            onAccepted: {
                if (root.searchResults.length > 0) root.jumpToResult(root.searchResults[0])
            }
        }

        Text {
            visible: searchInput.text === ""
            anchors.left: searchInput.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Rechercher un réglage…"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Theme.textSm
        }
    }

    // Résultats de recherche, posés sous le champ, par-dessus le contenu.
    Rectangle {
        id: searchResultsCol
        property int currentIndex: -1
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.space1
        anchors.left: searchBar.left
        anchors.right: searchBar.right
        height: resultsCol.height + 8
        radius: Theme.globalRadius
        color: Theme.surfaceVariant
        border.color: Theme.accentMuted
        border.width: 1
        z: 20
        visible: root.searchResults.length > 0

        Column {
            id: resultsCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 1

            Repeater {
                model: root.searchResults

                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool active: resultMa.containsMouse || searchResultsCol.currentIndex === index

                    width: parent.width
                    height: 28
                    radius: Theme.globalRadius
                    color: active ? Theme.accent : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.space4
                        text: modelData.label
                        color: parent.active ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: resultMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.jumpToResult(modelData)
                    }
                }
            }
        }
    }

    // Rail vertical d'onglets : 4 icônes, libellé au survol.
    Column {
        id: navRail
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.space3
        anchors.left: parent.left
        anchors.leftMargin: Theme.space3
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space4
        width: 40
        spacing: Theme.space2
        z: 5

        Repeater {
            model: [
                { icon: "palette", label: "Esthétique" },
                { icon: "widgets", label: "Widgets" },
                { icon: "monitor", label: root.isLaptop ? "Système & TV" : "Système & Écrans" },
                { icon: "keyboard", label: "Contrôles" },
                { icon: "rocket", label: "Applications" },
                { icon: "lock", label: "Connexion" }
            ]

            Rectangle {
                id: railBtn
                required property int index
                required property var modelData
                readonly property bool active: root.currentTab === index

                width: 40
                height: 36
                radius: Theme.globalRadius
                color: active
                    ? Theme.accent
                    : (railMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55))
                border.color: active ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Icon {
                    anchors.centerIn: parent
                    glyph: railBtn.modelData.icon
                    size: Theme.iconMd
                    color: railBtn.active ? Theme.bg : Theme.fg
                    opacityLevel: railBtn.active ? 1 : 0.78
                }

                MouseArea {
                    id: railMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.currentTab = railBtn.index
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 4: TAB CONTENT AREA (Scrollable & Clipped)
    // ────────────────────────────────────────────────────────────────────────
    Item {
        id: tabContentArea
        anchors.top: navRail.top
        anchors.left: navRail.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space4
        anchors.bottomMargin: Theme.space4
        clip: true

        Flickable {
            id: mainFlickable
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: {
                if (root.currentTab === 0) return tabEsthetiqueCol.implicitHeight
                if (root.currentTab === 1) return tabWidgetsCol.implicitHeight
                if (root.currentTab === 2) return tabSystemeCol.implicitHeight
                if (root.currentTab === 3) return tabControlesCol.implicitHeight
                if (root.currentTab === 4) return tabAppsCol.implicitHeight
                if (root.currentTab === 5) return greeterTabLoader.item
                    ? greeterTabLoader.item.implicitHeight : 0
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
                objectName: "secTheme"
                title: "Thème & Fond d'écran"
                icon: "palette"
                expanded: root.sectionOpen("esthetique_theme", true)
                onToggled: expanded => root.setPanelSection("esthetique_theme", expanded)

                Text {
                    text: "Jeux de couleurs & Fond d'écran"
                    color: Theme.accent
                    font.pixelSize: Theme.textLg
                    font.bold: true
                    width: parent.width
                }

            Column {
                width: parent.width
                spacing: 8

            Row {
                width: parent.width
                spacing: 8

                Repeater {
                    model: ["dynamic", "tokyo-night", "catppuccin"]
                    Rectangle {
                        required property string modelData
                        readonly property bool isCurrent: Theme.activeTheme === modelData

                        width: 100
                        height: 32
                        radius: Theme.globalRadius
                        color: isCurrent ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: isCurrent ? 1 : 0

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.isCurrent ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textSm
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
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: 135
                    height: 32
                    radius: Theme.globalRadius
                    color: wpPickMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Fonds d'écran"
                        color: wpPickMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
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
                        text: "Synchroniser Matugen"
                        color: matugenMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
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
            }

            // Matugen scheme & contrast (regenerates the dynamic palette from the current wallpaper)
            Column {
                id: matugenRow   // ancre de recherche
                objectName: "matugenRow"
                width: parent.width
                spacing: 6

                Text {
                    width: parent.width
                    text: "Schéma Matugen :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Row {
                    // Pastilles centrées sous leur libellé (elles tiennent sur une
                    // seule ligne) : largeur implicite, pas width: parent.width.
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

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
                                            font.pixelSize: Theme.textXs
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
}

            Column {
                width: parent.width
                spacing: 6

                Text {
                    width: parent.width
                    text: "Contraste :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Row {
                    // Pastilles centrées sous leur libellé (elles tiennent sur une
                    // seule ligne) : largeur implicite, pas width: parent.width.
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                Repeater {
                                    model: [
                                        // Les libellés décrivent la saturation : Pastel = moins saturé (+0.8),
                                        // Max = plus saturé (-0.8).
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
                                            font.pixelSize: Theme.textXs
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
}

            // Même respiration de 10 px que devant les barres d'ajout.
            Item { width: 1; height: 10 }

            // Wallpaper Directory Path
            Row {
                id: wallpaperDirRow   // ancre de recherche
                objectName: "wallpaperDirRow"
                spacing: 8
                width: parent.width

                Text {
                    width: 145
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpapers"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                }

                Rectangle {
                    width: parent.width - 145 - 85 - 2 * 8
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
                        font.pixelSize: Theme.textXs
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
                        font.pixelSize: Theme.textXs
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

            // 2 px de respiration entre les deux dossiers : sans cet item, les
            // deux champs se lisent comme une seule ligne à deux étages.
            Item { width: 1; height: 2 }

            // Dossier des captures d'écran (lu par core/screenshot.sh)
            Row {
                id: screenshotsDirRow   // ancre de recherche
                objectName: "screenshotsDirRow"
                spacing: 8
                width: parent.width

                Text {
                    width: 145
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Screenshots"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                }

                Rectangle {
                    width: parent.width - 145 - 85 - 2 * 8
                    height: 28
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: shotsDirInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1
                    clip: true

                    TextInput {
                        id: shotsDirInput
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        text: Theme.screenshotsDir || root.screenshotsDir
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                        onAccepted: {
                            if (shotsDirInput.text.trim() !== "") {
                                root.runConfigCmd(["style", "screenshots_dir", shotsDirInput.text.trim()])
                            }
                        }
                    }
                }

                Rectangle {
                    width: 85
                    height: 28
                    radius: Theme.globalRadius
                    color: shotsDirSaveMa.containsMouse ? Theme.accentMuted : Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Appliquer"
                        color: Theme.bg
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        id: shotsDirSaveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (shotsDirInput.text.trim() !== "") {
                                root.runConfigCmd(["style", "screenshots_dir", shotsDirInput.text.trim()])
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 10 }

            // 2. Active Palette Swatches & Custom Color Override
            Text {
                width: parent.width
                text: "Palette active — cliquer une pastille pour ajuster son hex"
                color: Theme.accent
                font.pixelSize: Theme.textMd
                font.bold: true
                elide: Text.ElideRight
            }

            Row {
                width: parent.width
                spacing: 8

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
                            font.pixelSize: Theme.textXs
                        }
                    }
                }

            }

                    Column {
                        spacing: 4

                        Text {
                            text: "Clé : " + root.selectedColorKey
                            color: Theme.accentMuted
                            font.pixelSize: Theme.textXs
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
                                    font.pixelSize: Theme.textXs
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
                                    font.pixelSize: Theme.textXs
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
            }   // end CollapsibleSection secTheme

            // 3. Desktop Aspect: Gaps, Borders, Rounding, Opacity, Blur, Bar (catégorie technique)
            CollapsibleSection {
                id: secAspect
                title: "Hyprland"
                icon: "cog"
                expanded: root.sectionOpen("esthetique_aspect", true)
                onToggled: expanded => root.setPanelSection("esthetique_aspect", expanded)

            Grid {
                width: parent.width
                columns: 1
                columnSpacing: 14
                rowSpacing: 12

                // 1. Gaps In
                Row {
                    id: gapsRow   // ancre de recherche
                    objectName: "gapsRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gaps internes (in) :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gaps externes (out) :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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
                    id: borderRow   // ancre de recherche
                    objectName: "borderRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bordures fenêtres :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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
                    id: roundingWinRow   // ancre de recherche
                    objectName: "roundingWinRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Arrondis fenêtres :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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

                // 4 bis. Forme des coins (decoration:rounding_power) : ce n'est pas
                // le rayon mais la courbe. 2 = arc de cercle ; en dessous le coin se
                // redresse jusqu'au chanfrein, au-dessus il s'arrondit en « squircle ».
                Row {
                    id: roundingPowerRow   // ancre de recherche
                    objectName: "roundingPowerRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Forme des coins :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    // Stepper comme les bordures : clic ou molette au dixième. Le
                    // suffixe vit à côté plutôt que dans le compteur, où « coupe
                    // droite » déborderait entre les deux boutons.
                    // Deux valeurs utiles seulement : 1 coupe le coin en droite,
                    // 2 trace un arc. Au-delà, Hyprland ne fait qu'arrondir la
                    // transition vers le carré, ce qui ne se distingue pas à l'œil.
                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.hyprRoundingPower
                        minimumValue: 1
                        maximumValue: 2
                        stepSize: 1
                        onValueModified: newVal => {
                            root.hyprRoundingPower = newVal
                            root.runConfigCmd(["style", "hypr_rounding_power", String(newVal)])
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hyprRoundingPower < 2 ? "coupe droite" : "cercle"
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Theme.textXs
                    }
                }

                // 7. Pas de redimensionnement clavier
                Row {
                    id: resizeRow   // ancre de recherche
                    objectName: "resizeRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pas redimensionnement :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Slider {
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

            }   // fin Grid aspect (gaps, arrondis, opacité, barre)

            Grid {
                width: parent.width
                columns: 1
                columnSpacing: 14
                rowSpacing: 12

                // 8. Opacité des fenêtres (decoration.active_opacity)
                Row {
                    id: winOpacityRow   // ancre de recherche
                    objectName: "winOpacityRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Opacité fenêtres :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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

                // 9. Taille du flou
                Row {
                    id: blurRow   // ancre de recherche
                    objectName: "blurRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Taille du flou :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Slider {
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

                // 10. Passes du flou
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Passes du flou :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
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

                // 11. Flou des fenêtres (Actif / Désactivé)
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Flou Hyprland :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 26
                        radius: Theme.globalRadius
                        color: root.blurEnabled ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.blurEnabled ? "✓ Flou Actif" : "✕ Désactivé"
                            color: root.blurEnabled ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
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

            }   // fin Grid fenêtres

        }   // end CollapsibleSection secAspect

        // 4. Surfaces dessinées par Quickshell : îlots, barre, panneau, popups.
        CollapsibleSection {
            id: secShell
            title: "Quickshell"
            icon: "widgets"
            expanded: root.sectionOpen("esthetique_quickshell", true)
            onToggled: expanded => root.setPanelSection("esthetique_quickshell", expanded)

            Grid {
                width: parent.width
                columns: 1
                columnSpacing: 14
                rowSpacing: 12

                // 5. Arrondis îlots (Quickshell)
                Row {
                    id: roundingIslandRow   // ancre de recherche
                    objectName: "roundingIslandRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Arrondis îlots (QS) :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Slider {
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

                // 6. Hauteur de barre
                Row {
                    id: barHeightRow   // ancre de recherche
                    objectName: "barHeightRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hauteur de barre :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Slider {
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

            }

            Grid {
                width: parent.width
                columns: 1
                columnSpacing: 14
                rowSpacing: 12

                // 12. Opacité des surfaces Quickshell (barre, OSD, panneau, popups)
                Row {
                    id: shellOpacityRow   // ancre de recherche
                    objectName: "shellOpacityRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Opacité surfaces :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Theme.shellOpacity
                        minimumValue: 0.20
                        maximumValue: 1.00
                        stepSize: 0.05
                        decimals: 2
                        textFormatter: v => Math.round(v * 100) + " %"
                        onValueModified: newVal => {
                            root.runConfigCmd(["style", "shell_opacity", String(newVal)])
                        }
                    }
                }

                // 13. Flou des surfaces du shell (barre, OSD, panneau)
                Row {
                    id: shellBlurRow   // ancre de recherche
                    objectName: "shellBlurRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Flou Quickshell :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 26
                        radius: Theme.globalRadius
                        color: root.shellBlurEnabled ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.shellBlurEnabled ? "✓ Flou Actif" : "✕ Désactivé"
                            color: root.shellBlurEnabled ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.shellBlurEnabled = !root.shellBlurEnabled
                                root.runConfigCmd(["style", "shell_blur_enabled", root.shellBlurEnabled ? "true" : "false"])
                            }
                        }
                    }
                }

                // 14. Seuil de transparence (ignore_alpha)
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Seuil de flou :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.shellBlurAlpha
                        minimumValue: 0.05
                        maximumValue: 0.9
                        stepSize: 0.05
                        decimals: 2
                        onValueModified: newVal => {
                            root.shellBlurAlpha = newVal
                            root.runConfigCmd(["style", "shell_blur_alpha", String(newVal)])
                        }
                    }
                }

                // 14b. Bordure de la barre du haut (capsule fusionnée et îlots)
                Row {
                    id: barBorderRow   // ancre de recherche
                    objectName: "barBorderRow"
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bordure de la barre :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 26
                        radius: Theme.globalRadius
                        color: root.barBorder ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.barBorder ? "✓ Bordure" : "✕ Sans bordure"
                            color: root.barBorder ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.barBorder = !root.barBorder
                                root.runConfigCmd(["style", "bar_border", root.barBorder ? "true" : "false"])
                            }
                        }
                    }
                }

                // 15. Flou derrière les popups ancrés (calendrier, wifi, volume…)
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Flou des popups :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 26
                        radius: Theme.globalRadius
                        color: root.shellBlurPopups ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.shellBlurPopups ? "✓ Flou Actif" : "✕ Désactivé"
                            color: root.shellBlurPopups ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.shellBlurPopups = !root.shellBlurPopups
                                root.runConfigCmd(["style", "shell_blur_popups", root.shellBlurPopups ? "true" : "false"])
                            }
                        }
                    }
                }
            }   // fin Grid shell

            Text {
                width: parent.width
                topPadding: 8
                text: "Ces réglages ne concernent que les surfaces du shell (barre, OSD, panneau, popups) ; "
                    + "l'opacité et le flou des fenêtres se règlent à part, au-dessus. "
                    + "La taille et les passes du flou restent communes aux deux, d'où un rendu plus ou moins diffus de part et d'autre. "
                    + "Le seuil doit rester sous l'opacité des surfaces : au-dessus, Hyprland cesse de flouter."
                color: Theme.fg
                opacity: 0.6
                font.pixelSize: Theme.textXs
                wrapMode: Text.WordWrap
            }

            Grid {
                width: parent.width
                columns: 1
                columnSpacing: 14
                rowSpacing: 12
                topPadding: 12

                // 16. Bouton central (engrenage) — bascule d'affichage
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: 160
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bouton central :"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 160
                        height: 26
                        radius: Theme.globalRadius
                        color: Theme.showConfigButton ? Theme.accent : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Theme.showConfigButton ? "✓ Affiché" : "Masqué (SUPER+H)"
                            color: Theme.showConfigButton ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
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
        }   // end CollapsibleSection secShell
    }   // end Column tabEsthetiqueCol

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 1: WIDGETS DU BUREAU (sur les workspaces, réglages par widget)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabWidgetsCol
            visible: root.currentTab === 1
            width: mainFlickable.width
            spacing: 11

            CollapsibleSection {
                id: secWidgets
                objectName: "secWidgets"
                title: "Widgets du bureau"
                icon: "widgets"
                expanded: true

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: parent.width
                        text: root.widgetsList.length === 0
                              ? "Aucun widget. Le bureau affiche le fond d'écran seul."
                              : "Chaque widget vit derrière les fenêtres, sur son workspace. "
                                + "Pour le déplacer : SUPER + SHIFT + clic dessus, puis clic pour le poser."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.widgetsList

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property string wid: modelData.id || ""
                            readonly property string wtype: modelData.type || ""
                            readonly property int wWorkspace: Number(modelData.workspace) || 0
                            readonly property real wOpacity: modelData.opacity !== undefined
                                                              ? Number(modelData.opacity) : 0.35
                            readonly property bool wEnabled: modelData.enabled !== false
                            readonly property bool wBlur: modelData.blur !== false
                            readonly property bool wBorder: modelData.border !== false
                            readonly property var wOptions: modelData.options || ({})
                            readonly property bool wSeconds: {
                                const v = widgetCard.wOptions.seconds
                                return v === true || v === "true" || v === 1 || v === "1"
                            }
                            readonly property string wCity: widgetCard.wOptions.city
                                ? String(widgetCard.wOptions.city) : ""
                            // Widgets qui interrogent un service : minutes entre deux
                            // requêtes (5 par défaut, comme le service lui-même).
                            readonly property int wRefreshMin: {
                                const v = Number(widgetCard.wOptions.refresh_min)
                                return (v >= 1 && v <= 120) ? Math.round(v) : 5
                            }

                            width: parent.width
                            height: wcol.implicitHeight + 20
                            radius: Theme.globalRadius
                            color: Qt.alpha(Theme.surfaceVariant, 0.55)
                            border.width: 1
                            border.color: Theme.surfaceVariant

                            Column {
                                id: wcol
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                // Ligne 1 : type, identifiant, suppression
                                Row {
                                    width: parent.width
                                    spacing: Theme.space2

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: widgetCard.wtype === "date" ? "calendar"
                                               : (widgetCard.wtype === "meteo" ? "cloud"
                                               : (widgetCard.wtype === "musique" ? "music"
                                               : (widgetCard.wtype === "combo" ? "widgets" : "clock")))
                                        size: Theme.iconSm
                                        color: Theme.accent
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 14 - 18 - Theme.space2 * 2
                                        text: widgetCard.wtype.charAt(0).toUpperCase()
                                              + widgetCard.wtype.slice(1) + "  ·  " + widgetCard.wid
                                        color: Theme.fg
                                        font.pixelSize: Theme.textSm
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    // Suppression : la croix seule. Le libellé « Retirer » et
                                    // son ancre à droite dans la Row cassaient la mise en page.
                                    Text {
                                        id: removeIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        horizontalAlignment: Text.AlignRight
                                        text: "✕"
                                        color: removeMa.containsMouse ? Theme.error
                                                                     : Qt.alpha(Theme.error, 0.80)
                                        font.pixelSize: Theme.textSm

                                        MouseArea {
                                            id: removeMa
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.runConfigCmd(["widget_remove", widgetCard.wid])
                                        }
                                    }
                                }

                                // Ligne 2 : workspace et position
                                Row {
                                    width: parent.width
                                    spacing: Theme.space2

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 76
                                        text: "Workspace"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.textXs
                                    }
                                    Stepper {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 120
                                        value: widgetCard.wWorkspace
                                        minimumValue: 0
                                        maximumValue: 5
                                        stepSize: 1
                                        textFormatter: v => v === 0 ? "Tous" : String(v)
                                        onValueModified: newVal =>
                                            root.runConfigCmd(["widget_set", widgetCard.wid, "workspace", String(newVal)])
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "x"
                                        color: Qt.alpha(Theme.fg, 0.55)
                                        font.pixelSize: Theme.textXs
                                    }
                                    Stepper {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 104
                                        value: Number(widgetCard.modelData.x) || 0
                                        minimumValue: 0
                                        maximumValue: 1800
                                        stepSize: 10
                                        onValueModified: newVal =>
                                            root.runConfigCmd(["widget_move", widgetCard.wid, String(newVal), String(Number(widgetCard.modelData.y) || 0)])
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "y"
                                        color: Qt.alpha(Theme.fg, 0.55)
                                        font.pixelSize: Theme.textXs
                                    }
                                    Stepper {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 104
                                        value: Number(widgetCard.modelData.y) || 0
                                        minimumValue: 0
                                        maximumValue: 1000
                                        stepSize: 10
                                        onValueModified: newVal =>
                                            root.runConfigCmd(["widget_move", widgetCard.wid, String(Number(widgetCard.modelData.x) || 0), String(newVal)])
                                    }
                                }

                                // Ligne 3 : opacité, puis les trois interrupteurs
                                Row {
                                    width: parent.width
                                    spacing: Theme.space2

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 56
                                        text: "Fond"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.textXs
                                    }
                                    Slider {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 56 - 240 - Theme.space2 * 3
                                        value: widgetCard.wOpacity
                                        minimumValue: 0.0
                                        maximumValue: 1.0
                                        stepSize: 0.05
                                        decimals: 2
                                        onValueModified: newVal =>
                                            root.runConfigCmd(["widget_set", widgetCard.wid, "opacity", String(newVal)])
                                    }

                                    Repeater {
                                        model: [
                                            { key: "enabled", label: "Actif",   on: widgetCard.wEnabled },
                                            { key: "border",  label: "Bordure", on: widgetCard.wBorder },
                                            { key: "blur",    label: "Flou",    on: widgetCard.wBlur }
                                        ]

                                        Rectangle {
                                            required property var modelData
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 72
                                            height: 24
                                            radius: Theme.globalRadius
                                            color: modelData.on ? Theme.accent : Theme.surfaceVariant
                                            border.width: 1
                                            border.color: Theme.accent

                                            Text {
                                                anchors.centerIn: parent
                                                text: (modelData.on ? "✓ " : "✕ ") + modelData.label
                                                color: modelData.on ? Theme.bg : Theme.fg
                                                font.pixelSize: Theme.text2xs
                                                font.bold: true
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.runConfigCmd([
                                                    "widget_set", widgetCard.wid,
                                                    modelData.key, modelData.on ? "false" : "true"
                                                ])
                                            }
                                        }
                                    }
                                }

                                // Ligne 4 : options propres au type de widget. La ville
                                // vide retombe sur `weather_city` de style_vars.json.
                                Row {
                                    width: parent.width
                                    spacing: Theme.space2

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 56
                                        text: "Options"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.textXs
                                    }

                                    // Les secondes ne concernent que les widgets qui
                                    // affichent une horloge.
                                    Rectangle {
                                        visible: widgetCard.wtype === "horloge"
                                                 || widgetCard.wtype === "combo"
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 86
                                        height: 24
                                        radius: Theme.globalRadius
                                        color: widgetCard.wSeconds ? Theme.accent : Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: (widgetCard.wSeconds ? "✓ " : "✕ ") + "Secondes"
                                            color: widgetCard.wSeconds ? Theme.bg : Theme.fg
                                            font.pixelSize: Theme.text2xs
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.runConfigCmd([
                                                "widget_set", widgetCard.wid, "seconds",
                                                widgetCard.wSeconds ? "false" : "true"
                                            ])
                                        }
                                    }

                                    // La ville ne concerne que la météo : elle
                                    // s'affichait sur tous les autres widgets, avec son
                                    // « Auto (IP) » qui n'y veut rien dire.
                                    Row {
                                        visible: widgetCard.wtype === "deepseek"
                                                 || widgetCard.wtype === "ollama"
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Rafraîchissement"
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: Theme.text2xs
                                        }

                                        Stepper {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 108
                                            value: widgetCard.wRefreshMin
                                            minimumValue: 1
                                            maximumValue: 120
                                            stepSize: 1
                                            suffix: " min"
                                            onValueModified: newVal =>
                                                root.runConfigCmd(["widget_set", widgetCard.wid,
                                                                   "refresh_min", String(newVal)])
                                        }
                                    }

                                    Rectangle {
                                        visible: widgetCard.wtype === "meteo"
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 170
                                        height: 24
                                        radius: Theme.globalRadius
                                        color: Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.surfaceVariant

                                        TextInput {
                                            id: cityInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 7
                                            anchors.rightMargin: 7
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: widgetCard.wCity
                                            color: Theme.fg
                                            font.pixelSize: Theme.textXs
                                            selectByMouse: true
                                            onAccepted: root.runConfigCmd([
                                                "widget_set", widgetCard.wid, "city", cityInput.text
                                            ])
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 7
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: cityInput.text === ""
                                            // Champ vide = géolocalisation par IP.
                                            text: "Auto (IP)"
                                            color: Qt.alpha(Theme.fg, 0.42)
                                            font.pixelSize: Theme.textXs
                                        }
                                    }
                                }
                            }

                            id: widgetCard
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

                    // Widgets disponibles : une case par nature, cochée quand le
                    // widget est posé. Trois colonnes dans une zone qui défile à
                    // la molette : cinq pastilles côte à côte débordaient du
                    // panneau et la dernière (« + Musique ») était rognée.
                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Text {
                            width: 76
                            text: "Widgets"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                            topPadding: 6
                        }

                        Item {
                            width: parent.width - 76 - Theme.space2
                            // Trois rangées visibles (28 px + 6 d'écart), puis on
                            // fait défiler à la molette quand la liste grandit.
                            height: Math.min(gridPicker.implicitHeight, 3 * 28 + 2 * 6 + 2)

                            Flickable {
                                id: widgetPicker
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.rightMargin: 7
                                anchors.top: parent.top
                                height: parent.height
                                contentWidth: width
                                contentHeight: gridPicker.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Grid {
                                    id: gridPicker
                                    width: widgetPicker.width
                                    columns: 3
                                    rowSpacing: 6
                                    columnSpacing: 6

                                    Repeater {
                                        model: root.widgetTypeRows

                                        Rectangle {
                                            id: typeCell
                                            required property var modelData
                                            width: (gridPicker.width - 2 * gridPicker.columnSpacing) / 3
                                            height: 28
                                            radius: Theme.globalRadius
                                            color: modelData.present
                                                ? Qt.alpha(Theme.accent, 0.16) : Theme.surfaceVariant
                                            border.width: 1
                                            border.color: modelData.present
                                                ? Theme.accent : Theme.surfaceVariant

                                            Row {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                anchors.right: parent.right
                                                anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6

                                                Rectangle {
                                                    width: 12
                                                    height: 12
                                                    radius: 3
                                                    color: typeCell.modelData.present
                                                        ? Theme.accent : "transparent"
                                                    border.width: 1
                                                    border.color: typeCell.modelData.present
                                                        ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: typeCell.modelData.present
                                                        text: "✓"
                                                        color: Theme.bg
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                    }
                                                }

                                                Text {
                                                    width: parent.width - 18
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: typeCell.modelData.label
                                                    color: Theme.fg
                                                    font.pixelSize: Theme.textXs
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleWidgetType(typeCell.modelData.type,
                                                                                typeCell.modelData.present)
                                            }
                                        }
                                    }
                                }
                            }

                            // Repère de défilement : n'apparaît que si la liste
                            // dépasse les trois rangées visibles.
                            Rectangle {
                                visible: gridPicker.implicitHeight > widgetPicker.height
                                width: 3
                                radius: 2
                                color: Qt.alpha(Theme.accent, 0.45)
                                x: parent.width - 4
                                height: Math.max(18, widgetPicker.height * widgetPicker.height
                                                     / Math.max(1, gridPicker.implicitHeight))
                                y: widgetPicker.contentY + widgetPicker.contentY
                                     * (widgetPicker.height - height)
                                     / Math.max(1, gridPicker.implicitHeight - widgetPicker.height)
                            }
                        }
                    }

                    // Le lanceur : intégré, position parmi six emplacements
                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "search"
                            size: Theme.iconSm
                            color: Theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 320
                            text: "Lanceur — intégré, position fixe"
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: [
                                { key: "haut-gauche", tip: "↖" },
                                { key: "haut-centre", tip: "↑" },
                                { key: "haut-droit",  tip: "↗" },
                                { key: "bas-gauche",  tip: "↙" },
                                { key: "bas-centre",  tip: "↓" },
                                { key: "bas-droit",   tip: "↘" }
                            ]

                            Rectangle {
                                required property var modelData
                                width: 30
                                height: 26
                                radius: Theme.globalRadius
                                color: root.launcherPosition === modelData.key ? Theme.accent : Theme.surfaceVariant
                                border.width: 1
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.tip
                                    color: root.launcherPosition === modelData.key ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textSm
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["style", "launcher_position", modelData.key])
                                }
                            }
                        }
                    }
                }
            }

            // Accès API : les widgets qui interrogent un service externe ont besoin
            // d'une clé. Elle est rangée dans secrets.json (mode 600) et le panneau
            // ne montre jamais que ses derniers caractères.
            CollapsibleSection {
                id: secApiKeys
                objectName: "secApiKeys"
                title: "Accès API"
                icon: "lock"
                expanded: root.sectionOpen("widgets_api", false)
                onToggled: expanded => root.setPanelSection("widgets_api", expanded)

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Une ligne par fournisseur LLM (core/llm_providers.json). La clé est "
                            + "rangée dans core/secrets.json et n'apparaît jamais en clair."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    // Une ligne par fournisseur déclaré : plus de bloc à recopier
                    // quand on ajoute OpenAI, Claude ou Gemini.
                    Repeater {
                        model: root.llmProviders

                        Column {
                            id: fournisseur
                            required property var modelData
                            width: parent.width
                            spacing: 6
                            // L'état est par fournisseur : « clé refusée » doit
                            // rester sous la ligne qui a échoué.
                            readonly property string etat: root.cleEtats[modelData.id] || ""

                            Text {
                                width: parent.width
                                text: modelData.label + " — " + (modelData.summary || "") + "."
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                wrapMode: Text.WordWrap
                            }

                            Row {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: parent.width - 130
                                    height: 32
                                    color: Theme.bg
                                    radius: Theme.globalRadius
                                    border.color: champ.activeFocus ? Theme.accent : Theme.surfaceVariant
                                    border.width: 1

                                    TextInput {
                                        id: champ
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.info
                                        font.pixelSize: Theme.textSm
                                        echoMode: TextInput.Password
                                        selectByMouse: true
                                        onAccepted: root.enregistrerCleApi(fournisseur.modelData, champ)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        visible: champ.text.length === 0
                                        text: root.apiKeys[fournisseur.modelData.key]
                                              ? "Clé enregistrée (…" + root.apiKeys[fournisseur.modelData.key].tail + ")"
                                              : (fournisseur.modelData.hint || "clé d'API")
                                        color: Qt.alpha(Theme.fg, 0.45)
                                        font.pixelSize: Theme.textXs
                                    }
                                }

                                Rectangle {
                                    width: 120
                                    height: 32
                                    radius: Theme.globalRadius
                                    color: enregistrerCle.containsMouse ? Theme.accentMuted : Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Enregistrer"
                                        color: Theme.bg
                                        font.pixelSize: Theme.textSm
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: enregistrerCle
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.enregistrerCleApi(fournisseur.modelData, champ)
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: fournisseur.etat !== ""
                                text: fournisseur.etat
                                color: (fournisseur.etat.startsWith("clé acceptée")
                                        || fournisseur.etat.startsWith("enregistrée"))
                                       ? Theme.success : Theme.error
                                font.pixelSize: Theme.textXs
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 2: SYSTÈME & ÉCRANS (Adaptatif : Tour Station vs Laptop Portable)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabSystemeCol
            visible: root.currentTab === 2
            width: mainFlickable.width
            spacing: 12

            Text {
                width: parent.width
                text: "Moniteurs détectés (" + root.hostName + ") — cliquer pour sélectionner un écran"
                color: Theme.accent
                font.pixelSize: Theme.textLg
                font.bold: true
                wrapMode: Text.WordWrap
            }

            // Dynamic list of connected monitors (e.g. HDMI-A-1 on Station, DP-1 / eDP-1 on Portable)
            Row {
                id: monitorsRow   // ancre de recherche
                objectName: "monitorsRow"
                spacing: 10
                width: parent.width

                Repeater {
                    model: root.monitorsList

                    Rectangle {
                        id: monCard
                        required property var modelData
                        readonly property bool isSel: root.selectedMonitorName === modelData.name
                        width: (parent.width - 10 * Math.max(0, root.monitorsList.length - 1))
                               / Math.max(1, root.monitorsList.length)
                        height: 54
                        radius: Theme.globalRadius
                        color: isSel ? Qt.alpha(Theme.accent, 0.22) : Theme.surfaceVariant
                        border.color: isSel ? Theme.accent : Theme.accentMuted
                        border.width: isSel ? 2 : 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6
                                Text {
                                    text: monCard.modelData.name + " (" + monCard.modelData.width + "x" + monCard.modelData.height + "@" + monCard.modelData.refreshRate + "Hz)"
                                    color: monCard.isSel ? Theme.accent : Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: !!monCard.modelData.is_primary
                                    width: 52
                                    height: 16
                                    radius: 3
                                    color: Theme.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Principal"
                                        color: Theme.bg
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: monCard.modelData.description || "Sortie vidéo active"
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: Theme.textXs
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

            // Statut / Action Écran Principal
            Rectangle {
                visible: root.monitorsList.length > 1
                width: parent.width
                height: 32
                radius: Theme.globalRadius
                readonly property bool isSelectedPrimary: root.currentMonitorObj && !!root.currentMonitorObj.is_primary
                color: isSelectedPrimary ? Qt.alpha(Theme.accent, 0.12) : (makePrimMa.containsMouse ? Theme.accent : Theme.surfaceVariant)
                border.color: Theme.accent
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Icon {
                        glyph: "check"
                        size: Theme.iconSm
                        color: parent.parent.isSelectedPrimary ? Theme.accent : (makePrimMa.containsMouse ? Theme.bg : Theme.accent)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.parent.isSelectedPrimary
                            ? "« " + root.selectedMonitorName + " » est l'écran principal (Workspaces 1 à 5)"
                            : "Définir « " + root.selectedMonitorName + " » comme écran principal"
                        color: parent.parent.isSelectedPrimary ? Theme.accent : (makePrimMa.containsMouse ? Theme.bg : Theme.fg)
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }
                }

                MouseArea {
                    id: makePrimMa
                    anchors.fill: parent
                    enabled: !parent.isSelectedPrimary
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.runConfigCmd(["monitor_primary", root.selectedMonitorName])
                }
            }

            // Resolution & Refresh Rate Dropdown Selector
            Text {
                width: parent.width
                text: "Résolution & Fréquence pour « " + root.selectedMonitorName + " » :"
                color: Theme.accent
                font.pixelSize: Theme.textMd
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: 4

                // Bouton principal du menu déroulant
                Rectangle {
                    id: resDropdownBtn
                    width: parent.width
                    height: 36
                    radius: Theme.globalRadius
                    color: resBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Theme.surfaceVariant
                    border.color: root.resDropdownOpen ? Theme.accent : Theme.accentMuted
                    border.width: 1

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Icon {
                            glyph: "monitor"
                            size: Theme.iconSm
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const m = root.currentMonitorObj
                                return m ? ("Mode actif : " + m.width + "x" + m.height + "@" + m.refreshRate + "Hz") : "Auto (Preferred)"
                            }
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }
                    }

                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.resDropdownOpen ? "chevron-up" : "chevron-down"
                        size: Theme.iconSm
                        color: Theme.accent
                    }

                    MouseArea {
                        id: resBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resDropdownOpen = !root.resDropdownOpen
                    }
                }

                // Liste déroulante des modes
                Rectangle {
                    visible: root.resDropdownOpen
                    width: parent.width
                    height: Math.min(220, resCol.height + 8)
                    radius: Theme.globalRadius
                    color: Theme.surface
                    border.color: Theme.accent
                    border.width: 1
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 4
                        contentWidth: width
                        contentHeight: resCol.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: resCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.currentMonitorModes

                                Rectangle {
                                    required property string modelData
                                    width: parent.width
                                    height: 30
                                    radius: Theme.globalRadius - 2
                                    readonly property bool isCurrent: {
                                        const m = root.currentMonitorObj
                                        if (!m) return false
                                        if (modelData === "preferred") return false
                                        return modelData === (m.width + "x" + m.height + "@" + m.refreshRate)
                                    }
                                    color: itemMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : (isCurrent ? Qt.alpha(Theme.accent, 0.12) : "transparent")

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Icon {
                                            glyph: isCurrent ? "check" : "chevron-right"
                                            size: 14
                                            color: isCurrent ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData === "preferred" ? "Auto (Preferred)" : (modelData + "Hz")
                                            color: isCurrent ? Theme.accent : Theme.fg
                                            font.pixelSize: Theme.textXs
                                            font.bold: isCurrent
                                        }
                                    }

                                    MouseArea {
                                        id: itemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const curScale = root.currentMonitorObj ? String(root.currentMonitorObj.scale || 1) : "1"
                                            root.runConfigCmd(["monitor_mode", root.selectedMonitorName, modelData, curScale])
                                            root.resDropdownOpen = false
                                        }
                                    }
                                }
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
                    width: parent.width - (3 * 58 + 3 * 10 + 8)
                    text: "Mise à l'échelle (Scale) de " + root.selectedMonitorName + " :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
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
                            font.pixelSize: Theme.textXs
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
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }

                Row {
                    spacing: 8
                    width: parent.width

                    Repeater {
                        model: [
                            { id: "dual", title: "Étendu (TV + laptop)" },
                            { id: "tv", title: "TV uniquement (dock)" },
                            { id: "laptop", title: "Nomade (laptop seul)" }
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
                                font.pixelSize: Theme.textXs
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
                                font.pixelSize: Theme.textXs
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
            Column {
                id: timezoneRow   // ancre de recherche
                objectName: "timezoneRow"
                width: parent.width
                spacing: 8

                Rectangle {
                    width: parent.width
                    height: 46
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: "Fuseau : " + root.timezoneStr
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                        Text {
                            text: root.ntpSynced ? "✓ Horloge NTP synchronisée" : "⚠ NTP non synchronisé"
                            color: root.ntpSynced ? Theme.success : Theme.warn
                            font.pixelSize: Theme.textXs
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 46
                    radius: Theme.globalRadius
                    color: openWifiMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Ouvrir le panneau réseau / WiFi"
                        color: openWifiMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textSm
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
                    width: parent.width
                    height: 46
                    radius: Theme.globalRadius
                    color: root.batLimit80 ? Theme.success : Theme.surfaceVariant
                    border.color: Theme.success
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.batLimit80 ? "Limite 80% : active" : "Activer la limite 80%"
                        color: root.batLimit80 ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
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
        // TAB 3: CONTRÔLES, CLAVIER & RACCOURCIS (binds.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabControlesCol
            visible: root.currentTab === 3
            width: mainFlickable.width
            spacing: 10

            // Top bar: Current Keyboard Layout + Button to reopen First-Run Keyboard Selector
            Rectangle {
                id: kbdRow   // ancre de recherche
                objectName: "kbdRow"
                width: parent.width
                height: 42
                radius: Theme.globalRadius
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 156
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        text: "Disposition active : " + root.kbLayout.toUpperCase()
                        color: Theme.accent
                        font.pixelSize: Theme.textMd
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 140
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
                        text: "Assistant clavier"
                        color: reopenKbMa.containsMouse ? Theme.bg : Theme.accent
                        font.pixelSize: Theme.textXs
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
                width: parent.width
                text: "Raccourcis Hyprland — cliquer une ligne pour l'éditer"
                color: Theme.accent
                font.pixelSize: Theme.textMd
                font.bold: true
                elide: Text.ElideRight
            }

            Flickable {
                width: parent.width
                height: 245
                contentWidth: width
                contentHeight: bindsCol.implicitHeight
                clip: true

                Column {
                    id: bindsCol
                    objectName: "bindsCol"
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
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 36
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Rectangle {
                                    width: 118
                                    height: 22
                                    radius: Theme.globalRadius
                                    color: Theme.bg
                                    border.color: Theme.accentMuted
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.mod + " + " + modelData.key
                                        color: Theme.accent
                                        font.pixelSize: Theme.textXs
                                        font.bold: true
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 118 - 24
                                    text: "→  " + modelData.target
                                    color: Theme.fg
                                    font.pixelSize: Theme.textSm
                                    elide: Text.ElideRight
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
                                    font.pixelSize: Theme.textXs
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
            Column {
                width: parent.width
                spacing: 8

                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: 66
                        height: 32
                        radius: Theme.globalRadius
                        color: Theme.surfaceVariant

                        Text {
                            anchors.centerIn: parent
                            text: "SUPER +"
                            color: Theme.accent
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: parent.width - 66 - 84 - 2 * 8
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
                            font.pixelSize: Theme.textXs
                        }

                        TextInput {
                            id: bindKeyInput
                            anchors.fill: parent
                            anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                        }
                    }

                    Rectangle {
                        width: 84
                        height: 32
                        radius: Theme.globalRadius
                        color: Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Ajouter"
                            color: Theme.bg
                            font.pixelSize: Theme.textSm
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

                Rectangle {
                    width: parent.width
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
                        font.pixelSize: Theme.textXs
                    }

                    TextInput {
                        id: bindCmdInput
                        anchors.fill: parent
                        anchors.margins: 6
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: Theme.textSm
                        onAccepted: {
                            if (bindKeyInput.text !== "" && bindCmdInput.text !== "") {
                                root.runConfigCmd(["bind_set", bindKeyInput.text, bindCmdInput.text])
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 4: VARIABLES DYNAMIQUES & APPLICATIONS (app_vars.json <-> programs.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabAppsCol
            visible: root.currentTab === 4
            width: mainFlickable.width
            spacing: 12

            // Programs par défaut des raccourcis (app_vars.json <-> programs.lua)
            CollapsibleSection {
                id: secApps
                objectName: "secApps"
                title: "Programmes par défaut des raccourcis"
                icon: "rocket"
                expanded: root.sectionOpen("apps_programs", true)
                onToggled: expanded => root.setPanelSection("apps_programs", expanded)

            // Historique des lancements de la pilule (style_vars.json : launch_history)
            Row {
                id: launchHistoryRow
                width: parent.width
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32 - 10
                           - (clearHistBtn.visible ? clearHistBtn.width + 10 : 0)
                    text: "Mémoriser les lancements récents dans la pilule"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: clearHistBtn
                    visible: root.launchHistory
                    width: visible ? clearHistText.implicitWidth + 22 : 0
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        id: clearHistText
                        anchors.centerIn: parent
                        text: "Vider"
                        color: Theme.accent
                        font.pixelSize: Theme.textSm
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearLaunchHistory()
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: root.launchHistory ? Theme.success : Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.launchHistory ? "✓" : "✕"
                        color: root.launchHistory ? Theme.success : Theme.error
                        font.pixelSize: root.launchHistory ? Theme.textMd : Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["style", "launch_history",
                                                      String(!root.launchHistory)])
                    }
                }

            }

            Text {
                text: "Les alias ci-dessous sont aussi proposés par la pilule ; « > » y lance une commande shell."
                color: Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: Theme.textSm
                width: parent.width
                wrapMode: Text.WordWrap
            }

            Text {
                text: "Variables d'Applications par défaut (Synchronisées à la volée avec Hyprland)"
                color: Theme.accent
                font.pixelSize: Theme.textLg
                font.bold: true
                width: parent.width
            }

            Flickable {
                width: parent.width
                // Hauteur calée sur le contenu (plafonnée) : une liste courte ne
                // laisse pas de vide, une liste longue défile sans couper la
                // dernière ligne.
                height: Math.min(appList.implicitHeight, 300)
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
                                width: 84
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    width: parent.width - 16
                                    text: appRow.modelData.alias
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: Theme.textSm
                                    elide: Text.ElideRight
                                }
                            }

                            // Editable Command Field
                            Rectangle {
                                width: appRow.width - 84 - 32 - 32 - 3 * 10 - 4
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
                                    font.pixelSize: Theme.textSm
                                    onAccepted: root.runConfigCmd(["app_set", appRow.modelData.alias, editCmdInput.text])
                                }
                            }

                            // Save Button
                            Rectangle {
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.success
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.success
                                    font.pixelSize: Theme.textMd
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
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: Theme.textSm
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

            // Respiration entre la dernière ligne et la barre d'ajout : un peu
            // plus que l'écart entre deux lignes (8 px) pour séparer le groupe.
            Item { width: 1; height: 10 }

            // Add New Application Variable Row
            Row {
                spacing: 10
                width: parent.width

                Rectangle {
                    width: 110
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
                        text: "Nom"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.textXs
                    }

                    TextInput {
                        id: newAlias
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                    }
                }

                Rectangle {
                    width: parent.width - 110 - 84 - 2 * 10
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
                        text: "Programme"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.textXs
                    }

                    TextInput {
                        id: newCmd
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: Theme.textSm
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
                    width: 84
                    height: 34
                    radius: Theme.globalRadius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: Theme.textSm
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

            // Cible du clic sur le titre d'une notification (core/notif_targets.json).
            // Aucun programme n'est écrit ici : les alias renvoient au tiroir
            // « Programmes par défaut » ci-dessus. Le résolveur relit le fichier à
            // chaque notification, donc une modification est effective tout de suite.
            CollapsibleSection {
                id: secNotifTargets
                objectName: "secNotifTargets"
                title: "Cible du clic sur une notification"
                icon: "history"
                expanded: root.sectionOpen("apps_notif_targets", false)
                onToggled: expanded => root.setPanelSection("apps_notif_targets", expanded)

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Cliquer le titre d'une notification ouvre ce qu'elle annonce. "
                            + "Les fichiers et les liens passent par les alias de « Programmes par défaut » ; "
                            + "une application peut avoir sa propre commande."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    // ── par nature de fichier ────────────────────────────
                    Text {
                        text: "Fichiers détectés dans le texte"
                        color: Theme.accent
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    Repeater {
                        model: root.notifTypeRows

                        Row {
                            id: typeRow
                            required property var modelData
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: 84
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: typeRow.modelData.label
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: Theme.textSm
                                }
                            }

                            Rectangle {
                                width: typeRow.width - 84 - 32 - 2 * 10
                                height: 32
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: typeAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                TextInput {
                                    id: typeAlias
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: typeRow.modelData.alias
                                    color: Theme.info
                                    font.pixelSize: Theme.textSm
                                    onAccepted: root.runConfigCmd(["notif_type_set", typeRow.modelData.nature, text])
                                }
                            }

                            Rectangle {
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.success
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.success
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["notif_type_set", typeRow.modelData.nature, typeAlias.text])
                                }
                            }
                        }
                    }

                    // ── liens ───────────────────────────────────────────
                    Row {
                        id: urlRow
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            width: 84
                            height: 32
                            color: Theme.surfaceVariant
                            radius: Theme.globalRadius
                            border.color: Theme.accentMuted
                            border.width: 1

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: "Liens"
                                color: Theme.fg
                                font.bold: true
                                font.pixelSize: Theme.textSm
                            }
                        }

                        Rectangle {
                            width: urlRow.width - 84 - 32 - 2 * 10
                            height: 32
                            color: Theme.bg
                            radius: Theme.globalRadius
                            border.color: urlAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
                            border.width: 1

                            TextInput {
                                id: urlAlias
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.notifTargets.url || ""
                                color: Theme.info
                                font.pixelSize: Theme.textSm
                                onAccepted: root.runConfigCmd(["notif_url_set", text])
                            }
                        }

                        Rectangle {
                            width: 32
                            height: 32
                            color: Theme.surfaceVariant
                            radius: Theme.globalRadius
                            border.color: Theme.success
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: Theme.success
                                font.pixelSize: Theme.textMd
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["notif_url_set", urlAlias.text])
                            }
                        }
                    }

                    // ── par application ─────────────────────────────────
                    Text {
                        text: "Par application"
                        color: Theme.accent
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    Text {
                        visible: root.notifAppRows.length === 0
                        width: parent.width
                        text: "Aucune règle par application."
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }

                    Repeater {
                        model: root.notifAppRows

                        Row {
                            id: appRuleRow
                            required property var modelData
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: 116
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    width: parent.width - 16
                                    text: appRuleRow.modelData.key + (appRuleRow.modelData.terminal ? " · terminal" : "")
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: Theme.text2xs
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: appRuleRow.width - 116 - 32 - 32 - 3 * 10 - 4
                                height: 32
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: appRuleCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                TextInput {
                                    id: appRuleCmd
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: appRuleRow.modelData.command
                                    color: Theme.info
                                    font.pixelSize: Theme.textSm
                                    onAccepted: root.runConfigCmd(["notif_app_set", appRuleRow.modelData.key, text])
                                }
                            }

                            Rectangle {
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.success
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Theme.success
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["notif_app_set", appRuleRow.modelData.key, appRuleCmd.text])
                                }
                            }

                            Rectangle {
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["notif_app_del", appRuleRow.modelData.key])
                                }
                            }
                        }
                    }

                    Item { width: 1; height: 4 }

                    // Ajout d'une règle : le nom de l'application tel qu'il apparaît
                    // dans ses notifications, et la commande à lancer.
                    Row {
                        id: newNotifAppRow
                        width: parent.width
                        spacing: 10

                        function ajouter() {
                            const cle = newNotifAppKey.text.trim()
                            const cmd = newNotifAppCmd.text.trim()
                            if (cle === "" || cmd === "") return
                            root.runConfigCmd(["notif_app_set", cle, cmd])
                            newNotifAppKey.text = ""
                            newNotifAppCmd.text = ""
                        }

                        Rectangle {
                            width: 116
                            height: 34
                            color: Theme.bg
                            radius: Theme.globalRadius
                            border.color: newNotifAppKey.activeFocus ? Theme.accent : Theme.surfaceVariant
                            border.width: 1

                            Text {
                                visible: newNotifAppKey.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: "Application"
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.textXs
                            }

                            TextInput {
                                id: newNotifAppKey
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                            }
                        }

                        Rectangle {
                            width: parent.width - 116 - 84 - 2 * 10
                            height: 34
                            color: Theme.bg
                            radius: Theme.globalRadius
                            border.color: newNotifAppCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                            border.width: 1

                            Text {
                                visible: newNotifAppCmd.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: "Commande"
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.textXs
                            }

                            TextInput {
                                id: newNotifAppCmd
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.info
                                font.pixelSize: Theme.textSm
                                onAccepted: newNotifAppRow.ajouter()
                            }
                        }

                        Rectangle {
                            width: 84
                            height: 34
                            radius: Theme.globalRadius
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: "+ Ajouter"
                                color: Theme.bg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: newNotifAppRow.ajouter()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Commande telle qu'on la taperait dans un terminal : les guillemets "
                            + "protègent les espaces (« gwenview \"mon dossier/image.png\" »)."
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.text2xs
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Autostart géré par le panneau (autostart.json -> autostart_managed.lua)
            CollapsibleSection {
                id: secAutostart
                objectName: "secAutostart"
                title: "Programmes lancés au démarrage"
                icon: "power"
                expanded: root.sectionOpen("apps_autostart", true)
                onToggled: expanded => root.setPanelSection("apps_autostart", expanded)

            Text {
                text: "Autostart Hyprland (effectif au prochain démarrage de session)"
                color: Theme.accent
                font.pixelSize: Theme.textMd
                font.bold: true
                width: parent.width
            }

            Flickable {
                width: parent.width
                height: Math.min(autostartList.implicitHeight, 260)
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
                                width: 32
                                height: 32
                                radius: Theme.globalRadius
                                color: asRow.modelData.enabled ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.4)
                                border.color: asRow.modelData.enabled ? Theme.success : Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: asRow.modelData.enabled ? "✓" : "✕"
                                    color: asRow.modelData.enabled ? Theme.success : Theme.error
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["autostart_set", asRow.modelData.name, String(!asRow.modelData.enabled)])
                                }
                            }

                            Rectangle {
                                width: 140
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    width: parent.width - 16
                                    text: asRow.modelData.name
                                    color: Theme.fg
                                    font.bold: true
                                    font.pixelSize: Theme.textSm
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: asRow.width - 32 - 140 - 32 - 3 * 10 - 4
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
                                    font.pixelSize: Theme.textXs
                                }
                            }

                            Rectangle {
                                width: 32
                                height: 32
                                color: Theme.surfaceVariant
                                radius: Theme.globalRadius
                                border.color: Theme.error
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.error
                                    font.pixelSize: Theme.textSm
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

            Item { width: 1; height: 10 }

            Row {
                spacing: 10
                width: parent.width

                Rectangle {
                    width: 110
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
                        text: "Nom"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.textXs
                    }

                    TextInput {
                        id: newAsName
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                    }
                }

                Rectangle {
                    width: parent.width - 110 - 84 - 2 * 10
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
                        text: "Commande"
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.textXs
                    }

                    TextInput {
                        id: newAsCmd
                        anchors.fill: parent
                        anchors.margins: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.info
                        font.pixelSize: Theme.textSm
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
                    width: 84
                    height: 34
                    radius: Theme.globalRadius
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: Theme.textSm
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

            // Onglet Connexion (thème du greeter) : composant séparé pour ne pas
            // alourdir ce fichier — il porte sa grille de miniatures et son backend.
            Loader {
                id: greeterTabLoader
                width: mainFlickable.width
                visible: root.currentTab === 5
                active: visible
                source: "GreeterTab.qml"
                onLoaded: item.width = mainFlickable.width
            }
    }   // end Flickable mainFlickable
    }   // end Item tabContentArea
}
