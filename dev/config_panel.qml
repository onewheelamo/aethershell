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
// Bureau (1 500 lignes dans OngletApparence.qml).
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
    readonly property var targetMap: ({})

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

    // Hauteur du contenu de l'onglet affiché : l'item du Loader peut ne pas
    // encore exister (chargement différé), d'où le 0 plutôt qu'un undefined.
    function hauteurOnglet(n) {
        let h = 0
        if (n === 0) h = ongletApparence.item ? ongletApparence.item.implicitHeight : 0
        else if (n === 1) h = ongletBarres.item ? ongletBarres.item.implicitHeight : 0
        else if (n === 2) h = ongletBureau.item ? ongletBureau.item.implicitHeight : 0
        else if (n === 3) h = ongletEcrans.item ? ongletEcrans.item.implicitHeight : 0
        else if (n === 4) h = ongletClavier.item ? ongletClavier.item.implicitHeight : 0
        else if (n === 5) h = ongletApps.item ? ongletApps.item.implicitHeight : 0
        else if (n === 6) h = ongletConnexion.item ? ongletConnexion.item.implicitHeight : 0
        else if (n === 7) h = ongletDonnees.item ? ongletDonnees.item.implicitHeight : 0
        return h
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
    readonly property var tiroirs: ({})

    // Les sections d'un onglet déporté n'existent que quand son Loader est actif :
    // les deux tables ci-dessus ne peuvent plus les nommer, et un id absent lève
    // « ReferenceError: secTheme is not defined ». On les demande donc à l'onglet
    // chargé, qui expose `sections` (nom de tiroir → objet) et `cibles` (nom
    // d'ancre → objet). La liste grandit au fil des extractions.
    readonly property var ongletsDeportes: [ ongletApparence, ongletBarres, ongletBureau, ongletEcrans, ongletClavier, ongletApps, ongletConnexion, ongletDonnees ]

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
    // Paramètres en attente pour les feuilles modales : le premier clic sur
    // « Choisir » crée le composant, et c'est `onLoaded` qui les applique.
    property var selecteurParams: ({})
    property var selecteurFichierParams: ({})

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
        // Les cibles de notification viennent de `state` (une seule source) :
        // auparavant un FileView du panneau les relisait de son cote.
        if (data.notif_targets && typeof data.notif_targets === "object") {
            const nt = data.notif_targets
            root.notifTargets = {
                "apps": (nt.apps && typeof nt.apps === "object") ? nt.apps : ({}),
                "types": (nt.types && typeof nt.types === "object") ? nt.types : ({}),
                "url": (typeof nt.url === "string") ? nt.url : "Browser"
            }
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



    Connections {
        target: Theme
        function onConfigPanelVisibleChanged() {
            if (Theme.configPanelVisible) {
                root.refreshConfigState()
            }
        }
    }

    // ── Les huit onglets : un seul endroit décide lequel vit ─────────────────
    // `source:` + `onLoaded` ne suffisait pas : le corps est créé avant que
    // `onLoaded` ne pose `root`, et ses liaisons lisent root dès l'évaluation
    // (« Cannot read property 'nuitA' of undefined », « value is undefined and
    // could not be converted to an object »). `setSource` passe les propriétés
    // **avant** la création. Quitter un onglet le libère : la position de
    // défilement est perdue, la mémoire revient.
    function majOnglets() {
        const defs = [
            [0, ongletApparence, "OngletApparence.qml", {}],
            [1, ongletBarres, "OngletBarres.qml", { disquesListeProc: disquesListeProc }],
            [2, ongletBureau, "OngletBureau.qml", {}],
            [3, ongletEcrans, "OngletEcrans.qml", {}],
            [4, ongletClavier, "OngletClavier.qml", {}],
            [5, ongletApps, "OngletApps.qml", {}],
            [6, ongletConnexion, "OngletConnexion.qml", {}],
            [7, ongletDonnees, "OngletDonnees.qml", { ncEtatProc: ncEtatProc }]
        ]
        for (let i = 0; i < defs.length; ++i) {
            const index = defs[i][0]
            const chargeur = defs[i][1]
            if (root.currentTab !== index) {
                if (chargeur.status !== Loader.Null)
                    chargeur.source = ""
                continue
            }
            if (chargeur.status === Loader.Null)
                chargeur.setSource(defs[i][2],
                                   Object.assign({ root: root, mainFlickable: mainFlickable }, defs[i][3]))
        }
    }

    onCurrentTabChanged: root.majOnglets()

    Component.onCompleted: {
        refreshConfigState()
        appletsRafraichir()
        // L'onglet mémorisé se charge comme les autres, par setSource.
        root.majOnglets()
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
            contentHeight: root.hauteurOnglet(root.currentTab)

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
            // ONGLET 0 : APPARENCE — fonds d'écran, thèmes, fenêtres Hyprland, barre.
            // Le corps (1 500 lignes) vit dans OngletApparence.qml, instancié seulement
            // quand l'onglet s'ouvre ; ici il ne reste que le Loader et son câblage.
            // Le tiroir « Barre & surfaces » est dans cet onglet ; les barres annexes,
            // les applets et le visualiseur sont dans « Barres & Applets ».
            // ═══════════════════════════════════════════════════════════════════════════
        Loader {
            id: ongletApparence
            width: mainFlickable.width
        }
        // ═════════════════════════════════════════════════════════════════════
        // TAB 1: GESTION QUICKSHELL — barres annexes, applets et visualiseur.
        // La barre elle-même (îlots, panneau, popups) est dans l'onglet « Bureau ».
        // ═════════════════════════════════════════════════════════════════════
        // ── Onglet « Barres & Applets » ──────────────────────────────────────────────
        // Corps dans OngletBarres.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletBarres
            width: mainFlickable.width
        }


        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 1: WIDGETS DU BUREAU (sur les workspaces, réglages par widget)
        // ═══════════════════════════════════════════════════════════════════════════
        // ── Onglet « Bureau & Lanceur » ──────────────────────────────────────────────
        // Corps dans OngletBureau.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletBureau
            width: mainFlickable.width
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB HOMELAB : ce qui parle à l'extérieur — Nextcloud d'un côté, Proxmox de
        // l'autre. Sortis de l'onglet Quickshell, où ils n'avaient rien à faire : la
        // barre et les applets se règlent là-bas, pas les accès aux serveurs.
        // ═══════════════════════════════════════════════════════════════════════════
        // ── Onglet « Données & Comptes » ──────────────────────────────────────────────
        // Corps dans OngletDonnees.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletDonnees
            width: mainFlickable.width
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 2: SYSTÈME & ÉCRANS (adaptatif : machine fixe ou portable)
        // ═══════════════════════════════════════════════════════════════════════════
        // ── Onglet « Écrans & Système » ──────────────────────────────────────────────
        // Corps dans OngletEcrans.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletEcrans
            width: mainFlickable.width
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 3: CONTRÔLES, CLAVIER & RACCOURCIS (binds.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        // ── Onglet « Clavier & Binds » ──────────────────────────────────────────────
        // Corps dans OngletClavier.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletClavier
            width: mainFlickable.width
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // TAB 4: VARIABLES DYNAMIQUES & APPLICATIONS (app_vars.json <-> programs.lua)
        // ═══════════════════════════════════════════════════════════════════════════
        // ── Onglet « Apps & Alertes » ──────────────────────────────────────────────
        // Corps dans OngletApps.qml, instancie a l'ouverture de l'onglet.
        Loader {
            id: ongletApps
            width: mainFlickable.width
        }

            // Onglet Connexion : le greeter est un composant séparé (grille de
            // miniatures + backend), posé dans un tiroir comme le reste.
            // ── Onglet « Connexion » ──────────────────────────────────────────────
            // Corps dans OngletConnexion.qml, instancie a l'ouverture de l'onglet.
            Loader {
                id: ongletConnexion
                width: mainFlickable.width
            }
    }   // end Flickable mainFlickable
    }   // end Item tabContentArea

    // Feuille modale du panneau : dernier enfant, donc au-dessus de tout.
    //
    // Chargée par **URL** et non par nom de type : « SelecteurDossier is not a
    // type » — le moteur ne l'enregistre pas dans l'import implicite du dossier,
    // alors qu'un Loader par chemin n'a pas besoin de cet enregistrement.
    //
    // ── Feuilles modales, instanciées à la demande ───────────────────────────
    // Deux feuilles de ~850 lignes qui ne servent qu'après un clic sur « Choisir » :
    // les garder montées avec le panneau faisait payer leur analyse et leur
    // instanciation à chaque ouverture. `active` les crée au premier besoin et les
    // relâche une fois refermées (le délai laisse la fermeture se faire avant de
    // détruire l'item).
    property var selecteurALiberer: null
    Timer {
        id: liberationSelecteur
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.selecteurALiberer) return
            root.selecteurALiberer.active = false
            root.selecteurALiberer = null
        }
    }
    function libererSelecteur(loader) {
        root.selecteurALiberer = loader
        root.restaurerFocus()
        liberationSelecteur.restart()
    }

    Loader {
        id: selecteurLoader
        anchors.fill: parent
        z: 1000
        active: false
        source: "SelecteurDossier.qml"
        onLoaded: {
            item.accepte.connect(function (chemin) {
                root.validerSelecteur(chemin)
                root.libererSelecteur(selecteurLoader)
            })
            item.annule.connect(function () {
                root.selecteurCible = ""
                root.libererSelecteur(selecteurLoader)
            })
            // Premier clic : l'item n'existait pas encore quand `ouvrirSelecteur` a
            // posé la cible, c'est ici qu'on lui passe ses paramètres.
            root.appliquerSelecteur()
        }
    }

    function ouvrirSelecteur(cible, titre, chemin) {
        root.selecteurCible = String(cible)
        root.selecteurParams = ({ titre: String(titre), chemin: root.cheminAbsolu(chemin) })
        selecteurLoader.active = true
        root.appliquerSelecteur()
    }

    function appliquerSelecteur() {
        const it = selecteurLoader.item
        if (!it || root.selecteurCible === "")
            return
        it.titre = String(root.selecteurParams.titre || "")
        it.chemin = String(root.selecteurParams.chemin || "")
        it.ouvert = true
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
        active: false
        source: "SelecteurFichier.qml"
        onLoaded: {
            item.accepte.connect(function (chemin) {
                root.validerSelecteurFichier(chemin)
                root.libererSelecteur(selecteurFichierLoader)
            })
            item.annule.connect(function () {
                root.selecteurFichierCible = ""
                root.libererSelecteur(selecteurFichierLoader)
            })
            root.appliquerSelecteurFichier()
        }
    }

    function ouvrirSelecteurFichier(cible, titre, chemin, extensions, icone) {
        root.selecteurFichierCible = String(cible)
        let chem = String(chemin || "")
        if (chem === "") chem = "~"
        root.selecteurFichierParams = ({
            titre: String(titre),
            chemin: root.cheminAbsolu(chem),
            extensions: extensions || [],
            icone: icone ? String(icone) : "file-document"
        })
        selecteurFichierLoader.active = true
        root.appliquerSelecteurFichier()
    }

    function appliquerSelecteurFichier() {
        const it = selecteurFichierLoader.item
        if (!it || root.selecteurFichierCible === "")
            return
        const p = root.selecteurFichierParams
        it.titre = String(p.titre || "")
        if (p.extensions && p.extensions.length > 0)
            it.extensions = p.extensions
        it.filtrerExtensions = true
        it.icone = String(p.icone || "file-document")
        it.chemin = String(p.chemin || "")
        it.fichierSelectionne = ""
        it.ouvert = true
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
