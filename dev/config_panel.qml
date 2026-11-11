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
//   • Section 3: Navigation Tabs Bar (Bureau, Quickshell, Widgets, Système & Écrans,
//     Contrôles, Applications, Connexion)
//   • Section 4: Tab Content Area (tabContentArea + mainFlickable with auto-scroll reset on tab switch)
//       - Tab 0: Bureau — seulement le fond d'écran, les thèmes et les fenêtres Hyprland
//           * CollapsibleSection secTheme: Themes, Matugen presets, palette hex editor, wallpaper directory
//           * CollapsibleSection secAspect: Gaps, Borders, Rounding, Opacity, Blur passes/size,
//             Resize step (réglages des fenêtres, pas du shell)
//       - Tab 1: Gestion Quickshell — la barre et ses applets, en deux tiroirs
//           * CollapsibleSection secBarre: îlots, hauteur de barre, opacité et flou du shell,
//             bordure, flou des popups, bouton central
//           * CollapsibleSection secApplets: quels applets, dans quel îlot, dans quel ordre, à quelle échelle
//       - Tab 2: Widgets du bureau
//           * Host detection (desktop vs laptop), multi-monitor grid, resolution/refresh modes, scaling,
//             and time synchronization (Timezone & NTP toggle)
//       - Tab 2: Contrôles, Clavier & Raccourcis
//           * Keyboard layout preview & switcher, Hyprland binds viewer/editor, workspace shortcuts
//       - Tab 3: Applications & Démarrage
//           * CollapsibleSection secApps: Default applications (terminal, browser, editor, file manager)
//           * CollapsibleSection secAutostart: Managed user background daemons & autostart entries
// ════════════════════════════════════════════════════════════════════════════

// ── Règle de gel (11/11) ────────────────────────────────────────────────────
// Ce fichier ne doit plus grossir. Une option nouvelle naît dans son propre
// composant, chargé par URL depuis ici : `Loader { source: "Onglet….qml" }`.
// C'est le motif qui a déjà sorti l'onglet Greeter (707 lignes) puis l'onglet
// Bureau (1 500 lignes dans OngletEsthetique.qml).
//
// Pourquoi : 9 000 lignes à un seul endroit font payer chaque édition, et une
// retouche scriptée y a déjà dupliqué un bloc entier — le panneau ne s'instanciait
// plus, sans que qmllint bronche. Un composant à part se relit, se vérifie et se
// recharge seul.
//
// Le tronc commun (rail, recherche, en-tête collant, overlays) reste ici ; chaque
// onglet a son fichier, instancié à la première ouverture par un `active:`
// qui suit `currentTab`.
Rectangle {
    id: root
    width: 740
    height: parent ? parent.height : 600
    color: Theme.surfaceBg
    radius: Theme.globalRadius
    border.color: Theme.accent
    border.width: 1

    focus: true
    Keys.onEscapePressed: event => {
        if (selecteurLoader.item && selecteurLoader.item.ouvert) {
            selecteurLoader.item.annulerEtFermer()
            event.accepted = true
            return
        }
        if (selecteurFichierLoader.item && selecteurFichierLoader.item.ouvert) {
            selecteurFichierLoader.item.annulerEtFermer()
            event.accepted = true
            return
        }
        Theme.configPanelVisible = false
        event.accepted = true
    }

    function restaurerFocus() {
        searchInput.forceActiveFocus()
    }

    // Verre dépoli autonome : inactif tant que Theme.shellFlouInterne vaut 0.
    FlouFond {
        anchors.fill: parent
        rayon: root.radius
        intensite: Theme.shellFlouInterne
    }

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
          tab: 6, section: "greeter_theme", target: "secGreeter" },
        { label: "Accès API", words: "cle api token deepseek ollama antigravity secrets connexion fournisseur", tab: 2,
          section: "widgets_api", target: "secApiKeys" },
        { label: "Notifications (ne pas déranger)", words: "notification dnd ne pas deranger toast silencieux cloche", tab: 1,
          section: "quickshell_notifications", target: "secNotifs" },
        { label: "Localisation (ville, coordonnées, fuseau)", words: "localisation ville position coordonnees latitude longitude fuseau timezone meteo", tab: 7,
          section: "donnees_localisation", target: "secLocalisation" },
        { label: "Calendrier Nextcloud", words: "nextcloud calendrier caldav identifiants agenda compte", tab: 7,
          section: "quickshell_calendrier", target: "secCalendrier" },
        { label: "Homelab (Proxmox)", words: "proxmox homelab serveur noeud vm jeton api token", tab: 7,
          section: "widgets_homelab", target: "secHomelab" },
        { label: "Applets de la barre", words: "applets barre ilot ordre position echelle cloche volume reseau",
          tab: 1, section: "quickshell_applets", target: "secApplets" },
        { label: "Barre et surfaces du shell", words: "barre hauteur opacite flou arrondi ilot popups bordure",
          tab: 0, section: "quickshell_barre", target: "secBarre" },
        { label: "Widgets du bureau", words: "widgets bureau horloge date meteo workspace",
          tab: 2, section: "widgets", target: "secWidgets" },
        { label: "Position du lanceur", words: "lanceur position capsule haut bas centre gauche droite",
          tab: 2, section: "widgets", target: "secWidgets" },
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
          tab: 0, section: "quickshell_barre", target: "roundingIslandRow" },
        { label: "Hauteur de la barre", words: "hauteur barre taille bar",
          tab: 0, section: "quickshell_barre", target: "barHeightRow" },
        { label: "Pas de redimensionnement", words: "pas redimensionnement resize step",
          tab: 0, section: "esthetique_aspect", target: "resizeRow" },
        { label: "Opacité des fenêtres", words: "opacite fenetres transparence hyprland",
          tab: 0, section: "esthetique_aspect", target: "winOpacityRow" },
        { label: "Opacité des surfaces du shell", words: "opacite surfaces shell verre barre panneau",
          tab: 0, section: "quickshell_barre", target: "shellOpacityRow" },
        { label: "Réglages du visualiseur audio", words: "visualiseur audio onde barres fps colonnes sensibilite lissage epaisseur couleur",
          tab: 1, section: "quickshell_visualiseur", target: "secVisualiseur" },
        { label: "Espaces entre les îlots", words: "espaces ilots transparence transparence vide gap barre media",
          tab: 0, section: "quickshell_barre", target: "barGapsRow" },
        { label: "Taille et passes du flou", words: "flou blur taille passes intensite",
          tab: 0, section: "esthetique_aspect", target: "blurRow" },
        { label: "Variante du flou", words: "flou blur variante variant acrylic kawase haze aurora",
          tab: 0, section: "esthetique_aspect", target: "blurVariantRow" },
        { label: "Flou des surfaces du shell", words: "flou shell layer rule seuil ignore alpha popups",
          tab: 0, section: "quickshell_barre", target: "shellBlurRow" },
        { label: "Écrans, résolution, taux de rafraîchissement", words: "ecran moniteur resolution taux hz echelle scale",
          tab: 3, section: "", target: "monitorsRow" },
        { label: "Fuseau horaire et synchronisation NTP", words: "fuseau timezone heure ntp synchronisation horloge",
          tab: 3, section: "", target: "timezoneRow" },
        { label: "Mise en veille automatique", words: "mise en veille veille inactivité suspend sleep ecran timer energie heure",
          tab: 3, section: "systeme_horloge", target: "idleTimeoutRow" },
        { label: "Disposition du clavier", words: "clavier layout azerty qwerty langue",
          tab: 4, section: "", target: "kbdRow" },
        { label: "Raccourcis Hyprland", words: "raccourcis binds touches clavier hyprland",
          tab: 4, section: "", target: "bindsCol" },
        { label: "Programmes par défaut des raccourcis", words: "applications variables programmes defaut terminal navigateur editeur fichiers chemins",
          tab: 5, section: "apps_programs", target: "secApps" },
        { label: "Historique des lancements", words: "historique lancements recents pilule spotlight memoire",
          tab: 2, section: "widgets_pilule", target: "launchHistoryRow" },
        { label: "Cible du clic sur une notification", words: "notification notifications clic titre cible lien fichier video image dossier commande", 
          tab: 5, section: "quickshell_notifications", target: "secNotifs" },
        { label: "Programmes lancés au démarrage", words: "applications autostart demarrage lancement daemon",
          tab: 5, section: "apps_autostart", target: "secAutostart" }
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
        "roundingIslandRow": roundingIslandRow,
        "barHeightRow": barHeightRow,
        "barGapsRow": barGapsRow,
        "secVisualiseur": secVisualiseur,
        "monitorsRow": monitorsRow,
        "timezoneRow": timezoneRow,
        "idleTimeoutRow": idleTimeoutRow,
        "kbdRow": kbdRow,
        "bindsCol": bindsCol,
        "secApps": secApps,
        "launchHistoryRow": launchHistoryRow,
        "secAutostart": secAutostart
    })

    // Correspondance section → ancre : le clic milieu d'un applet donne un nom
    // de section (celui de `panel_sections`), l'ancre est l'id de l'objet à
    // amener à l'écran. Sans correspondance, on déplie sans défiler.
    readonly property var ancreDeSection: ({
        "quickshell_applets": "secApplets",
        "quickshell_visualiseur": "secVisualiseur",
        "quickshell_barre": "secBarre",
        "quickshell_barres": "secBarres",
        "quickshell_disques": "secDisques",
        "widgets": "secWidgets",
        "apps_programs": "secApps",
        "donnees_localisation": "secLocalisation"
    })

    // Un nom de section ne dit pas dans quel onglet il vit : sans ça, le clic
    // milieu ouvrait le panneau sur « Bureau » et dépliait une section cachée.
    // Table complète : une section absente d'ici ne fait pas changer d'onglet, donc
    // le clic milieu et la recherche ouvraient le panneau sur « Bureau » en dépliant
    // une section cachée. Neuf sections manquaient.
    readonly property var ongletDeSection: ({
        "esthetique_theme": 0, "esthetique_fonds": 0, "esthetique_aspect": 0,
        "quickshell_barre": 0,
        "quickshell_applets": 1, "quickshell_barres": 1, "quickshell_disques": 1,
        "quickshell_visualiseur": 1,
        "widgets": 2, "widgets_pilule": 2, "widgets_api": 7,
        "systeme_nuit": 3, "ecrans_moniteurs": 3, "ecrans_profils": 3, "systeme_horloge": 3,
        "clavier_disposition": 4, "clavier_binds": 4,
        "apps_programs": 5, "apps_autostart": 5, "quickshell_notifications": 5,
        "greeter_theme": 6,
        "quickshell_calendrier": 7, "taches_fichiers": 7, "widgets_homelab": 7,
        "donnees_localisation": 7
    })

    // Écrit la localisation : quatre clés, une par champ, dans style_vars.json.
    function enregistrerLocalisation(ville, lat, lon, tz) {
        runConfigCmd(["style", "user_location_ville", String(ville || "")])
        runConfigCmd(["style", "user_location_lat", String(lat || "")])
        runConfigCmd(["style", "user_location_lon", String(lon || "")])
        runConfigCmd(["style", "user_location_tz", String(tz || "")])
    }

    // Géocodage de la ville saisie, par le service météo (Open-Meteo, sans clé).
    function geocoder(ville) {
        if (String(ville || "").trim() === "") return
        geocodage.command = ["python3", Quickshell.shellPath("core/weather_service.py"),
                             "--geocode", String(ville)]
        geocodage.running = true
    }

    function ouvrirSection(nom) {
        const section = String(nom || "")
        if (section === "") return
        const onglet = root.ongletDeSection[section]
        if (onglet !== undefined) root.currentTab = onglet
        root.setPanelSection(section, true)
        if (Theme.panelAccordion) root.fermerAutresTiroirs(section)
        const ancre = root.ancreDeSection[section] || ""
        if (ancre !== "") {
            root.scrollTargetName = ancre
            root.scrollTries = 0
            scrollTimer.restart()
        }
    }

    // Ouverture demandée de l'extérieur (clic milieu d'un applet).
    Connections {
        target: Theme
        function onConfigRequestChanged() {
            if (!Theme.configPanelVisible) return
            const cible = String(Theme.configTarget || "")
            Theme.configTarget = ""
            if (cible !== "") root.ouvrirSection(cible)
        }
    }

    function scrollToAnchor(name) {
        const target = root.cibleDe(name)
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
    property int currentTab: 0 // 0: Bureau, 1: Quickshell, 2: Widgets, 3: Système & Écrans,
                               // 4: Contrôles, 5: Applications, 6: Connexion

    // State synced with config_manager.py & FileViews
    property string hostName: "Machine"
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
    // Proxmox : l'applet et le widget homelab s'en servent. Le secret du jeton
    // n'est jamais rendu par config_manager, seulement ses quatre derniers
    // caractères — le panneau ne peut donc pas l'afficher, même par erreur.
    property string homelabUrl: ""
    property string homelabTokenId: ""
    property string homelabTokenTail: ""
    property bool homelabTokenPresent: false
    // Fichiers suivis par l'applet et le widget « Tâches » (core/todo.json).
    property var todoFichiers: []
    property string todoFocus: ""
    property string todoErreur: ""
    property bool todoSurveillance: false

    function rechargerTodo() {
        todoListProc.running = false
        todoListProc.running = true
    }

    function ajouterTodo() {
        const chemin = nouveauTodoChemin.text.trim()
        if (chemin === "") return
        root.todoErreur = ""
        root.runConfigCmd(["todo_add", nouveauTodoNom.text.trim(), chemin])
    }
    // Mode nuit (onglet Système & Écrans) : température, plage, état.
    property int nuitTemp: 4000
    property bool nuitAllumee: false
    // Ne pas déranger : même drapeau que la cloche de la barre et le centre de
    // notifications (style_vars.json → do_not_disturb).
    property bool dndActif: false
    property string nuitDe: ""
    property string nuitA: ""
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
    property int idleSuspendTimeout: 3600
    readonly property string idleSuspendLabel: {
        const s = root.idleSuspendTimeout
        if (s === 900) return "15 min"
        if (s === 1800) return "30 min"
        if (s === 3600) return "1 heure"
        if (s === 7200) return "2 heures"
        if (s === 10800) return "3 heures"
        if (s === 0) return "Désactivée"
        if (s > 0 && s < 3600) return Math.round(s / 60) + " min"
        if (s >= 3600) return (s / 3600).toFixed(s % 3600 === 0 ? 0 : 1) + " h"
        return "1 heure"
    }
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
        { type: "combo",   label: "Aperçu du jour" },
        { type: "musique", label: "Musique" },
        { type: "systeme", label: "Système" },
        { type: "reseau", label: "Réseau" },
        { type: "disques", label: "Disques" },
        { type: "homelab", label: "Homelab" },
        { type: "hermes",  label: "Hermes" },
        { type: "usb",     label: "Périphériques" },
        { type: "todo",    label: "Tâches" },
        { type: "presse_papiers", label: "Presse-papiers" },
        { type: "deepseek", label: "DeepSeek" },
        { type: "ollama",   label: "Ollama Cloud" },
        { type: "antigravity", label: "Antigravity" },
        // Fusion des trois précédents : un seul widget, blocs empilés.
        { type: "comptes",  label: "Quotas IA" }
    ]
    // Libellé lisible d'une nature de widget : la carte de réglages affichait le
    // nom technique (« combo ») alors que la grille du dessus dit « Aperçu du jour ».
    function libelleWidget(nature) {
        const n = String(nature || "")
        for (let i = 0; i < widgetTypes.length; ++i)
            if (String(widgetTypes[i].type) === n) return widgetTypes[i].label
        return n
    }

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

    // ── Applets de la barre ──────────────────────────────────────────────────
    // Le registre (core/bar_applets.py) est la seule source de vérité : le
    // panneau ne fait que l'interroger et lui envoyer des ordres. Comme c'est un
    // dictionnaire `id → placement`, cocher deux fois ou placer ailleurs ne peut
    // pas créer de doublon : la dernière décision remplace la précédente.
    property var appletRows: []
    // La même liste, rangée par catégorie et aplatie : un titre, puis ses
    // applets, puis le titre suivant. Un seul Repeater dessine les deux genres,
    // ce qui évite de dupliquer le délégué de ligne (250 lignes) ou d'en faire
    // un fichier à part pour trois titres.
    //
    // La catégorie vient du catalogue (`categorie`) : un applet ajouté plus tard
    // arrive rangé tout seul. Sans catégorie déclarée, il tombe dans « Autres »
    // plutôt que de disparaître de la liste.
    readonly property var appletCategories: [
        "Session & énergie",
        "Système & réseau",
        "Temps & notifications",
        "Médias & bureaux",
        "Services & IA"
    ]
    readonly property var appletEntries: {
        const seaux = ({})
        const apparues = []
        for (let i = 0; i < appletRows.length; ++i) {
            const a = appletRows[i] || {}
            // Le visualiseur n'a pas d'emplacement : son activation vit dans son
            // propre tiroir, pas dans la liste des applets.
            if (String(root.donneeApplet(a).id) === "visualiseur") continue
            const cat = String(a.categorie || "Autres")
            if (!seaux[cat]) {
                seaux[cat] = []
                apparues.push(cat)
            }
            seaux[cat].push(a)
        }
        // Ordre de lecture imposé par `appletCategories` — une catégorie connue
        // mais vide ne s'affiche pas, et une catégorie inventée plus tard se
        // range à la fin plutôt que d'être perdue.
        const ordre = []
        for (let j = 0; j < appletCategories.length; ++j)
            if (seaux[appletCategories[j]]) ordre.push(appletCategories[j])
        for (let j = 0; j < apparues.length; ++j)
            if (ordre.indexOf(apparues[j]) < 0) ordre.push(apparues[j])

        const out = []
        for (let j = 0; j < ordre.length; ++j) {
            out.push({ genre: "titre", texte: ordre[j] })
            const lignes = seaux[ordre[j]]
            for (let k = 0; k < lignes.length; ++k)
                out.push({ genre: "applet", applet: lignes[k] })
        }
        return out
    }
    // Change à chaque réponse du registre : les cases à cocher s'y abonnent, car
    // lire `donnee.options` (un objet JS) ne crée aucune dépendance QML et la
    // coche ne se recalculait donc jamais.
    property string appletSignature: ""
    // Un applet a une barre et une place dans cette barre. Deux groupes de
    // pastilles plutôt que douze : douze ne tiendraient pas sur une ligne, et
    // cette séparation est celle du modèle (« haut:fin », « bas:debut »…).
    readonly property var appletBarres: [
        { code: "haut", label: "H" },
        { code: "bas", label: "↓" },
        { code: "cote-gauche", label: "←" },
        { code: "cote-droite", label: "→" }
    ]
    readonly property var appletZones: [
        { code: "debut", labelA: "G", labelB: "⇤" },
        { code: "milieu", labelA: "C", labelB: "●" },
        { code: "fin", labelA: "D", labelB: "⇥" }
    ]

    function barreDe(donnee) {
        const p = String((donnee && donnee.ile) || "haut:fin").split(":")
        return p[0] || "haut"
    }

    function zoneDe(donnee) {
        const p = String((donnee && donnee.ile) || "haut:fin").split(":")
        return p[1] || "milieu"
    }

    Process {
        id: appletsEtatProc
        command: ["python3", Quickshell.shellPath("core/bar_applets.py"), "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text.trim())
                    root.appletRows = Array.isArray(liste) ? liste : []
                    root.appletSignature = JSON.stringify(root.appletRows)
                } catch (e) {
                    root.appletRows = []
                }
            }
        }
    }

    // ── Calendrier Nextcloud ─────────────────────────────────────────────────
    // Le panneau n'a jamais le mot de passe : il demande l'état au script, qui
    // répond « présent » et les quatre derniers caractères. L'applet calendrier
    // et le widget date lisent le même fichier, donc une saisie ici sert aux deux.
    property var ncEtat: ({})
    property string ncStatut: ""

    Process {
        id: ncEtatProc
        command: ["python3", Quickshell.shellPath("core/calendrier_config.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ncEtat = JSON.parse(text.trim()) } catch (e) { root.ncEtat = ({}) }
            }
        }
    }

    Process {
        id: ncEcritProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text.trim())
                    root.ncEtat = r
                    root.ncStatut = r.ok ? "Enregistré" : ("Échec : " + (r.erreur || "inconnu"))
                } catch (e) {
                    root.ncStatut = "Échec de l'enregistrement"
                }
            }
        }
    }

    function enregistrerNc(champ, valeur) {
        const v = String(valeur || "").trim()
        // Un mot de passe laissé vide veut dire « ne change rien » : on ne peut
        // pas le relire, l'afficher, ni le confirmer autrement que par sa fin.
        if (champ === "app_password" && v === "") return
        if (v === "") {
            root.ncStatut = "Ce champ ne peut pas rester vide"
            return
        }
        root.ncStatut = "Enregistrement…"
        ncEcritProc.command = ["python3", Quickshell.shellPath("core/calendrier_config.py"),
                               "definir", champ, v]
        ncEcritProc.running = true
    }

    Process {
        id: appletsCmdProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text.trim())
                    if (Array.isArray(liste)) {
                        // Deux temps : vider puis remplir. Une réaffectation
                        // directe laissait les délégués en place quand la liste
                        // gardait la même longueur, et les cases à cocher des
                        // disques continuaient d'afficher l'ancien état.
                        root.appletRows = []
                        root.appletRows = liste
                        root.appletSignature = JSON.stringify(liste)
                    } else {
                        root.appletsRafraichir()
                    }
                } catch (e) {
                    root.appletsRafraichir()
                }
            }
        }
    }

    function appletsRafraichir() {
        appletsEtatProc.running = false
        appletsEtatProc.running = true
    }

    // Chaque commande rend l'état complet : pas de deuxième requête à faire.
    // Les lignes brutes du registre portent `id` et `actif` à la racine ; les
    // entrées groupées les enveloppent dans `applet`. Une seule lecture pour les
    // deux, sinon le visualiseur passait pour éteint alors qu'il était actif.
    function donneeApplet(ligne) {
        return (ligne && ligne.applet) ? ligne.applet : (ligne || {})
    }

    // Activation du visualiseur audio : absent de la liste des applets (pas
    // d'emplacement), son état se lit dans la même liste, produite par
    // bar_applets.py.
    readonly property bool vizActif: {
        for (let i = 0; i < root.appletRows.length; ++i) {
            const a = root.donneeApplet(root.appletRows[i])
            if (String(a.id) === "visualiseur") return a.actif === true
        }
        return false
    }

    // Rendu du visualiseur (« onde » ou « barres »). C'est une option d'applet
    // du registre `bar_applets.json`, mais on l'expose ici : c'est le seul
    // réglage de cet applet qui change son allure, et le tiroir parle déjà du
    // « mode barres ».
    readonly property string vizStyle: {
        for (let i = 0; i < root.appletRows.length; ++i) {
            const a = root.donneeApplet(root.appletRows[i])
            if (String(a.id) === "visualiseur")
                return String((a.options || {}).style || "onde")
        }
        return "onde"
    }

    function changerModeVisualiseur(code) {
        if (String(code) === root.vizStyle) return
        root.appletCommande(["option", "visualiseur", "style", String(code)])
        vizRafraichir.restart()
    }

    // Schémas de couleurs KDE installés : importés dans `palette` au premier
    // chargement du panneau, puis relus. Sans cette étape, « détecter les thèmes
    // installés » ne montrerait que les palettes déjà présentes.
    Process {
        id: scanThemes
        command: ["python3", Quickshell.shellPath("core/themes_scan.py"), "--sync"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && d.ajoutes && d.ajoutes.length > 0)
                        Theme.relireStyle()
                } catch (e) { /* rien à importer */ }
            }
        }
    }

    // Installation d'un schéma de couleurs (.colors ou archive zip/tar)
    property string themeInstallStatus: ""
    property bool themeInstallBusy: false

    Process {
        id: installThemeProc
        command: ["python3", Quickshell.shellPath("core/installer_theme_couleur.py"), ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text.trim())
                    if (res.ok) {
                        root.themeInstallStatus = res.message || "Thème installé !"
                        Theme.relireStyle()
                    } else {
                        root.themeInstallStatus = "Échec : " + (res.erreur || "erreur d'installation")
                    }
                } catch (e) {
                    if (text.trim().length > 0) root.themeInstallStatus = text.trim()
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.themeInstallBusy = false
            scanThemes.running = false
            scanThemes.running = true
        }
    }

    function installerThemeCouleur(chemin) {
        if (!chemin || root.themeInstallBusy) return
        root.themeInstallBusy = true
        root.themeInstallStatus = "Installation du thème..."
        installThemeProc.command = ["python3", Quickshell.shellPath("core/installer_theme_couleur.py"), String(chemin), "--activate"]
        installThemeProc.running = true
    }

    // Recentrage différé : la mise en page du tiroir qui se déplie n'est pas
    // encore à jour quand on écrit contentY, d'où le délai d'une frame.
    Timer {
        id: recentrage
        interval: 60
        repeat: false
        onTriggered: {
            const t = root.tiroirOuvertCourant
            if (t) root.amenerTiroirEnHaut(t.nom)
            root.majEnteteCollant()
        }
    }

    // Tiroir ouvert de l'onglet courant (l'accordéon n'en laisse qu'un, mais on
    // ne s'y fie pas : on prend le premier ouvert de l'onglet).
    readonly property var tiroirOuvertCourant: {
        for (const nom in root.tiroirs) {
            if (root.ongletDeSection[nom] !== root.currentTab) continue
            if (root.sectionOpen(nom, false)) return { nom: nom, item: root.tiroirDe(nom) }
        }
        return null
    }

    property string tiroirCollant: ""
    property string titreCollant: ""

    // Le bandeau n'apparaît que si l'en-tête du tiroir est sorti par le haut et
    // qu'il reste du contenu sous le bandeau : sinon il doublerait l'en-tête réel.
    function majEnteteCollant() {
        const t = root.tiroirOuvertCourant
        if (!t || !t.item) { root.tiroirCollant = ""; return }
        const haut = t.item.mapToItem(mainFlickable.contentItem, 0, 0).y
        const bas = haut + t.item.height
        const visible = haut < mainFlickable.contentY && bas > mainFlickable.contentY + 34
        root.tiroirCollant = visible ? t.nom : ""
        root.titreCollant = visible ? String(t.item.title || "") : ""
    }

    // Réduire un tiroir au-dessus décale tout : sans ce recentrage, le tiroir
    // qu'on vient d'ouvrir pouvait se retrouver hors de vue et le clic semblait
    // sans effet. On place son en-tête sous le bandeau collant.
    function amenerTiroirEnHaut(nom) {
        const tiroir = root.tiroirDe(nom)
        if (!tiroir) return
        const y = tiroir.mapToItem(mainFlickable.contentItem, 0, 0).y
        const marge = root.tiroirCollant !== "" ? 44 : 10
        const maxY = Math.max(0, mainFlickable.contentHeight - mainFlickable.height)
        mainFlickable.contentY = Math.max(0, Math.min(y - marge, maxY))
    }

    function replierTiroirCollant() {
        const nom = root.tiroirCollant
        const tiroir = root.tiroirDe(nom)
        if (tiroir) tiroir.expanded = false
        root.setPanelSection(nom, false)
        root.tiroirCollant = ""
    }

    // La commande écrit bar_applets.json ; on relit la liste juste après.
    Timer {
        id: vizRafraichir
        interval: 350
        repeat: false
        onTriggered: root.appletsRafraichir()
    }

    function basculerVisualiseur() {
        root.appletCommande([root.vizActif ? "desactiver" : "activer", "visualiseur"])
        vizRafraichir.restart()
    }

    function appletCommande(args) {
        appletsCmdProc.command = ["python3", Quickshell.shellPath("core/bar_applets.py")].concat(args)
        appletsCmdProc.running = true
    }

    // Placer un applet dans une barre éteinte le rendrait invisible : on allume
    // la barre dans le même geste. C'était le cas vécu « je choisis → et l'applet
    // disparaît ».
    function placerApplet(id, ile) {
        appletCommande(["placer", id, ile])
        if (ile === "bas" && !Theme.barBottomVisible)
            runConfigCmd(["style", "bar_bottom", "true"])
        else if (ile === "cote-gauche" && !Theme.barLeftVisible)
            runConfigCmd(["style", "bar_left", "true"])
        else if (ile === "cote-droite" && !Theme.barRightVisible)
            runConfigCmd(["style", "bar_right", "true"])
    }

    // ── Disques : la sélection se fait sur la liste réelle des montages ──────
    property var disquesListe: []

    Process {
        id: disquesListeProc
        command: ["python3", Quickshell.shellPath("core/disques_applet.py"), "liste"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.disquesListe = Array.isArray(d.montages) ? d.montages : []
                } catch (e) {
                    root.disquesListe = []
                }
            }
        }
    }

    // Sans choix enregistré, le service affiche tout sauf la racine : la case doit
    // refléter ce défaut, sinon la première coche décocherait tout le reste.
    function montagesChoisis(donnee) {
        const o = (donnee && donnee.options) || ({})
        if (Array.isArray(o.montages)) return o.montages.slice()
        const defaut = []
        for (let i = 0; i < root.disquesListe.length; ++i) {
            const m = String(root.disquesListe[i].montage || "")
            if (m !== "" && m !== "/") defaut.push(m)
        }
        return defaut
    }

    function montageCoche(donnee, montage) {
        return montagesChoisis(donnee).indexOf(String(montage)) >= 0
    }

    // L'entrée telle que le panneau la connaît **maintenant** : le délégué peut
    // porter un `modelData` périmé, et c'est ce qui faisait repartir la sélection
    // du défaut (tout sauf la racine) au lieu du choix courant.
    function entreeApplet(id) {
        const cle = String(id || "")
        for (let i = 0; i < root.appletRows.length; ++i) {
            if (String(root.appletRows[i].id) === cle) return root.appletRows[i]
        }
        return null
    }

    function basculerMontage(donnee, montage) {
        const vive = entreeApplet(donnee && donnee.id) || donnee
        const liste = montagesChoisis(vive)
        const i = liste.indexOf(String(montage))
        if (i >= 0) liste.splice(i, 1)
        else liste.push(String(montage))
        appletCommande(["option", (vive && vive.id) || donnee.id, "montages", JSON.stringify(liste)])
    }

    function appletBasculer(id, actif) {
        appletCommande([actif ? "desactiver" : "activer", id])
    }

    function appletEchelle(id, valeur) {
        const v = Math.max(60, Math.min(160, Math.round(valeur)))
        appletCommande(["echelle", id, String(v)])
    }

    // Fichiers suivis par le widget Tâches : une option vide veut dire « tous »,
    // donc on matérialise la liste complète avant d'en retirer un — sinon la
    // première case décochée ne changerait rien.
    function basculerFichierWidget(wid, nom) {
        let vive = null
        for (let i = 0; i < root.widgetsList.length; ++i) {
            if (String(root.widgetsList[i].id) === String(wid)) vive = root.widgetsList[i]
        }
        if (!vive) return
        const o = vive.options || ({})
        let liste = Array.isArray(o.fichiers)
                  ? o.fichiers.map(function (s) { return String(s) })
                  : (typeof o.fichiers === "string" && o.fichiers !== ""
                     ? o.fichiers.split(",").map(function (s) { return s.trim() }) : [])
        liste = liste.filter(function (s) { return s !== "" })
        if (liste.length === 0) {
            for (let i = 0; i < root.todoFichiers.length; ++i)
                liste.push(String(root.todoFichiers[i].nom || ""))
        }
        const i = liste.indexOf(String(nom))
        if (i >= 0) liste.splice(i, 1)
        else liste.push(String(nom))
        root.runConfigCmd(["widget_set", wid, "fichiers", JSON.stringify(liste)])
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
    // Variante du flou (decoration:blur:variant) : le panneau gagne, la valeur
    // est rangée dans style_vars.json et Theme.qml l'applique à chaud.
    property string blurVariant: "acrylic"
    // Les onze variantes que Hyprland 0.57 accepte en clair ; l'ordre suit le
    // binaire (kawase 0 … haze 10). Les libellés sont mis en forme, la clé
    // reste le nom brut que `hl.config` attend.
    readonly property var blurVariantChoix: [
        { key: "kawase",       label: "Kawase" },
        { key: "frost",        label: "Frost" },
        { key: "ripple",       label: "Ripple" },
        { key: "drops",        label: "Drops" },
        { key: "water",        label: "Water" },
        { key: "fluid_jar",    label: "Fluid jar" },
        { key: "prism",        label: "Prism" },
        { key: "heat_shimmer", label: "Heat shimmer" },
        { key: "acrylic",      label: "Acrylic" },
        { key: "aurora",       label: "Aurora" },
        { key: "haze",         label: "Haze" }
    ]
    // Flou des surfaces layer-shell du shell (layer rules de general.lua)
    property bool shellBlurEnabled: true
    property bool barBorder: true
    // Espaces entre les îlots de la barre du haut : transparents et sans flou
    property bool barGapsTransparent: false
    // Visualiseur audio (style_vars) : capture et dessin.
    property int vizFps: 30
    property int vizCols: 96
    property real vizSensibilite: 1.0
    property real vizLissage: 0.2
    property real vizEpaisseur: 1.4
    property string vizCouleur: "accent"
    // Jetons proposés au visualiseur — les mêmes que VIZ_COULEURS dans
    // core/config_manager.py, qui refuse tout le reste.
    readonly property var vizCouleurs: [
        { code: "accent", nom: "Accent" },
        { code: "accentMuted", nom: "Accent 2" },
        { code: "fg", nom: "Texte" },
        { code: "warn", nom: "Alerte" },
        { code: "success", nom: "Succès" }
    ]
    function couleurViz(code) {
        return code === "accentMuted" ? Theme.accentMuted
             : code === "fg" ? Theme.fg
             : code === "warn" ? Theme.warn
             : code === "success" ? Theme.success
             : Theme.accent
    }
    property real shellBlurAlpha: 0.4
    property bool shellBlurPopups: true
    property int resizeStep: 15
    property var panelSections: ({})

    // Table nom de section → objet, pour pouvoir replier les tiroirs d'un onglet.
    // Les sections sont nommées parce qu'une section réécrit elle-même son
    // `expanded` au clic : la liaison est alors perdue, il faut donc agir dessus.
    readonly property var tiroirs: ({
        "quickshell_barres": secBarres,
        "quickshell_applets": secApplets,
        "quickshell_visualiseur": secVisualiseur,
        "clavier_disposition": secClavier,
        "clavier_binds": secBinds,
        "ecrans_moniteurs": secEcrans,
        "ecrans_profils": secProfils,
        "systeme_horloge": secHorloge,
        "widgets": secWidgets,
        "widgets_pilule": secPilule,
        "widgets_api": secApiKeys,
        "donnees_localisation": secLocalisation,
        "quickshell_calendrier": secCalendrier,
        "widgets_homelab": secHomelab,
        "taches_fichiers": secTaches,
        "systeme_nuit": secNuit,
        "apps_programs": secApps,
        "quickshell_notifications": secNotifs,
        "greeter_theme": secGreeter,
        "apps_autostart": secAutostart
    })

    // Les sections d'un onglet déporté n'existent que quand son Loader est actif :
    // les deux tables ci-dessus ne peuvent plus les nommer, et un id absent lève
    // « ReferenceError: secTheme is not defined ». On les demande donc à l'onglet
    // chargé, qui expose `sections` (nom de tiroir → objet) et `cibles` (nom
    // d'ancre → objet). La liste grandit au fil des extractions.
    readonly property var ongletsDeportes: [ongletEsthetique]

    function tiroirDe(nom) {
        if (root.tiroirs[nom]) return root.tiroirs[nom]
        for (let i = 0; i < root.ongletsDeportes.length; i++) {
            const it = root.ongletsDeportes[i] ? root.ongletsDeportes[i].item : null
            if (it && it.sections && it.sections[nom]) return it.sections[nom]
        }
        return null
    }

    function cibleDe(nom) {
        if (root.targetMap[nom]) return root.targetMap[nom]
        for (let i = 0; i < root.ongletsDeportes.length; i++) {
            const it = root.ongletsDeportes[i] ? root.ongletsDeportes[i].item : null
            if (it && it.cibles && it.cibles[nom]) return it.cibles[nom]
        }
        return null
    }

    // Applique l'état persisté à tous les tiroirs : l'état est la seule source
    // de vérité, donc un tiroir ouvert en referme un autre sans course.
    function rafraichirTiroirs() {
        // Un seul tiroir ouvert par onglet, et c'est le premier marqué ouvert :
        // l'invariant est tenu ici plutôt que dans chaque bascule, sinon l'ordre
        // des écritures peut laisser deux tiroirs ouverts (cas vu avec le
        // visualiseur sous les applets).
        const ouvertParOnglet = ({})
        for (const nom in root.tiroirs) {
            if (!root.sectionOpen(nom, false)) continue
            const onglet = root.ongletDeSection[nom]
            if (ouvertParOnglet[onglet] === undefined) ouvertParOnglet[onglet] = nom
        }
        for (const nom in root.tiroirs) {
            const tiroir = root.tiroirDe(nom)
            if (!tiroir) continue
            const voulu = Theme.panelAccordion
                ? (ouvertParOnglet[root.ongletDeSection[nom]] === nom)
                : root.sectionOpen(nom, false)
            if (tiroir.expanded !== voulu) tiroir.expanded = voulu
        }
    }

    // Seul endroit qui décide : à l'ouverture d'un tiroir, ceux du même onglet
    // sont refermés **dans la même écriture d'état**. L'ordre des écritures ne
    // peut donc plus laisser deux tiroirs ouverts (cas vu avec le visualiseur
    // sous les applets).
    function setPanelSection(name, expanded) {
        const s = Object.assign({}, root.panelSections)
        const fermes = []
        if (expanded && Theme.panelAccordion) {
            const onglet = root.ongletDeSection[name]
            for (const autre in root.tiroirs) {
                if (autre === name) continue
                if (root.ongletDeSection[autre] !== onglet) continue
                if (s[autre] === false) continue
                s[autre] = false
                fermes.push(autre)
            }
        }
        s[name] = expanded
        root.panelSections = s
        root.runConfigCmd(["panel_section", name, String(expanded)])
        for (let i = 0; i < fermes.length; ++i)
            root.runConfigCmd(["panel_section", fermes[i], "false"])
        root.rafraichirTiroirs()
        majEnteteCollant()
        if (expanded) recentrage.restart()
    }

    // Accordéon : ouvrir un tiroir referme ceux du même onglet.
    function fermerAutresTiroirs(cle) {
        const onglet = root.ongletDeSection[cle]
        if (onglet === undefined) return
        for (const autre in root.tiroirs) {
            if (autre === cle) continue
            if (root.ongletDeSection[autre] !== onglet) continue
            if (root.sectionOpen(autre, false) === false) continue
            const s = Object.assign({}, root.panelSections)
            s[autre] = false
            root.panelSections = s
            root.runConfigCmd(["panel_section", autre, "false"])
        }
        root.rafraichirTiroirs()
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

    // Résumé de tiroir : un chemin du thème (`$HOME/...`) se lit mieux en `~`.
    function resumeChemin(chemin) {
        const s = String(chemin || "")
        return s.replace(/^\$HOME/, "~").replace(/\/$/, "")
    }

    // Chemins des réglages → chemin absolu. Les valeurs du thème commencent par
    // `$HOME` ou `~` ; les sélecteurs de dossier/fichier travaillent en absolu.
    function cheminAbsolu(chemin) {
        let s = String(chemin || "")
        if (s.indexOf("$HOME") === 0) s = Quickshell.env("HOME") + s.substring(5)
        else if (s.indexOf("~") === 0) s = Quickshell.env("HOME") + s.substring(1)
        return s.replace(/\/$/, "")
    }

    function abregerHome(chemin) {
        const home = Quickshell.env("HOME")
        const s = String(chemin || "")
        if (home && s.indexOf(home) === 0) {
            return "~" + s.substring(home.length)
        }
        return s
    }

    // Sélecteurs de dossier et de fichier : feuilles modales du panneau
    // (SelecteurDossier.qml / SelecteurFichier.qml), pas des dialogues Qt.
    property string selecteurCible: ""
    property string selecteurFichierCible: ""

    // Installation des paquets manquants (onglet « Apps & Alertes »). Le script
    // lit dependencies.txt, filtre sur la distribution et élève par pkexec —
    // l'agent polkit du shell pose la question dans la session.
    property string depsEtat: ""
    property string depsDetail: ""

    Process {
        id: depsProc
        onRunningChanged: {
            if (running) {
                root.depsEtat = "vérification…"
                root.depsDetail = ""
            }
        }
        stderr: SplitParser {
            onRead: donnee => root.depsDetail = String(donnee)
        }
        onExited: code => {
            root.depsEtat = code === 0 ? "à jour" : "incomplet (code " + code + ")"
        }
    }

    function installerDependances() {
        if (depsProc.running)
            return
        depsProc.command = ["python3", Quickshell.shellPath("core/deps_install.py")]
        depsProc.running = true
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
        if (typeof data.blur_variant === "string" && data.blur_variant.length > 0) root.blurVariant = data.blur_variant
        if (typeof data.shell_blur_enabled === "boolean") root.shellBlurEnabled = data.shell_blur_enabled
        if (typeof data.bar_border === "boolean") root.barBorder = data.bar_border
        if (typeof data.bar_gaps_transparent === "boolean") root.barGapsTransparent = data.bar_gaps_transparent
        if (typeof data.viz_fps === "number") root.vizFps = data.viz_fps
        if (typeof data.viz_cols === "number") root.vizCols = data.viz_cols
        if (typeof data.viz_sensibilite === "number") root.vizSensibilite = data.viz_sensibilite
        if (typeof data.viz_lissage === "number") root.vizLissage = data.viz_lissage
        if (typeof data.viz_epaisseur === "number") root.vizEpaisseur = data.viz_epaisseur
        if (typeof data.viz_couleur === "string") root.vizCouleur = data.viz_couleur
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
        if (typeof data.do_not_disturb === "boolean") root.dndActif = data.do_not_disturb
        if (data.night && typeof data.night === "object") {
            if (typeof data.night.temperature === "number") root.nuitTemp = data.night.temperature
            root.nuitAllumee = data.night.mode === true
            root.nuitDe = String(data.night.from || "")
            root.nuitA = String(data.night.to || "")
        }
        if (data.homelab && typeof data.homelab === "object") {
            root.homelabUrl = String(data.homelab.proxmox_url || "")
            root.homelabTokenId = String(data.homelab.proxmox_token_id || "")
            root.homelabTokenTail = String(data.homelab.jeton_tail || "")
            root.homelabTokenPresent = data.homelab.jeton_present === true
        }
        if (data.todo && typeof data.todo === "object") {
            root.todoFichiers = Array.isArray(data.todo.fichiers) ? data.todo.fichiers : []
            root.todoFocus = String(data.todo.focus || "")
            root.todoSurveillance = Boolean(data.todo.surveillance)
            if (typeof data.todo.erreur === "string") {
                root.todoErreur = data.todo.erreur
                if (data.todo.erreur === "") {
                    nouveauTodoNom.text = ""
                    nouveauTodoChemin.text = ""
                }
            }
        }
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
        if (typeof data.idle_suspend_timeout === "number") root.idleSuspendTimeout = data.idle_suspend_timeout
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

    // Jeton Proxmox : même chemin que les clés d'API — un fichier temporaire dans
    // le répertoire runtime, puis config_manager le range dans secrets.json.
    FileView {
        id: homelabSecretFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-homelab-secret.json"
        atomicWrites: true
        printErrors: true
        onSaved: homelabSecretProc.running = true
    }

    Process {
        id: homelabSecretProc
        command: ["python3", Quickshell.shellPath("core/config_manager.py"),
                  "api_key_set_file", homelabSecretFile.path]
        stdout: StdioCollector {
            onStreamFinished: root.refreshConfigState()
        }
    }

    // Mode nuit : le service s'occupe d'hyprsunset et de style_vars.json, le
    // panneau ne fait que lui passer l'ordre.
    Process {
        id: nuitProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (typeof d.temperature === "number") root.nuitTemp = d.temperature
                    root.nuitAllumee = d.allume === true
                    root.nuitDe = String(d.de || "")
                    root.nuitA = String(d.a || "")
                } catch (e) {}
                root.refreshConfigState()
            }
        }
    }

    Process {
        id: dndProc
        stdout: StdioCollector {
            onStreamFinished: root.refreshConfigState()
        }
    }

    function reglerDnd(actif) {
        root.dndActif = actif
        dndProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                           "style", "do_not_disturb", actif ? "true" : "false"]
        dndProc.running = true
    }

    function reglerNuit(args) {
        nuitProc.command = ["python3", Quickshell.shellPath("core/nuit_service.py")].concat(args)
        nuitProc.running = true
    }

    Process {
        id: homelabProc
        stdout: StdioCollector {
            onStreamFinished: root.refreshConfigState()
        }
    }

    // Après chaque geste, on relit la liste au lieu de la deviner : c'est le
    // fichier qui fait foi, et deux panneaux ouverts ne peuvent pas diverger.
    Process {
        id: todoListProc
        command: ["python3", Quickshell.shellPath("core/config_manager.py"), "todo_list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.todoFichiers = d.fichiers || []
                    root.todoFocus = String(d.focus || "")
                    root.todoSurveillance = Boolean(d.surveillance)
                } catch (e) { }
            }
        }
    }

    function homelabSet(cle, valeur) {
        homelabProc.command = ["python3", Quickshell.shellPath("core/config_manager.py"),
                               "homelab_set", cle, valeur]
        homelabProc.running = true
    }

    function homelabSetSecret(valeur) {
        if (String(valeur).trim() === "") return
        homelabSecretFile.setText(JSON.stringify({
            section: "proxmox", nom: "token_secret", valeur: String(valeur).trim()
        }))
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

    Component.onCompleted: {
        refreshConfigState()
        appletsRafraichir()
        // Ouverture demandée avant que le panneau n'existe (IPC) : la Connections
        // rate le changement d'état puisque l'item naît après. On reprend la cible ici.
        if (Theme.configPanelVisible && Theme.configTarget !== "") {
            const demande = String(Theme.configTarget)
            Theme.configTarget = ""
            root.ouvrirSection(demande)
        }
        // Un seul gestionnaire de démarrage par objet : deux lèvent
        // « Property value set multiple times » et le panneau ne se crée pas.
        todoListProc.running = true
    }

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
            text: "AetherShell · Réglages · " + root.hostName + ""
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

    // Rail vertical d'onglets : icône + libellé, pour ne plus deviner huit
    // pictogrammes abstraits (voir tmp/MOCKUP_00, §1.1).
    Column {
        id: navRail
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.space3
        anchors.left: parent.left
        anchors.leftMargin: Theme.space3
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space4
        width: 168
        spacing: Theme.space2
        z: 5

        Repeater {
            // Ordre et noms de tmp/MOCKUP_00 §2.1. Les contenus suivront dans
            // les étapes suivantes : ici seule la charpente change.
            model: [
                { icon: "palette", label: "Apparence" },
                { icon: "cog", label: "Barres & Applets" },
                { icon: "widgets", label: "Bureau & Lanceur" },
                { icon: "monitor", label: root.isLaptop ? "Écrans & Système" : "Écrans & Système" },
                { icon: "keyboard", label: "Clavier & Binds" },
                { icon: "rocket", label: "Apps & Alertes" },
                { icon: "lock", label: "Connexion" },
                { icon: "cloud-check", label: "Données & Comptes" }
            ]

            Rectangle {
                id: railBtn
                required property int index
                required property var modelData
                readonly property bool active: root.currentTab === index

                width: 168
                height: 36
                radius: Theme.globalRadius
                color: active
                    ? Theme.accent
                    : (railMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55))
                border.color: active ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: railBtn.modelData.icon
                        size: Theme.iconMd
                        color: railBtn.active ? Theme.bg : Theme.fg
                        opacityLevel: railBtn.active ? 1 : 0.78
                    }

                    Text {
                        width: 120
                        anchors.verticalCenter: parent.verticalCenter
                        text: railBtn.modelData.label
                        color: railBtn.active ? Theme.bg : Theme.fg
                        opacity: railBtn.active ? 1 : 0.86
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }
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

        // En-tête collant : quand le tiroir ouvert défile hors de vue, son titre
        // reste en haut du panneau pour qu'on puisse le refermer sans remonter.
        Rectangle {
            id: enteteCollant
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 34
            radius: Theme.globalRadius
            color: Theme.surfaceVariant
            border.color: Theme.accentMuted
            border.width: 1
            visible: root.tiroirCollant !== ""
            z: 20

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 44
                text: root.titreCollant
                color: Theme.fg
                font.pixelSize: Theme.textSm
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "▼"
                color: Theme.accent
                font.pixelSize: Theme.textSm
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.replierTiroirCollant()
            }
        }

        Flickable {
            id: mainFlickable
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: {
                if (root.currentTab === 0) return ongletEsthetique.item ? ongletEsthetique.item.implicitHeight : 0
                if (root.currentTab === 1) return tabQuickshellCol.implicitHeight
                if (root.currentTab === 2) return tabWidgetsCol.implicitHeight
                if (root.currentTab === 3) return tabSystemeCol.implicitHeight
                if (root.currentTab === 4) return tabControlesCol.implicitHeight
                if (root.currentTab === 5) return tabAppsCol.implicitHeight
                // L'onglet 7 a été inséré au milieu de l'opérateur ternaire de l'onglet 6 :
                // celui-ci rendait l'**item** du greeter au lieu de sa hauteur (contentHeight
                // valait NaN, donc ni défilement ni bornes), et l'onglet 7 mesurait la hauteur
                // du greeter en testant celle de sa propre colonne.
                if (root.currentTab === 6) return tabConnexionCol.implicitHeight
                if (root.currentTab === 7) return tabHomelabCol.implicitHeight
                return 0
            }

            onContentYChanged: root.majEnteteCollant()
            onContentHeightChanged: root.majEnteteCollant()
            onHeightChanged: root.majEnteteCollant()

            Connections {
                target: root
                function onCurrentTabChanged() {
                    mainFlickable.contentY = 0
                }
            }

            // ═══════════════════════════════════════════════════════════════════════════
            // TAB 0: BUREAU — fonds d'écran, thèmes, fenêtres Hyprland, barre et surfaces.
            // Le tiroir « Barre & surfaces » est ici ; les barres annexes, les applets
            // et le visualiseur sont dans l'onglet « Quickshell ».
            // ═══════════════════════════════════════════════════════════════════════════
        // Onglet « Bureau » : 1 500 lignes déplacées dans OngletEsthetique.qml,
        // instanciées seulement quand l'onglet s'ouvre. Le fichier du panneau ne
        // garde que le tronc commun (rail, recherche, en-tête collant) et les
        // Loaders — voir la règle de gel en tête de fichier.
        Loader {
            id: ongletEsthetique
            width: mainFlickable.width
            active: root.currentTab === 0
            source: "OngletEsthetique.qml"
            onLoaded: {
                item.root = root
                item.mainFlickable = mainFlickable
            }
        }
        // ═════════════════════════════════════════════════════════════════════
        // TAB 1: GESTION QUICKSHELL — barres annexes, applets et visualiseur.
        // La barre elle-même (îlots, panneau, popups) est dans l'onglet « Bureau ».
        // ═════════════════════════════════════════════════════════════════════
        Column {
            id: tabQuickshellCol
            visible: root.currentTab === 1
            width: mainFlickable.width
            spacing: 11



            // Tiroir 3 : les barres optionnelles. Une barre allumée mais sans
            // applet reste invisible : on le dit, sinon le réglage semble cassé.
            CollapsibleSection {
                id: secBarres
                objectName: "secBarres"
                title: "Barre principale & Barres annexes"
                summary: "Hauteur " + Theme.barHeight + " · " + (root.barGapsTransparent ? "îlots transparents" : "capsule continue")
                icon: "monitor"
                expanded: root.sectionOpen("quickshell_barres", true)
                onToggled: expanded => {
                    root.setPanelSection("quickshell_barres", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_barres")
                }

                Column {
                    // Barre principale : géométrie, bordure, espaces entre les
                    // îlots et bouton central. Ces réglages dessinaient autrefois une
                    // section « Barre & surfaces » dans l'onglet Apparence.
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

                    // 5b. Arrondis des fenêtres de sélecteurs (fichiers/dossiers) : 0 = suit la règle générale
                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            width: 160
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Arrondis sélecteurs :"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            elide: Text.ElideRight
                        }

                        Slider {
                            anchors.verticalCenter: parent.verticalCenter
                            value: Theme.selecteurRadius
                            minimumValue: 0
                            maximumValue: 30
                            stepSize: 1
                            suffix: value === 0 ? " (auto)" : " px"
                            onValueModified: newVal => {
                                root.runConfigCmd(["style", "selecteur_radius", String(newVal)])
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
                    Row {
                        id: barGapsRow   // ancre de recherche
                        objectName: "barGapsRow"
                        width: parent.width
                        spacing: 8

                        Text {
                            width: 160
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Espaces entre les îlots :"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 160
                            height: 26
                            radius: Theme.globalRadius
                            color: root.barGapsTransparent ? Theme.accent : Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.barGapsTransparent ? "✓ Transparents" : "✕ Peints"
                                color: root.barGapsTransparent ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.barGapsTransparent = !root.barGapsTransparent
                                    root.runConfigCmd(["style", "bar_gaps_transparent", root.barGapsTransparent ? "true" : "false"])
                                }
                            }
                        }
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
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "Une barre allumée apparaît aussitôt, même vide : elle affiche "
                              + "alors un rappel. Pour la remplir, choisissez l'emplacement "
                              + "↓ ← → dans la liste des applets."
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                        wrapMode: Text.WordWrap
                    }
                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Barre du bas"
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 110
                            height: 20
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.globalRadius
                            color: Theme.barBottomVisible ? Theme.accent : Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Theme.barBottomVisible ? "✓ Affichée" : "Masquée"
                                color: Theme.barBottomVisible ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["style", "bar_bottom",
                                    String(!Theme.barBottomVisible)])
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Barre de gauche"
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 110
                            height: 20
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.globalRadius
                            color: Theme.barLeftVisible ? Theme.accent : Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Theme.barLeftVisible ? "✓ Affichée" : "Masquée"
                                color: Theme.barLeftVisible ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["style", "bar_left",
                                    String(!Theme.barLeftVisible)])
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 22

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Barre de droite"
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 110
                            height: 20
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.globalRadius
                            color: Theme.barRightVisible ? Theme.accent : Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Theme.barRightVisible ? "✓ Affichée" : "Masquée"
                                color: Theme.barRightVisible ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["style", "bar_right",
                                    String(!Theme.barRightVisible)])
                            }
                        }
                    }
                }
            }

            // Tiroir 2 : les applets. Un applet n'a qu'un emplacement ; l'ordre
            // se règle aux flèches, l'échelle par applet.
            CollapsibleSection {
                id: secApplets
                objectName: "secApplets"
                title: "Applets de la barre"
                summary: root.appletRows.length + " applets"
                icon: "widgets"
                expanded: root.sectionOpen("quickshell_applets", false)
                onToggled: expanded => {
                    root.setPanelSection("quickshell_applets", expanded)
                    if (expanded) disquesListeProc.running = true
                }
                Component.onCompleted: disquesListeProc.running = true

                Column {
                    width: parent.width
                    spacing: 8


                    Text {
                        width: parent.width
                        text: "Éteints par défaut. Un applet n'a qu'un emplacement : "
                              + "le choisir ailleurs le déplace, il ne se duplique pas. "
                              + "Le visualiseur audio fait exception : il n'a pas d'emplacement, "
                              + "il occupe les espaces entre les îlots (un de chaque côté du centre)."
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                        wrapMode: Text.WordWrap
                    }

                    Column {
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: root.appletEntries

                            delegate: Column {
                                id: appletRow
                                // Les propriétés `required` doivent vivre sur la
                                // racine du délégué, pas sur son enfant.
                                required property var modelData

                                readonly property bool estTitre: modelData.genre === "titre"
                                // Une tête de catégorie n'a pas de données
                                // d'applet : un objet neutre évite les
                                // « Unable to assign [undefined] » que lèvent
                                // les liaisons de la ligne, même invisible.
                                readonly property var donnee: estTitre
                                    ? ({ id: "", nom: "", ile: "", actif: false,
                                         text_scale: 100, options: ({}) })
                                    : modelData.applet
                                width: parent.width
                                spacing: 3

                                // ── tête de catégorie ────────────────────────────
                                // Un petit titre et un trait : le panneau devient
                                // lisible par groupes au lieu d'une liste de
                                // dix-neuf lignes au même niveau. Le trait est
                                // sous le titre, pas entre deux catégories : il
                                // sépare le titre de ses lignes.
                                Column {
                                    width: parent.width
                                    visible: appletRow.estTitre
                                    spacing: 5

                                    Item { width: 1; height: 6 }

                                    Text {
                                        width: parent.width
                                        text: appletRow.estTitre ? String(modelData.texte) : ""
                                        color: Qt.alpha(Theme.fg, 0.6)
                                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                        font.capitalization: Font.AllUppercase
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Qt.alpha(Theme.fg, 0.14)
                                    }
                                }

                                Rectangle {
                                visible: !appletRow.estTitre
                                width: parent.width
                                height: 30
                                radius: Theme.globalRadius
                                color: appletRow.donnee.actif
                                    ? Qt.alpha(Theme.accent, 0.10) : Theme.surfaceVariant
                                border.width: 1
                                border.color: appletRow.donnee.actif
                                    ? Qt.alpha(Theme.accent, 0.5) : "transparent"

                                // Toute la ligne bascule l'applet : la seule case
                                // de 12 px obligeait à viser, et les contrôles de
                                // droite (flèches, pastilles, échelle) la recouvrent
                                // puisqu'ils sont déclarés après celle-ci.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.appletBasculer(appletRow.donnee.id,
                                                                   appletRow.donnee.actif)
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Rectangle {
                                        width: 12
                                        height: 12
                                        radius: 3
                                        color: appletRow.donnee.actif ? Theme.accent : "transparent"
                                        border.width: 1
                                        border.color: appletRow.donnee.actif
                                            ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: appletRow.donnee.actif
                                            text: "✓"
                                            color: Theme.bg
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.appletBasculer(appletRow.donnee.id,
                                                                           appletRow.donnee.actif)
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: appletRow.donnee.nom
                                        color: Theme.fg
                                        font.pixelSize: Theme.textXs
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    // Ordre d'affichage : échange avec le voisin
                                    // du même îlot. Deux flèches plutôt qu'un
                                    // numéro à saisir — l'ordre n'a de sens que
                                    // relativement aux autres.
                                    Row {
                                        spacing: 3
                                        opacity: appletRow.donnee.actif ? 1 : 0.35

                                        Rectangle {
                                            width: 14
                                            height: 16
                                            radius: 4
                                            color: "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "‹"
                                                color: Theme.fg
                                                font.pixelSize: Theme.textXs
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (appletRow.donnee.actif)
                                                    root.appletCommande(["monter", appletRow.donnee.id])
                                            }
                                        }

                                        Rectangle {
                                            width: 14
                                            height: 16
                                            radius: 4
                                            color: "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "›"
                                                color: Theme.fg
                                                font.pixelSize: Theme.textXs
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (appletRow.donnee.actif)
                                                    root.appletCommande(["descendre", appletRow.donnee.id])
                                            }
                                        }
                                    }

                                    // Échelle de texte de cet applet : la même
                                    // règle que les widgets, appliquée par applet.
                                    // Boutons dans des Rectangles : un MouseArea
                                    // avec `anchors.fill` ne peut pas être enfant
                                    // direct d'un Row (le positionneur refuse les
                                    // ancres horizontales), d'où l'enveloppe.
                                    Row {
                                        spacing: 3
                                        opacity: appletRow.donnee.actif ? 1 : 0.35

                                        Rectangle {
                                            width: 14
                                            height: 16
                                            radius: 4
                                            color: "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "−"
                                                color: Theme.fg
                                                font.pixelSize: Theme.textXs
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.appletEchelle(appletRow.donnee.id,
                                                                              appletRow.donnee.text_scale - 5)
                                            }
                                        }

                                        Text {
                                            text: appletRow.donnee.text_scale + " %"
                                            color: Qt.alpha(Theme.fg, 0.75)
                                            font.pixelSize: Math.max(9, Theme.textXs - 1)
                                            font.features: { "tnum": 1 }
                                        }

                                        Rectangle {
                                            width: 14
                                            height: 16
                                            radius: 4
                                            color: "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: "+"
                                                color: Theme.fg
                                                font.pixelSize: Theme.textXs
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.appletEchelle(appletRow.donnee.id,
                                                                              appletRow.donnee.text_scale + 5)
                                            }
                                        }
                                    }

                                    // Groupe 1 : la barre. Reste réglable même
                                    // pour un applet à emplacement fixe : le
                                    // visualiseur n'a pas de place *dans* une
                                    // barre, mais il choisit *quelle* barre le
                                    // porte — une seule à la fois, et la
                                    // pastille active est en couleur d'accent.
                                    Row {
                                        spacing: 2

                                        Repeater {
                                            model: root.appletBarres

                                            Rectangle {
                                                required property var modelData
                                                readonly property bool choisi:
                                                    root.barreDe(appletRow.donnee) === modelData.code
                                                width: 17
                                                height: 16
                                                radius: 4
                                                color: choisi ? Theme.accent : "transparent"
                                                border.width: 1
                                                border.color: choisi
                                                    ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                                opacity: appletRow.donnee.actif ? 1 : 0.35

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                                    font.pixelSize: Math.max(8, Theme.textXs - 2)
                                                    font.bold: parent.choisi
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.placerApplet(appletRow.donnee.id,
                                                        modelData.code + ":" + root.zoneDe(appletRow.donnee))
                                                }
                                            }
                                        }
                                    }

                                    // Groupe 2 : la place dans la barre (début,
                                    // milieu, fin). Sur la barre du haut, ce sont
                                    // les trois îlots historiques G / C / D.
                                    Row {
                                        spacing: 2
                                        visible: !appletRow.donnee.fixe

                                        Repeater {
                                            model: root.appletZones

                                            Rectangle {
                                                required property var modelData
                                                readonly property bool choisi:
                                                    root.zoneDe(appletRow.donnee) === modelData.code
                                                readonly property bool enHaut:
                                                    root.barreDe(appletRow.donnee) === "haut"
                                                width: 17
                                                height: 16
                                                radius: 4
                                                color: choisi ? Theme.accent : "transparent"
                                                border.width: 1
                                                border.color: choisi
                                                    ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                                opacity: appletRow.donnee.actif ? 1 : 0.35

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: parent.enHaut ? modelData.labelA : modelData.labelB
                                                    color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                                    font.pixelSize: Math.max(8, Theme.textXs - 2)
                                                    font.bold: parent.choisi
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.placerApplet(appletRow.donnee.id,
                                                        root.barreDe(appletRow.donnee) + ":" + modelData.code)
                                                }
                                            }
                                        }
                                    }
                                }
                                }

                                // Choix déclaré au catalogue : ici, le service que
                                // l'applet des comptes affiche dans la barre.
                                Row {
                                    visible: appletRow.donnee.choix !== undefined
                                    width: parent.width
                                    height: visible ? 18 : 0
                                    spacing: 4

                                    Item { width: 26; height: 1 }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(appletRow.donnee.choix && appletRow.donnee.choix.libelle
                                                     ? appletRow.donnee.choix.libelle : "")
                                        color: Qt.alpha(Theme.fg, 0.5)
                                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                                    }

                                    Repeater {
                                        model: (appletRow.donnee.choix && appletRow.donnee.choix.valeurs) || []

                                        Rectangle {
                                            required property var modelData
                                            readonly property bool choisi: {
                                                const o = appletRow.donnee.options || ({})
                                                const cle = appletRow.donnee.choix
                                                    ? appletRow.donnee.choix.cle : ""
                                                return String(o[cle] || "") === String(modelData.code)
                                            }
                                            width: 62
                                            height: 16
                                            radius: 4
                                            color: choisi ? Theme.accent : "transparent"
                                            border.width: 1
                                            border.color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                            opacity: appletRow.donnee.actif ? 1 : 0.35

                                            Text {
                                                anchors.centerIn: parent
                                                text: String(modelData.nom || modelData.code)
                                                color: choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                                font.bold: choisi
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (appletRow.donnee.actif)
                                                    root.appletCommande(["option", appletRow.donnee.id,
                                                                         appletRow.donnee.choix.cle,
                                                                         String(modelData.code)])
                                            }
                                        }
                                    }
                                }

                                // Petit tiroir : la sélection des systèmes de
                                // fichiers, sur deux colonnes. Replié par défaut,
                                // il ne mange pas la place des autres applets.
                                CollapsibleSection {
                                    id: secDisques
                                    visible: appletRow.donnee.liste !== undefined
                                    title: String((appletRow.donnee.liste || ({})).libelle
                                                  || "Disques affichés")
                                    icon: "disque"
                                    expanded: root.sectionOpen("quickshell_disques", false)
                                    onToggled: expanded => {
                    root.setPanelSection("quickshell_disques", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_disques")
                }

                                    Grid {
                                        id: grilleDisques
                                        width: parent.width
                                        columns: 2
                                        columnSpacing: 10
                                        rowSpacing: 3
                                        topPadding: 4

                                        Repeater {
                                            model: root.disquesListe

                                            // Item et non Row : un MouseArea en
                                            // `anchors.fill` ne peut pas être
                                            // enfant direct d'un positionneur, et
                                            // c'est ce qui rendait les cases inertes.
                                            Item {
                                                required property var modelData
                                                readonly property string montage: String(modelData.montage || "")
                                                readonly property bool coche: {
                                                    // Deux précautions : lire la
                                                    // signature (dépendance réactive)
                                                    // et relire l'entrée courante par
                                                    // id — le `modelData` du délégué
                                                    // reste figé sur l'ancienne copie
                                                    // quand la liste est réaffectée.
                                                    const _ = root.appletSignature
                                                    const vive = root.entreeApplet(appletRow.donnee.id)
                                                                 || appletRow.donnee
                                                    return root.montageCoche(vive, montage)
                                                }

                                                width: (grilleDisques.width - grilleDisques.columnSpacing) / 2
                                                height: 18

                                                Rectangle {
                                                    id: boite
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 12
                                                    height: 12
                                                    radius: 3
                                                    color: parent.coche ? Theme.accent : "transparent"
                                                    border.width: 1
                                                    border.color: parent.coche ? Theme.accent
                                                                               : Qt.alpha(Theme.fg, 0.4)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: parent.parent.coche
                                                        text: "✓"
                                                        color: Theme.bg
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                    }
                                                }

                                                Text {
                                                    anchors.left: boite.right
                                                    anchors.leftMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - 20 - pourcentage.implicitWidth
                                                    text: parent.montage
                                                    color: Theme.fg
                                                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    id: pourcentage
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: String(modelData.pourcent) + " %"
                                                    color: Qt.alpha(Theme.fg, 0.45)
                                                    font.pixelSize: Math.max(8, Theme.textXs - 2)
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.basculerMontage(appletRow.donnee,
                                                                                    parent.montage)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Cases déclarées au catalogue : un réglage
                                // vrai/faux par applet, écrit comme une option
                                // (absent = activé, valeur par défaut du catalogue).
                                Row {
                                    visible: (appletRow.donnee.cases || []).length > 0
                                    width: parent.width
                                    height: visible ? 18 : 0
                                    spacing: 4

                                    Item { width: 26; height: 1 }

                                    Repeater {
                                        model: appletRow.donnee.cases || []

                                        Rectangle {
                                            required property var modelData
                                            readonly property bool coche: {
                                                const _ = root.appletSignature
                                                const vive = root.entreeApplet(appletRow.donnee.id)
                                                             || appletRow.donnee
                                                const o = vive.options || ({})
                                                const v = o[modelData.cle]
                                                if (v === undefined || v === null || v === "") return true
                                                return !(v === false || v === "false"
                                                         || v === 0 || v === "0")
                                            }
                                            width: caseTexte.implicitWidth + 16
                                            height: 16
                                            radius: 4
                                            color: coche ? Theme.accent : "transparent"
                                            border.width: 1
                                            border.color: coche ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                            opacity: appletRow.donnee.actif ? 1 : 0.35

                                            Text {
                                                id: caseTexte
                                                anchors.centerIn: parent
                                                text: (coche ? "\u2713 " : "\u2715 ")
                                                      + String(modelData.libelle || modelData.cle)
                                                color: coche ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                                font.bold: coche
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (appletRow.donnee.actif)
                                                    root.appletCommande(["option", appletRow.donnee.id,
                                                                         modelData.cle,
                                                                         coche ? "false" : "true"])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
                // ═══════════════════════════════════════════════════════════════
                // Visualiseur audio — capture et dessin
                // ═══════════════════════════════════════════════════════════════
                CollapsibleSection {
                    id: secVisualiseur
                    objectName: "secVisualiseur"
                    title: "Visualiseur audio"
                    summary: (root.vizActif ? "actif" : "coupé") + " · " + (root.vizStyle === "barres" ? "barres" : "onde")
                    icon: "music"
                    expanded: root.sectionOpen("quickshell_visualiseur", false)
                    onToggled: expanded => {
                    root.setPanelSection("quickshell_visualiseur", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_visualiseur")
                }

                    Column {
                        width: parent.width
                        spacing: 8

                        // Activation : elle vivait dans la liste des applets, où
                        // elle n'avait rien à faire (aucun emplacement à choisir).
                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                width: 160
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Visualiseur :"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 160
                                height: 26
                                radius: Theme.globalRadius
                                color: root.vizActif ? Theme.accent : Theme.surfaceVariant
                                border.color: Theme.accent
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: root.vizActif ? "✓ Actif" : "✕ Éteint"
                                    color: root.vizActif ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.basculerVisualiseur()
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 340
                                text: "Occupe les espaces entre les îlots, un de chaque côté du centre."
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.pixelSize: Theme.text2xs
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Rendu : une ligne qui ne défile pas (onde) ou des bandes
                        // qui montent avec la musique (barres). Option d'applet du
                        // registre, exposée ici parce que c'est elle qui décide de
                        // l'allure du visualiseur.
                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                width: 160
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Mode :"
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: [{ code: "onde", nom: "Onde" },
                                        { code: "barres", nom: "Barres" }]

                                Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 92
                                    height: 26
                                    radius: Theme.globalRadius
                                    color: root.vizStyle === modelData.code ? Theme.accent
                                                                            : Theme.surfaceVariant
                                    border.color: Theme.accent
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.vizStyle === modelData.code
                                              ? ("✓ " + modelData.nom) : modelData.nom
                                        color: root.vizStyle === modelData.code ? Theme.bg : Theme.fg
                                        font.pixelSize: Theme.textXs
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.changerModeVisualiseur(modelData.code)
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 380
                                text: "L'onde suit le signal, les barres suivent le spectre. "
                                      + "Les barres s'alignent sur les colonnes : une bande pour quatre."
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.pixelSize: Theme.text2xs
                                wrapMode: Text.WordWrap
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Images par seconde :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.vizFps
                                minimumValue: 10; maximumValue: 60; stepSize: 5; decimals: 0
                                onValueModified: newVal => {
                                    root.vizFps = newVal
                                    root.runConfigCmd(["style", "viz_fps", String(newVal)])
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Colonnes :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.vizCols
                                minimumValue: 16; maximumValue: 256; stepSize: 8; decimals: 0
                                onValueModified: newVal => {
                                    root.vizCols = newVal
                                    root.runConfigCmd(["style", "viz_cols", String(newVal)])
                                }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "bandes en mode barres : colonnes / 4"; color: Qt.alpha(Theme.fg, 0.45); font.pixelSize: Math.max(9, Theme.textXs - 1) }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Sensibilité :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.vizSensibilite
                                minimumValue: 0.05; maximumValue: 4.0; stepSize: 0.05; decimals: 2
                                onValueModified: newVal => {
                                    root.vizSensibilite = newVal
                                    root.runConfigCmd(["style", "viz_sensibilite", String(newVal)])
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Lissage :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.vizLissage
                                minimumValue: 0.0; maximumValue: 0.99; stepSize: 0.05; decimals: 2
                                onValueModified: newVal => {
                                    root.vizLissage = newVal
                                    root.runConfigCmd(["style", "viz_lissage", String(newVal)])
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Épaisseur du trait :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.vizEpaisseur
                                minimumValue: 0.5; maximumValue: 4.0; stepSize: 0.5; decimals: 1
                                onValueModified: newVal => {
                                    root.vizEpaisseur = newVal
                                    root.runConfigCmd(["style", "viz_epaisseur", String(newVal)])
                                }
                            }
                        }

                        // Couleur : des jetons du thème, pas une valeur libre — une
                        // couleur en dur ne suivrait pas un changement de palette.
                        Row {
                            width: parent.width
                            spacing: 8

                            Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Couleur :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }

                            // Flow plutôt que Row : à cinq jetons et 540 px de
                            // contenu, la dernière pastille sortait du panneau.
                            // Flow passe à la ligne tout seul.
                            Flow {
                                spacing: 6
                                width: parent.width - 168
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: root.vizCouleurs

                                    Rectangle {
                                        required property var modelData
                                        readonly property bool choisi: root.vizCouleur === modelData.code
                                        width: 74; height: 22; radius: Theme.globalRadius
                                        color: choisi ? root.couleurViz(modelData.code) : "transparent"
                                        border.color: root.couleurViz(modelData.code)
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.nom
                                            color: parent.choisi ? Theme.bg : root.couleurViz(modelData.code)
                                            font.pixelSize: Math.max(8, Theme.textXs - 2)
                                            font.bold: parent.choisi
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.vizCouleur = modelData.code
                                                root.runConfigCmd(["style", "viz_couleur", modelData.code])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


        }


        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 1: WIDGETS DU BUREAU (sur les workspaces, réglages par widget)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabWidgetsCol
            visible: root.currentTab === 2
            width: mainFlickable.width
            spacing: 11

            CollapsibleSection {
                id: secWidgets
                objectName: "secWidgets"
                title: "Widgets du bureau"
                summary: root.widgetsList.length + " widgets"
                icon: "widgets"
                // État persisté comme les autres tiroirs ; ouvert par défaut,
                // c'est le premier de l'onglet « Bureau & Lanceur ».
                expanded: root.sectionOpen("widgets", true)
                onToggled: expanded => {
                    root.setPanelSection("widgets", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets")
                }

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
                        // Sans hauteur explicite, un texte replié sur deux lignes
                        // gardait la hauteur d'une seule et la ligne suivante
                        // (les pastilles des widgets) passait par-dessus.
                        height: contentHeight
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
                            // Échelle du texte (options.text_scale) : 100 = taille du
                            // thème, 85 par défaut pour les widgets de compte LLM, qui
                            // empilent deux lignes de texte dense.
                            // Ne pas prendre un onglet de navigateur pour de la
                            // musique. Absent = on ignore (défaut du widget).
                            readonly property bool wIgnorerNavigateurs: {
                                const v = widgetCard.wOptions.ignorer_navigateurs
                                if (v === undefined || v === null || v === "") return true
                                return !(v === false || v === "false" || v === 0 || v === "0")
                            }

                            // Widget Tâches : fichiers suivis, nombre de lignes et
                            // affichage des cochés. Une liste vide veut dire « tous »
                            // — c'est le défaut d'un widget sans options.
                            readonly property var wFichiers: {
                                const brut = widgetCard.wOptions.fichiers
                                let liste = Array.isArray(brut)
                                          ? brut.map(function (s) { return String(s) })
                                          : (typeof brut === "string" && brut !== ""
                                             ? brut.split(",").map(function (s) { return s.trim() })
                                             : [])
                                liste = liste.filter(function (s) { return s !== "" })
                                if (liste.length === 0) {
                                    const tous = []
                                    for (let i = 0; i < root.todoFichiers.length; ++i)
                                        tous.push(String(root.todoFichiers[i].nom || ""))
                                    return tous
                                }
                                return liste
                            }
                            readonly property int wLignes: {
                                const v = Number(widgetCard.wOptions.lignes)
                                return (v >= 1 && v <= 6) ? Math.round(v) : 3
                            }
                            readonly property bool wAfficherFaits: {
                                const v = widgetCard.wOptions.afficher_faits
                                return v === true || v === "true" || v === 1 || v === "1"
                            }

                            readonly property int wTextScale: {
                                const v = Number(widgetCard.wOptions.text_scale)
                                if (v >= 60 && v <= 160) return Math.round(v)
                                const ia = ["deepseek", "ollama", "antigravity"]
                                return ia.indexOf(widgetCard.wtype) >= 0 ? 85 : 100
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
                                               : (widgetCard.wtype === "combo" ? "widgets"
                                               : (widgetCard.wtype === "systeme" ? "monitor"
                                               : "clock"))))
                                        size: Theme.iconSm
                                        color: Theme.accent
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 14 - 18 - Theme.space2 * 2
                                        text: root.libelleWidget(widgetCard.wtype)
                                              + "  ·  " + widgetCard.wid
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

                                    // L'échelle du texte vaut pour tous les widgets :
                                    // c'est le premier réglage qu'on cherche quand un
                                    // widget déborde de sa taille.
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Texte"
                                            color: Qt.alpha(Theme.fg, 0.6)
                                            font.pixelSize: Theme.text2xs
                                        }

                                        Stepper {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 92
                                            value: widgetCard.wTextScale
                                            minimumValue: 60
                                            maximumValue: 160
                                            stepSize: 5
                                            suffix: " %"
                                            onValueModified: newVal =>
                                                root.runConfigCmd(["widget_set", widgetCard.wid,
                                                                   "text_scale", String(newVal)])
                                        }
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

                                    // Les navigateurs ne concernent que le widget
                                    // musique : ailleurs, la question n'a pas de sens.
                                    Rectangle {
                                        visible: widgetCard.wtype === "musique"
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 118
                                        height: 24
                                        radius: Theme.globalRadius
                                        color: widgetCard.wIgnorerNavigateurs
                                            ? Theme.accent : Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: (widgetCard.wIgnorerNavigateurs ? "✓ " : "✕ ")
                                                  + "Navigateurs"
                                            color: widgetCard.wIgnorerNavigateurs ? Theme.bg : Theme.fg
                                            font.pixelSize: Theme.text2xs
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.runConfigCmd([
                                                "widget_set", widgetCard.wid, "ignorer_navigateurs",
                                                widgetCard.wIgnorerNavigateurs ? "false" : "true"
                                            ])
                                        }
                                    }

                                    // La ville ne concerne que la météo : elle
                                    // s'affichait sur tous les autres widgets, avec son
                                    // « Auto (IP) » qui n'y veut rien dire.
                                    Row {
                                        visible: widgetCard.wtype === "deepseek"
                                                 || widgetCard.wtype === "ollama"
                                                 || widgetCard.wtype === "antigravity"
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
                                // Widget Tâches : quels fichiers suivis, combien de
                                // lignes d'items, et si les items cochés comptent. La
                                // liste vide veut dire « tous » (défaut historique).
                                Row {
                                    width: parent.width
                                    spacing: Theme.space2
                                    visible: widgetCard.wtype === "todo"

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 56
                                        text: "Tâches"
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.textXs
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Repeater {
                                            model: root.todoFichiers

                                            Rectangle {
                                                required property var modelData
                                                readonly property bool pris:
                                                    widgetCard.wFichiers.indexOf(String(modelData.nom)) >= 0
                                                width: nomFichier.width + 16
                                                height: 24
                                                radius: Theme.globalRadius
                                                color: pris ? Qt.alpha(Theme.accent, 0.16)
                                                            : Theme.surfaceVariant
                                                border.width: 1
                                                border.color: pris ? Theme.accent : Theme.surfaceVariant

                                                Text {
                                                    id: nomFichier
                                                    anchors.centerIn: parent
                                                    text: String(modelData.nom || "")
                                                    color: Theme.fg
                                                    font.pixelSize: Theme.textXs
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.basculerFichierWidget(
                                                                   widgetCard.wid, modelData.nom)
                                                }
                                            }
                                        }
                                    }

                                    Stepper {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 84
                                        value: widgetCard.wLignes
                                        minimumValue: 1
                                        maximumValue: 6
                                        stepSize: 1
                                        suffix: " l."
                                        onValueModified: newVal =>
                                            root.runConfigCmd(["widget_set", widgetCard.wid,
                                                               "lignes", String(newVal)])
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 92
                                        height: 24
                                        radius: Theme.globalRadius
                                        color: widgetCard.wAfficherFaits ? Theme.accent : Theme.surfaceVariant
                                        border.width: 1
                                        border.color: Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: widgetCard.wAfficherFaits ? "✓ cochés" : "✕ cochés"
                                            color: widgetCard.wAfficherFaits ? Theme.bg : Theme.fg
                                            font.pixelSize: Theme.textXs
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.runConfigCmd([
                                                "widget_set", widgetCard.wid, "afficher_faits",
                                                widgetCard.wAfficherFaits ? "false" : "true"
                                            ])
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
                            // Six rangées visibles (28 px + 6 d'écart) : les dix-sept
                            // natures tiennent en 6 lignes de trois colonnes. Au-delà,
                            // on fait défiler et la bande du bas le signale.
                            height: Math.min(gridPicker.implicitHeight, 6 * 28 + 5 * 6 + 2)

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
                            // dépasse les rangées visibles.
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

                            // « Il en reste en dessous » : une bande dégradée et un
                            // chevron, qui disparaissent une fois arrivé au bas de la
                            // liste. Le simple trait de 3 px ne se voyait pas.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 26
                                visible: widgetPicker.contentHeight > widgetPicker.height + 1
                                         && widgetPicker.contentY + widgetPicker.height
                                            < widgetPicker.contentHeight - 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.55; color: Qt.alpha(Theme.bg, 0.82) }
                                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.96) }
                                }

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 1
                                    glyph: "chevron-down"
                                    size: 14
                                    color: Theme.accent
                                }
                            }
                        }
                    }


                }
            }
            // Tiroir : la pilule de lancement (Spotlight). Sa position et son
            // historique étaient éparpillés dans deux onglets.
            CollapsibleSection {
                id: secPilule
                objectName: "secPilule"
                title: "Pilule de lancement (Spotlight)"
                summary: root.launcherPosition
                icon: "rocket"
                expanded: root.sectionOpen("widgets_pilule", false)
                onToggled: expanded => {
                    root.setPanelSection("widgets_pilule", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_pilule")
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


                // Respiration entre le choix de position et la ligne d'historique :
                // les deux règlent la même pilule, mais se lisaient comme un seul
                // bloc compact.
                Item { width: parent.width; height: Theme.space2 * 3 }

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
                // 0,8 × la taille du bouton voisin (32) : il efface un historique,
                // il n'a pas à peser autant que la bascule qu'il accompagne.
                width: visible ? clearHistText.implicitWidth + 18 : 0
                height: 26
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
            }


            // Accès API : les widgets qui interrogent un service externe ont besoin
            // d'une clé. Elle est rangée dans secrets.json (mode 600) et le panneau
            // ne montre jamais que ses derniers caractères.

            // Cadenas des widgets : hors tiroir, sous les réglages. Il vaut pour
            // tout le bureau, pas pour un widget — c'est une garde contre le
            // déplacement accidentel (SUPER + SHIFT + clic).
            Item { width: 1; height: 12 }

            Row {
                width: parent.width
                spacing: 10

                Text {
                    width: 200
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Déplacement des widgets :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: 120
                    height: 26
                    radius: Theme.globalRadius
                    color: Theme.widgetsLocked ? Theme.accent : Theme.surfaceVariant
                    border.color: Theme.accent
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        // Glyphe monochrome du jeu d'icônes : l'emoji de cadenas
                        // arrive en couleur dans une barre qui n'en a aucun.
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "lock"
                            size: Theme.iconSm
                            color: Theme.widgetsLocked ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                            opacityLevel: 1
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.widgetsLocked ? "Verrouillé" : "Libre"
                            color: Theme.widgetsLocked ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd([
                            "style", "widgets_locked",
                            Theme.widgetsLocked ? "false" : "true"
                        ])
                    }
                }

            }

        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB HOMELAB : ce qui parle à l'extérieur — Nextcloud d'un côté, Proxmox de
        // l'autre. Sortis de l'onglet Quickshell, où ils n'avaient rien à faire : la
        // barre et les applets se règlent là-bas, pas les accès aux serveurs.
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabHomelabCol
            visible: root.currentTab === 7
            width: mainFlickable.width
            spacing: 12


            // Tiroir : fournisseurs d'IA, une ligne par fournisseur. Les clés
            // ne sortent jamais du shell : le fichier est en mode 600.
            CollapsibleSection {
                id: secApiKeys
                objectName: "secApiKeys"
                title: "Accès API"
                summary: Object.keys(root.apiKeys).length + " clés"
                icon: "lock"
                expanded: root.sectionOpen("widgets_api", false)
                onToggled: expanded => {
                    root.setPanelSection("widgets_api", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_api")
                }

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

                            // Un fournisseur local (quota lu sur la machine) n'a
                            // pas de clé : afficher un champ vide laisserait croire
                            // qu'il en manque une.
                            Text {
                                width: parent.width
                                visible: (modelData.key || "") === ""
                                text: "aucune clé — la donnée est lue localement"
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.pixelSize: Theme.text2xs
                                font.italic: true
                            }

                            Row {
                                width: parent.width
                                spacing: 10
                                visible: (modelData.key || "") !== ""

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

            // Tiroir : localisation de l'utilisateur. Un seul endroit pour « où
            // suis-je » : l'applet et le widget météo, l'horloge et le calendrier
            // lisent les clés user_location_* de style_vars.json.
            CollapsibleSection {
                id: secLocalisation
                objectName: "secLocalisation"
                title: "Localisation"
                summary: root.timezoneStr
                icon: "cloud"
                expanded: root.sectionOpen("donnees_localisation", true)
                onToggled: expanded => {
                    root.setPanelSection("donnees_localisation", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("donnees_localisation")
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "Ville et coordonnées lues par les applets et widgets qui ont besoin de "
                            + "savoir où l'on est — la météo d'abord, mais aussi l'horloge et le calendrier "
                            + "pour le fuseau. Sans coordonnées, ils annoncent « localisation non réglée » "
                            + "plutôt que d'inventer une position."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                        height: contentHeight
                    }

                    // Ville + bouton de vérification (géocodage Open-Meteo, sans clé).
                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            width: 76
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Ville"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: parent.width - 76 - 8 - verifier.width - 8
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champVille
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textSm
                                clip: true
                                text: Theme.userLocationVille
                                onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                                          champLon.text, champTz.text)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: parent.text === ""
                                    text: "Paris, France"
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: Theme.textSm
                                }
                            }
                        }

                        Rectangle {
                            id: verifier
                            width: 96
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: geocodage.running ? "…" : "Vérifier"
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.geocoder(champVille.text)
                            }
                        }
                    }

                    // Latitude / longitude : remplies par « Vérifier », modifiables à la main.
                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            width: 76
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Latitude"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 120
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champLat
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                text: Theme.userLocationSet ? String(Theme.userLocationLat) : ""
                                onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                                          champLon.text, champTz.text)
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Longitude"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 120
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champLon
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                text: Theme.userLocationSet ? String(Theme.userLocationLon) : ""
                                onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                                          champLon.text, champTz.text)
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            width: 76
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Fuseau"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 200
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champTz
                                anchors.fill: parent
                                anchors.margins: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textSm
                                text: Theme.userLocationTz
                                onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                                          champLon.text, champTz.text)
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Europe/Paris"
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.pixelSize: Theme.text2xs
                        }
                    }

                    Text {
                        id: etatLocalisation
                        width: parent.width
                        text: Theme.userLocationSet
                              ? "Réglée : " + (Theme.userLocationVille || "sans nom")
                                + " (" + Theme.userLocationLat + ", " + Theme.userLocationLon + ")"
                                + (Theme.userLocationTz ? " · " + Theme.userLocationTz : "")
                              : "Non réglée : les applets et widgets qui en dépendent le disent à l'écran."
                        color: Theme.userLocationSet ? Qt.alpha(Theme.fg, 0.6) : Qt.alpha(Theme.warn, 0.85)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                        height: contentHeight
                    }

                    // Géocodage : le service météo sait déjà le faire, on lui demande
                    // la même chose que pour un `--city`, et il rend le fuseau en plus.
                    Process {
                        id: geocodage
                        stdout: StdioCollector {
                            onStreamFinished: {
                                let d = null
                                try { d = JSON.parse(String(text).trim()) } catch (e) { d = null }
                                if (!d || !d.ok) {
                                    etatLocalisation.text = "Ville introuvable : "
                                        + String((d && d.error) || "réponse illisible")
                                    return
                                }
                                champVille.text = d.libelle || d.ville || ""
                                champLat.text = String(d.lat)
                                champLon.text = String(d.lon)
                                champTz.text = d.tz || ""
                                root.enregistrerLocalisation(champVille.text, champLat.text,
                                                             champLon.text, champTz.text)
                            }
                        }
                    }
                }
            }

            // Tiroir : identifiants du calendrier Nextcloud. Sert à l'applet
            // « calendrier » comme au widget « date » — même fichier, même
            // saisie. Le secret n'est jamais réaffiché : place-holder avec ses
            // quatre derniers caractères, et un champ vide ne l'efface pas.
            CollapsibleSection {
                id: secCalendrier
                objectName: "secCalendrier"
                title: "Calendrier Nextcloud"
                summary: root.ncStatut !== "" ? root.ncStatut : "non configuré"
                icon: "calendar"
                expanded: root.sectionOpen("quickshell_calendrier", false)
                onToggled: expanded => {
                    root.setPanelSection("quickshell_calendrier", expanded)
                    if (expanded) {
                        if (Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_calendrier")
                        ncEtatProc.running = true
                    }
                }
                Component.onCompleted: ncEtatProc.running = true

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Le calendrier lit le calendrier Nextcloud par CalDAV. "
                              + "Le mot de passe demandé est un mot de passe "
                              + "d'application, pas celui du compte."
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: [
                            { cle: "url", libelle: "Adresse du serveur",
                              exemple: "https://cloud.exemple.org" },
                            { cle: "user", libelle: "Identifiant",
                              exemple: "prenom.nom" },
                            { cle: "app_password", libelle: "Mot de passe d'application",
                              exemple: "xxxxx-xxxxx-xxxxx-xxxxx" }
                        ]

                        Column {
                            id: champCol
                            required property var modelData
                            width: parent.width
                            spacing: 5

                            // Les deux premiers champs arrivent pré-remplis ; le mot
                            // de passe jamais, on ne fait qu'annoncer sa fin.
                            readonly property string initiale: modelData.cle === "url"
                                ? String(root.ncEtat.url || "")
                                : (modelData.cle === "user" ? String(root.ncEtat.user || "") : "")
                            readonly property bool secret: modelData.cle === "app_password"
                            readonly property string rappel: secret
                                ? (root.ncEtat.mot_de_passe_present
                                   ? "Enregistré (…" + String(root.ncEtat.mot_de_passe_fin || "") + ")"
                                   : "aucun mot de passe") + " — laisser vide pour ne pas changer"
                                : String(modelData.exemple)

                            Text {
                                text: modelData.libelle
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                            }

                            Row {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: parent.width - 130
                                    height: 32
                                    color: Theme.bg
                                    radius: Theme.globalRadius
                                    border.color: ncChamp.activeFocus ? Theme.accent : Theme.surfaceVariant
                                    border.width: 1

                                    TextInput {
                                        id: ncChamp
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.info
                                        font.pixelSize: Theme.textSm
                                        selectByMouse: true
                                        echoMode: champCol.secret ? TextInput.Password : TextInput.Normal
                                        text: champCol.initiale
                                        onAccepted: root.enregistrerNc(champCol.modelData.cle, text)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        width: parent.width - 20
                                        visible: ncChamp.text.length === 0
                                        text: champCol.rappel
                                        color: Qt.alpha(Theme.fg, 0.45)
                                        font.pixelSize: Theme.textXs
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    width: 120
                                    height: 32
                                    radius: Theme.globalRadius
                                    color: ncEnreg.containsMouse ? Theme.accentMuted : Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Enregistrer"
                                        color: Theme.bg
                                        font.pixelSize: Theme.textSm
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: ncEnreg
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.enregistrerNc(champCol.modelData.cle, ncChamp.text)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.ncStatut !== ""
                        text: root.ncStatut
                        color: root.ncStatut.startsWith("Enregistré") ? Theme.success : Theme.error
                        font.pixelSize: Theme.textXs
                    }
                }
            }


            // Homelab : l'applet et le widget interrogent l'API Proxmox. L'URL et
            // l'identifiant du jeton ne sont pas secrets et vivent dans
            // homelab.json ; le secret du jeton suit le chemin des clés d'API.
            CollapsibleSection {
                id: secHomelab
                objectName: "secHomelab"
                title: "Homelab (Proxmox)"
                summary: root.homelabUrl !== "" ? root.resumeChemin(root.homelabUrl) : "non configuré"
                icon: "cloud-check"
                expanded: root.sectionOpen("widgets_homelab", false)
                onToggled: expanded => {
                    root.setPanelSection("widgets_homelab", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_homelab")
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "L'applet et le widget lisent l'état du nœud et des machines virtuelles. "
                            + "Dans Proxmox : Datacenter → Permissions → API Tokens, rôle PVEAuditor, "
                            + "puis décocher « Privilege Separation » ou donner les droits en lecture seule."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    // ── URL ────────────────────────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: parent.width - enregUrl.width - 8
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champPveUrl
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textSm
                                clip: true
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: parent.text === ""
                                    text: "https://pve.lan:8006"
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: Theme.textSm
                                }
                                Component.onCompleted: text = root.homelabUrl
                                Connections {
                                    target: root
                                    function onHomelabUrlChanged() {
                                        if (!champPveUrl.activeFocus) champPveUrl.text = root.homelabUrl
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: enregUrl
                            width: 92
                            height: 30
                            radius: 6
                            color: survolUrl.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "Enregistrer"
                                color: Theme.accent
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                id: survolUrl
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.homelabSet("proxmox_url", champPveUrl.text.trim())
                            }
                        }
                    }

                    // ── identifiant du jeton (hermes@pam!applet) ───────────
                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: parent.width - enregId.width - 8
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champPveId
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textSm
                                clip: true
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: parent.text === ""
                                    text: "utilisateur@pam!nom-du-jeton"
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: Theme.textSm
                                }
                                Component.onCompleted: text = root.homelabTokenId
                                Connections {
                                    target: root
                                    function onHomelabTokenIdChanged() {
                                        if (!champPveId.activeFocus) champPveId.text = root.homelabTokenId
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: enregId
                            width: 92
                            height: 30
                            radius: 6
                            color: survolId.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "Enregistrer"
                                color: Theme.accent
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                id: survolId
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.homelabSet("proxmox_token_id", champPveId.text.trim())
                            }
                        }
                    }

                    // ── secret du jeton ────────────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: parent.width - enregSecret.width - 8
                            height: 30
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champPveSecret
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textSm
                                clip: true
                                echoMode: TextInput.Password
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: parent.text === ""
                                    text: root.homelabTokenPresent
                                          ? "enregistré (…" + root.homelabTokenTail + ") — collez-en un nouveau pour le remplacer"
                                          : "secret du jeton (uuid)"
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    font.pixelSize: Theme.textSm
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }

                        Rectangle {
                            id: enregSecret
                            width: 92
                            height: 30
                            radius: 6
                            color: survolSecret.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "Enregistrer"
                                color: Theme.accent
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                id: survolSecret
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.homelabSetSecret(champPveSecret.text)
                                    champPveSecret.text = ""
                                }
                            }
                        }
                    }
                }
            }

            // ── Tâches : fichiers suivis par l'applet et le widget ──────────
            // Le widget voit tous ces fichiers ; l'applet n'en montre qu'un, et
            // c'est celui marqué « affiché ». Rien ici n'est un réglage du dépôt :
            // les chemins vivent dans core/todo.json, sur la machine.
            CollapsibleSection {
                id: secTaches
                objectName: "secTaches"
                title: "Tâches — fichiers suivis"
                summary: root.todoFichiers.length + " fichiers"
                icon: "check"
                expanded: root.sectionOpen("taches_fichiers", false)
                onToggled: expanded => {
                    root.setPanelSection("taches_fichiers", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("taches_fichiers")
                }

                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Chaque ligne `- [ ] **Titre**` d'un fichier Markdown devient "
                              + "une case à cocher. Cocher dans le panneau commande l'étape "
                              + "à l'agent, qui réécrit la ligne une fois faite."
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.todoFichiers.length === 0
                        text: "Aucun fichier suivi."
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.textXs
                    }

                    Repeater {
                        model: root.todoFichiers

                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8

                            Text {
                                width: Math.round(parent.width * 0.28)
                                text: String(modelData.nom || "")
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width - Math.round(parent.width * 0.28) - 46
                                text: String(modelData.chemin || "")
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Math.max(9, Theme.textXs - 1)
                                elide: Text.ElideMiddle
                            }

                            // Une croix dans un rond, comme les autres retraits du
                            // panneau : un mot entier ne tenait pas dans la ligne et
                            // se retrouvait coupé.
                            Rectangle {
                                width: 22
                                height: 22
                                radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: croixRetirer.containsMouse ? Theme.error
                                                                  : Qt.alpha(Theme.fg, 0.08)
                                border.width: 1
                                border.color: Qt.alpha(Theme.error, 0.45)

                                Icon {
                                    anchors.centerIn: parent
                                    glyph: "close"
                                    size: Math.round(Theme.iconSm * 0.78)
                                    color: croixRetirer.containsMouse ? Theme.bg : Theme.error
                                    opacityLevel: 1
                                }

                                MouseArea {
                                    id: croixRetirer
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd(["todo_del", String(modelData.nom || "")])
                                }
                            }
                        }
                    }

                    // Ajouter un fichier : le nom est libre, le chemin est étendu
                    // par l'applet (`~` reste `~`, c'est elle qui l'interprète).
                    // Bouton "Choisir" graphique pour sélectionner un fichier .md.
                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: 130
                            height: 30
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.06)
                            border.width: 1
                            border.color: Qt.alpha(Theme.fg, 0.2)

                            TextInput {
                                id: nouveauTodoNom
                                anchors.fill: parent
                                anchors.margins: 6
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                selectByMouse: true
                                clip: true
                                onTextEdited: root.todoErreur = ""
                                onAccepted: nouveauTodoChemin.forceActiveFocus()
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: nouveauTodoNom.text === ""
                                    text: "nom (ex. perso)"
                                    color: Qt.alpha(Theme.fg, 0.3)
                                    font.pixelSize: Theme.textXs
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width - 130 - 70 - 90 - 24
                            height: 30
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.06)
                            border.width: 1
                            border.color: root.todoErreur !== ""
                                          ? Qt.alpha(Theme.error, 0.65) : Qt.alpha(Theme.fg, 0.2)

                            TextInput {
                                id: nouveauTodoChemin
                                anchors.fill: parent
                                anchors.margins: 6
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                selectByMouse: true
                                clip: true
                                onTextEdited: root.todoErreur = ""
                                onAccepted: root.ajouterTodo()
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: nouveauTodoChemin.text === ""
                                    text: "~/chemin/vers/todo.md"
                                    color: Qt.alpha(Theme.fg, 0.3)
                                    font.pixelSize: Theme.textXs
                                }
                            }
                        }

                        // Bouton "Choisir" graphique (comme pour les fonds d'écran et captures)
                        Rectangle {
                            width: 70
                            height: 30
                            radius: 6
                            color: todoPickMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    glyph: "folder"
                                    size: Math.round(Theme.iconSm * 0.78)
                                    color: todoPickMa.containsMouse ? Theme.bg : Theme.accent
                                    opacityLevel: 1
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Choisir"
                                    color: todoPickMa.containsMouse ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                }
                            }

                            MouseArea {
                                id: todoPickMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.ouvrirSelecteurFichier("todo_md", "Choisir un fichier Markdown", nouveauTodoChemin.text, ["md", "markdown"])
                            }
                        }

                        Rectangle {
                            width: 90
                            height: 30
                            radius: 6
                            color: survolTodoAjout.containsMouse
                                   ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "+ Ajouter"
                                color: Theme.accent
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                id: survolTodoAjout
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.ajouterTodo()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.todoErreur !== ""
                        text: root.todoErreur
                        color: Theme.error
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                        wrapMode: Text.WordWrap
                    }

                    // Quel fichier l'applet montre : le widget, lui, les voit tous.
                    Row {
                        width: parent.width
                        spacing: 6
                        visible: root.todoFichiers.length > 0

                        Text {
                            width: 150
                            text: "Affiché par l'applet"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: Theme.textXs
                        }

                        Repeater {
                            model: root.todoFichiers

                            Rectangle {
                                required property var modelData
                                readonly property bool choisi: root.todoFocus === String(modelData.nom)
                                width: Math.max(56, labelChoisi.implicitWidth + 18)
                                height: 24
                                radius: 6
                                color: choisi ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                                border.width: 1
                                border.color: choisi ? Qt.alpha(Theme.accent, 0.5)
                                                     : Qt.alpha(Theme.fg, 0.18)

                                Text {
                                    id: labelChoisi
                                    anchors.centerIn: parent
                                    text: String(modelData.nom || "")
                                    color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runConfigCmd(["todo_focus", String(modelData.nom || "")])
                                        root.todoFocus = String(modelData.nom || "")
                                    }
                                }
                            }
                        }
                    }

                    // ── Surveillance des tâches par Hermes ──────────────────
                    Row {
                        width: parent.width
                        spacing: 12

                        Column {
                            width: parent.width - 50
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "Surveillance des tâches par Hermes"
                                color: root.todoSurveillance ? Theme.accent : Theme.fg
                                font.pixelSize: Theme.textSm
                                font.bold: true
                            }

                            Text {
                                width: parent.width
                                text: "Lorsque cette option est active, cocher une case confie l'exécution de la tâche à Hermes via la file d'attente. Désactivé : simple gestionnaire de cases Markdown locales."
                                color: Qt.alpha(Theme.fg, 0.5)
                                font.pixelSize: Theme.textXs
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            width: 38
                            height: 20
                            radius: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                y: 2
                                x: root.todoSurveillance ? parent.width - width - 2 : 2
                                color: root.todoSurveillance ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                Behavior on x { NumberAnimation { duration: 130 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["todo_surveillance"])
                            }
                        }
                    }
                }
            }

        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 2: SYSTÈME & ÉCRANS (adaptatif : machine fixe ou portable)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabSystemeCol
            visible: root.currentTab === 3
            width: mainFlickable.width
            spacing: 12

            // Tiroir : moniteurs détectés, moniteur principal, résolution et
            // fréquence.
            CollapsibleSection {
                id: secEcrans
                objectName: "secEcrans"
                title: "Moniteurs & Résolution"
                summary: root.selectedMonitorName + " · " + root.monitorsList.length + " écran(s)"
                icon: "monitor"
                expanded: root.sectionOpen("ecrans_moniteurs", true)
                onToggled: expanded => {
                    root.setPanelSection("ecrans_moniteurs", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ecrans_moniteurs")
                }

            Text {
                width: parent.width
                text: "Moniteurs détectés (" + root.hostName + ") — cliquer pour sélectionner un écran"
                color: Theme.accent
                font.pixelSize: Theme.textLg
                font.bold: true
                wrapMode: Text.WordWrap
            }

            // Liste des moniteurs détectés (HDMI-A-1 sur une tour, eDP-1 sur un portable)
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
            }

            // Tiroir : mise à l'échelle, profils multi-écrans et mode tablette.
            CollapsibleSection {
                id: secProfils
                objectName: "secProfils"
                title: "Profils & Rotation"
                summary: root.isLaptop ? "portable" : "fixe"
                icon: "tablet"
                expanded: root.sectionOpen("ecrans_profils", false)
                onToggled: expanded => {
                    root.setPanelSection("ecrans_profils", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ecrans_profils")
                }

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

            // Section réservée au portable : profils multi-écrans et rotation tablette
            Column {
                visible: root.isLaptop
                width: parent.width
                spacing: 10

                Text {
                    text: "Profils Multi-Écrans & Mode Tablette (portable uniquement)"
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
            }

            // Tiroir : Alimentation, Veille, Fuseau horaire et Batterie
            CollapsibleSection {
                id: secHorloge
                objectName: "secHorloge"
                title: "Alimentation, Veille & Horloge"
                summary: "Veille : " + root.idleSuspendLabel + " · " + (root.ntpSynced ? "NTP synchronisé" : "NTP manuel")
                icon: "power"
                expanded: root.sectionOpen("systeme_horloge", false)
                onToggled: expanded => {
                    root.setPanelSection("systeme_horloge", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("systeme_horloge")
                }

            Column {
                width: parent.width
                spacing: 12

                // ── Mise en veille du système (inactivité) ────────────────────
                Column {
                    id: idleTimeoutRow
                    objectName: "idleTimeoutRow"
                    width: parent.width
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Mise en veille automatique :"
                            color: Theme.accent
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "inactivité avant suspension (hypridle)"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "15 min", value: 900 },
                                { label: "30 min", value: 1800 },
                                { label: "1 heure (défaut)", value: 3600 },
                                { label: "2 heures", value: 7200 },
                                { label: "3 heures", value: 10800 },
                                { label: "Jamais", value: 0 }
                            ]

                            Rectangle {
                                required property var modelData
                                readonly property bool actif: root.idleSuspendTimeout === modelData.value
                                width: idlePillText.implicitWidth + 18
                                height: 28
                                radius: Theme.globalRadius
                                color: actif ? Theme.accent : Theme.surfaceVariant
                                border.width: 1
                                border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                                Text {
                                    id: idlePillText
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: actif ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: actif
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.idleSuspendTimeout = modelData.value
                                        root.runConfigCmd(["idle_timeout", String(modelData.value)])
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Limite batterie 80% (portable) ─────────────────────────────
                Rectangle {
                    visible: root.isLaptop
                    width: parent.width
                    height: 44
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

                // ── Fuseau & NTP ──────────────────────────────────────────────
                Rectangle {
                    id: timezoneRow
                    objectName: "timezoneRow"
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

                // ── WiFi ──────────────────────────────────────────────────────
                Rectangle {
                    width: parent.width
                    height: 44
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
            }
            }

            // Mode nuit : le filtre chaud de l'écran. Une plage horaire vide
            // signifie « à la main » — c'est l'icône de l'applet luminosité qui
            // décide ; dès qu'une plage existe, le service s'en charge seul.
            CollapsibleSection {
                id: secNuit
                objectName: "secNuit"
                title: "Mode nuit"
                summary: root.nuitAllumee ? ("allumé · " + root.nuitTemp + " K") : "éteint"
                icon: "weather-night"
                expanded: root.sectionOpen("systeme_nuit", true)
                onToggled: expanded => {
                    root.setPanelSection("systeme_nuit", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("systeme_nuit")
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "Température appliquée par hyprsunset. Plus la valeur est basse, "
                            + "plus l'écran tire vers l'orange."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: [2700, 3400, 4000, 5000]

                            Rectangle {
                                required property var modelData
                                readonly property bool actif: root.nuitTemp === modelData
                                width: 74
                                height: 28
                                radius: Theme.globalRadius
                                color: actif ? Qt.alpha(Theme.accent, 0.28) : Theme.surfaceVariant
                                border.color: actif ? Theme.accent : Theme.accentMuted
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + " K"
                                    color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                                    font.pixelSize: Theme.textXs
                                    font.bold: actif
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.reglerNuit(["temperature", String(modelData)])
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Plage horaire automatique — laisser vide pour commander à la main."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: 8

                        Rectangle {
                            width: 76
                            height: 28
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champNuitDe
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textXs
                                clip: true
                                Component.onCompleted: text = root.nuitDe
                                Connections {
                                    target: root
                                    function onNuitDeChanged() {
                                        if (!champNuitDe.activeFocus) champNuitDe.text = root.nuitDe
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "→"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: Theme.textXs
                        }

                        Rectangle {
                            width: 76
                            height: 28
                            radius: 6
                            color: Theme.surfaceVariant
                            border.color: Theme.accentMuted
                            border.width: 1

                            TextInput {
                                id: champNuitA
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fg
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.pixelSize: Theme.textXs
                                clip: true
                                Component.onCompleted: text = root.nuitA
                                Connections {
                                    target: root
                                    function onNuitAChanged() {
                                        if (!champNuitA.activeFocus) champNuitA.text = root.nuitA
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 92
                            height: 28
                            radius: Theme.globalRadius
                            color: survolNuit.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "Enregistrer"
                                color: Theme.accent
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            MouseArea {
                                id: survolNuit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.reglerNuit(["plage", champNuitDe.text.trim(), champNuitA.text.trim()])
                            }
                        }

                        Rectangle {
                            width: 74
                            height: 28
                            radius: Theme.globalRadius
                            color: survolSansPlage.containsMouse ? Qt.alpha(Theme.error, 0.14) : "transparent"
                            border.color: Qt.alpha(Theme.fg, 0.18)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Aucune"
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.pixelSize: Theme.textXs
                            }

                            MouseArea {
                                id: survolSansPlage
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    champNuitDe.text = ""
                                    champNuitA.text = ""
                                    root.reglerNuit(["plage", "", ""])
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: (root.nuitAllumee ? "Mode nuit allumé" : "Mode nuit éteint")
                            + (root.nuitDe !== "" ? " · plage " + root.nuitDe + " → " + root.nuitA : " · manuel")
                        color: root.nuitAllumee ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }
                }
            }

        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 3: CONTRÔLES, CLAVIER & RACCOURCIS (binds.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabControlesCol
            visible: root.currentTab === 4
            width: mainFlickable.width
            spacing: 10

            // Top bar: Current Keyboard Layout + Button to reopen First-Run Keyboard Selector
            // Tiroir : disposition active et changement de clavier.
            CollapsibleSection {
                id: secClavier
                objectName: "secClavier"
                title: "Disposition du clavier"
                summary: root.kbLayout
                icon: "keyboard"
                expanded: root.sectionOpen("clavier_disposition", true)
                onToggled: expanded => {
                    root.setPanelSection("clavier_disposition", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("clavier_disposition")
                }

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
            }

            // Tiroir : raccourcis Hyprland — liste, ajout, suppression.
            CollapsibleSection {
                id: secBinds
                objectName: "secBinds"
                title: "Raccourcis Hyprland"
                summary: root.bindsList.length + " raccourcis"
                icon: "cog"
                expanded: root.sectionOpen("clavier_binds", false)
                onToggled: expanded => {
                    root.setPanelSection("clavier_binds", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("clavier_binds")
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
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 4: VARIABLES DYNAMIQUES & APPLICATIONS (app_vars.json <-> programs.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        Column {
            id: tabAppsCol
            visible: root.currentTab === 5
            width: mainFlickable.width
            spacing: 12

            // Programs par défaut des raccourcis (app_vars.json <-> programs.lua)
            CollapsibleSection {
                id: secApps
                objectName: "secApps"
                title: "Applications par défaut"
                summary: root.appVarsModel.length + " programmes"
                icon: "rocket"
                expanded: root.sectionOpen("apps_programs", true)
                onToggled: expanded => {
                    root.setPanelSection("apps_programs", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("apps_programs")
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

            // Notifications : un seul réglage global ici, la bascule « ne pas
            // déranger ». Elle coupe les toasts ; l'historique continue de se
            // remplir, et la cloche de la barre se barre.
            CollapsibleSection {
                id: secNotifs
                objectName: "secNotifs"
                title: "Notifications & Actions au clic"
                summary: root.dndActif ? "ne pas déranger" : "alertes actives"
                icon: "bell"
                expanded: root.sectionOpen("quickshell_notifications", false)
                onToggled: expanded => {
                    root.setPanelSection("quickshell_notifications", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_notifications")
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "« Ne pas déranger » n'affiche plus aucun toast : les notifications "
                            + "arrivent quand même dans le centre et dans l'historique."
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }

                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Ne pas déranger"
                            color: root.dndActif ? Theme.accent : Theme.fg
                            font.pixelSize: Theme.textSm
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 22
                            radius: 11
                            color: root.dndActif ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                y: 2
                                x: root.dndActif ? parent.width - width - 2 : 2
                                color: root.dndActif ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                Behavior on x { NumberAnimation { duration: 130 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.reglerDnd(!root.dndActif)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.dndActif ? "Actif : aucun toast ne s'affiche." : "Inactif : les toasts s'affichent normalement."
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }
                }

                // Au clic : quoi faire quand on clique une notification.
                Text {
                    width: parent.width
                    text: "Au clic sur une notification"
                    color: Theme.accent
                    font.pixelSize: Theme.textSm
                    font.bold: true
                }

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

            // Cible du clic sur le titre d'une notification (core/notif_targets.json).
            // Aucun programme n'est écrit ici : les alias renvoient au tiroir
            // « Programmes par défaut » ci-dessus. Le résolveur relit le fichier à
            // chaque notification, donc une modification est effective tout de suite.

            // Autostart géré par le panneau (autostart.json -> autostart_managed.lua)
            CollapsibleSection {
                id: secAutostart
                objectName: "secAutostart"
                title: "Programmes lancés au démarrage"
                summary: root.autostartModel.length + " programmes"
                icon: "power"
                expanded: root.sectionOpen("apps_autostart", false)
                onToggled: expanded => {
                    root.setPanelSection("apps_autostart", expanded)
                    if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("apps_autostart")
                }

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

            // Hors tiroir : c'est une action, pas un réglage. Elle installe ce que
            // dependencies.txt réclame et qui manque sur cette machine.
            Item { width: 1; height: 12 }

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    id: depsBtn
                    width: depsBtnText.implicitWidth + 26
                    height: 28
                    radius: Theme.globalRadius
                    color: depsBtnMa.containsMouse ? Theme.accentMuted : Theme.accent

                    Text {
                        id: depsBtnText
                        anchors.centerIn: parent
                        text: "Installer les paquets manquants"
                        color: Theme.bg
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                    }

                    MouseArea {
                        id: depsBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.installerDependances()
                    }
                }

                // Rien à côté du bouton quand tout va bien : une coche, et c'est
                // tout. Un échec, lui, se dit — c'est la seule information utile.
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.depsEtat === "à jour"
                    glyph: "check"
                    size: Theme.iconSm
                    color: Theme.success
                    opacityLevel: 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.depsEtat !== "" && root.depsEtat !== "à jour"
                    width: parent.width - depsBtn.width - Theme.iconSm - 20
                    text: root.depsEtat
                    color: Theme.error
                    font.pixelSize: Theme.textXs
                    elide: Text.ElideRight
                }
            }
        }   // end Column tabAppsCol

            // Onglet Connexion : le greeter est un composant séparé (grille de
            // miniatures + backend), posé dans un tiroir comme le reste.
            Column {
                id: tabConnexionCol
                visible: root.currentTab === 6
                width: mainFlickable.width
                spacing: 11

                CollapsibleSection {
                    id: secGreeter
                    objectName: "secGreeter"
                    title: "Thème de l'écran de connexion (SDDM)"
                    summary: root.greeterSelected !== "" ? root.greeterSelected : "thème par défaut"
                    icon: "lock"
                    expanded: root.sectionOpen("greeter_theme", true)
                    onToggled: expanded => {
                        root.setPanelSection("greeter_theme", expanded)
                        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("greeter_theme")
                    }

                    Loader {
                        id: greeterTabLoader
                        width: parent.width
                        active: root.currentTab === 6
                        source: "GreeterTab.qml"
                        onLoaded: item.width = parent.width
                    }
                }
            }
    }   // end Flickable mainFlickable
    }   // end Item tabContentArea

    // Feuille modale du panneau : dernier enfant, donc au-dessus de tout.
    //
    // Chargée par **URL** et non par nom de type : « SelecteurDossier is not a
    // type » — le moteur ne l'enregistre pas dans l'import implicite du dossier,
    // alors qu'un Loader par chemin n'a pas besoin de cet enregistrement.
    Loader {
        id: selecteurLoader
        anchors.fill: parent
        z: 1000
        source: "SelecteurDossier.qml"
        onLoaded: {
            item.accepte.connect(chemin => {
                root.validerSelecteur(chemin)
                root.restaurerFocus()
            })
            item.annule.connect(() => {
                root.selecteurCible = ""
                root.restaurerFocus()
            })
        }
    }

    function ouvrirSelecteur(cible, titre, chemin) {
        root.selecteurCible = String(cible)
        if (!selecteurLoader.item)
            return
        selecteurLoader.item.titre = String(titre)
        selecteurLoader.item.chemin = root.cheminAbsolu(chemin)
        selecteurLoader.item.ouvert = true
    }

    function validerSelecteur(chemin) {
        if (root.selecteurCible === "")
            return
        root.runConfigCmd(["style", root.selecteurCible, String(chemin) + "/"])
        root.selecteurCible = ""
    }

    // Feuille modale du sélecteur de fichier (ex: Markdown pour les tâches)
    Loader {
        id: selecteurFichierLoader
        anchors.fill: parent
        z: 1000
        source: "SelecteurFichier.qml"
        onLoaded: {
            item.accepte.connect(chemin => {
                root.validerSelecteurFichier(chemin)
                root.restaurerFocus()
            })
            item.annule.connect(() => {
                root.selecteurFichierCible = ""
                root.restaurerFocus()
            })
        }
    }

    function ouvrirSelecteurFichier(cible, titre, chemin, extensions, icone) {
        root.selecteurFichierCible = String(cible)
        if (!selecteurFichierLoader.item)
            return
        selecteurFichierLoader.item.titre = String(titre)
        if (extensions && extensions.length > 0)
            selecteurFichierLoader.item.extensions = extensions
        selecteurFichierLoader.item.filtrerExtensions = true
        selecteurFichierLoader.item.icone = icone ? String(icone) : "file-document"
        let chem = String(chemin || "")
        if (chem === "") chem = "~"
        selecteurFichierLoader.item.chemin = root.cheminAbsolu(chem)
        selecteurFichierLoader.item.fichierSelectionne = ""
        selecteurFichierLoader.item.ouvert = true
    }

    function validerSelecteurFichier(chemin) {
        if (root.selecteurFichierCible === "todo_md") {
            nouveauTodoChemin.text = root.abregerHome(chemin)
            if (nouveauTodoNom.text.trim() === "") {
                const base = String(chemin).split("/").pop().replace(/\.md$/i, "").replace(/\.markdown$/i, "")
                if (base)
                    nouveauTodoNom.text = base
            }
        } else if (root.selecteurFichierCible === "install_theme_colors") {
            root.installerThemeCouleur(chemin)
        }
        root.selecteurFichierCible = ""
    }
}
