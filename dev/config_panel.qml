import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ════════════════════════════════════════════════════════════════════════════
// SYSTEM CONFIGURATION PANEL (config_panel.qml)
// ════════════════════════════════════════════════════════════════════════════
// Choix du contrôle numérique :
//   • plage > 12 unités → Slider (curseur)
//   • plage ≤ 12 unités → Stepper (compteur [−] valeur [+])
//   • exceptions : position x/y des widgets et opacité « Fond » des cartes.
//
// Règle de gel : une option nouvelle naît dans son propre composant Onglet*.qml,
// chargé par URL depuis ici (`Loader { source: "Onglet….qml" }`).
// ════════════════════════════════════════════════════════════════════════════
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
    width: 860
    height: parent ? parent.height : 600
    // Fond transparent : le rendu verre + teinte est porté par SurfaceFloutee.
    color: "transparent"
    radius: Theme.globalRadius
    border.color: root.dragWidgetType !== "" ? Qt.alpha(Theme.accent, 0.25) : Theme.accent
    border.width: 1

    property string dragWidgetType: ""
    property real dragPointerX: 0
    property real dragPointerY: 0
    property string dragCapsuleId: ""
    property string dragCapsuleLabel: ""

    function widgetSourceFor(t) {
        const s = String(t || "")
        if (!s) return ""
        const partages = ["deepseek", "ollama", "antigravity"]
        return "widgets/" + (partages.indexOf(s) >= 0 ? "llm" : s) + ".qml"
    }

    function widgetOptionsFor(t) {
        const s = String(t || "")
        const partages = ["deepseek", "ollama", "antigravity"]
        if (partages.indexOf(s) >= 0) return ({ provider: s })
        return ({})
    }

    function dropWidgetAt(wtype, dropX, dropY) {
        const sx = Math.max(8, Math.round(dropX))
        const sy = Math.max(Theme.barHeight + 8, Math.round(dropY))
        const liste = root.widgetsList || []
        for (let i = 0; i < liste.length; ++i) {
            if (String(liste[i].type) === String(wtype)) {
                if (liste[i].enabled === false) {
                    root.runConfigCmd(["widget_toggle", String(liste[i].id)])
                }
                root.runConfigCmd(["widget_move", String(liste[i].id), String(sx), String(sy)])
                return
            }
        }
        root.runConfigCmd(["widget_add", String(wtype), "1", String(sx), String(sy)])
    }

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

    // Surface floutée unifiée (SurfaceFloutee → Theme.surfaceBg)
    SurfaceFloutee {
        id: fondFlou
        anchors.fill: parent
        rayon: root.radius
        teinte: Theme.surfaceBg
        bordureLargeur: 0
        actif: Theme.configPanelVisible
    }

    // Thème du greeter sélectionné dans l'onglet Connexion. Porté ici parce que
    // le composant de l'onglet est déchargé dès qu'on le quitte.
    property string greeterSelected: ""
    property var iconesEtat: ({ ok: false, actif: "", themes: [] })
    property string iconesMessage: ""

    Process {
        id: iconesProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (d && d.ok) {
                        root.iconesEtat = d
                        root.iconesMessage = d.message ? String(d.message) : ""
                    } else if (d && d.error) {
                        root.iconesMessage = String(d.error)
                    }
                } catch (e) {}
            }
        }
    }

    function rafraichirIcones() {
        iconesProc.command = [Quickshell.shellPath("core/as-core"), "icones", "list"]
        iconesProc.running = false
        iconesProc.running = true
    }

    function appliquerThemeIcones(id) {
        root.iconesMessage = "Application de « " + id + " »…"
        iconesProc.command = [Quickshell.shellPath("core/as-core"), "icones", "apply", String(id)]
        iconesProc.running = false
        iconesProc.running = true
    }

    function installerPackIcones(chemin) {
        root.iconesMessage = "Installation de l'archive…"
        iconesProc.command = [Quickshell.shellPath("core/as-core"), "icones", "install", String(chemin)]
        iconesProc.running = false
        iconesProc.running = true
    }

    function supprimerPackIcones(id) {
        iconesProc.command = [Quickshell.shellPath("core/as-core"), "icones", "remove", String(id)]
        iconesProc.running = false
        iconesProc.running = true
    }

    // Recherche : requête courante, alimentée par le champ de la §3.
    property string searchQuery: ""
    // Résultats calculés (label, tab, section, target) — voir searchIndex.
    property var searchResults: []

    // Index d'ancres : une entrée par réglage notable. Le champ redirige vers
    // l'onglet et la section, puis fait défiler jusqu'à la ligne ciblée.
    readonly property var tabLabels: ["Apparence", "Barre & Îlot", "Bureau", "Système", "Services"]

    readonly property var searchIndex: [
        { label: "Thème de l'écran de connexion", words: "connexion greeter sddm ecran login theme de connexion",
          tab: 0, section: "greeter_theme", target: "secGreeter" },
        { label: "Quotas IA", words: "quotas ia cle api token deepseek ollama antigravity secrets connexion fournisseur", tab: 4,
          section: "widgets_api", target: "secApiKeys" },
        { label: "Notifications (ne pas déranger)", words: "notification dnd ne pas deranger toast silencieux cloche", tab: 4,
          section: "quickshell_notifications", target: "secNotifs" },
        { label: "Localisation (ville, coordonnées, fuseau)", words: "localisation ville position coordonnees latitude longitude fuseau timezone meteo", tab: 4,
          section: "donnees_localisation", target: "secLocalisation" },
        { label: "Calendrier Nextcloud", words: "nextcloud calendrier caldav identifiants agenda compte", tab: 4,
          section: "quickshell_calendrier", target: "secCalendrier" },
        { label: "Homelab (Proxmox)", words: "proxmox homelab serveur noeud vm jeton api token", tab: 4,
          section: "widgets_homelab", target: "secHomelab" },
        { label: "Îlot dynamique (mode, animation, projets)", words: "ilot dynamique pilule animation projets kanban bordure hauteur",
          tab: 1, section: "ilot_config", target: "secIlotConfig" },
        { label: "Indicateurs de la pilule (VPN, capture, Live Activity...)", words: "ilot indicateurs pilule vpn capture live activity media planka workspaces horloge",
          tab: 1, section: "ilot_indicateurs", target: "secIlotIndicateurs" },
        { label: "Applets de l'îlot (systray, système, média, nuit, usb...)", words: "ilot applets systray systeme musique audio nuit batterie volume reseau wifi usb repos etendu",
          tab: 1, section: "ilot_applets", target: "secIlotApplets" },
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
          tab: 0, section: "esthetique_fonds", target: "wallpaperDirRow" },
        { label: "Glissement du fond d'écran", words: "glissement slide wallpaper parallaxe bureau",
          tab: 0, section: "esthetique_fonds", target: "wallpaperSlideRow" },
        { label: "Masque de profondeur du fond", words: "masque profondeur relief parallaxe wallpaper widgets seuil adouci",
          tab: 0, section: "esthetique_fonds", target: "masqueProfondeurRow" },
        { label: "Thèmes et packs d'icônes", words: "icones icone pack theme qt6ct gtk papirus archive zip tar",
          tab: 0, section: "esthetique_icones", target: "secIcones" },
        { label: "Dossier des captures d'écran", words: "capture ecran screenshot dossier chemin enregistrement image",
          tab: 3, section: "ecrans_captures", target: "screenshotsDirRow" },
        { label: "Gaps internes et externes", words: "gaps espacement interieur exterieur marge",
          tab: 0, section: "esthetique_aspect", target: "gapsRow" },
        { label: "Bordures des fenêtres", words: "bordure border epaisseur",
          tab: 0, section: "esthetique_aspect", target: "borderRow" },
        { label: "Arrondis des fenêtres", words: "arrondi rounding rayon fenetre",
          tab: 0, section: "esthetique_aspect", target: "roundingWinRow" },
        { label: "Forme des coins", words: "arrondi rounding power chanfrein squircle forme coin courbe",
          tab: 0, section: "esthetique_aspect", target: "roundingPowerRow" },
        { label: "Disposition de la barre (Classique ou Îlot dynamique)", words: "disposition style barre ilot dynamique island classique",
          tab: 1, section: "quickshell_barres", target: "barStyleRow" },
        { label: "Arrondis des îlots", words: "arrondi rayon ilot quickshell barre",
          tab: 1, section: "quickshell_barres", target: "roundingIslandRow" },
        { label: "Hauteur de la barre", words: "hauteur barre taille bar",
          tab: 1, section: "quickshell_barres", target: "barHeightRow" },
        { label: "Gaps latéraux de la barre", words: "gaps lateraux marge barre ecart cote gauche droite bar gap",
          tab: 1, section: "quickshell_barres", target: "barGapsOutHRow" },
        { label: "Gaps haut/bas de la barre", words: "gaps haut bas vertical marge barre ecart bord bar gap",
          tab: 1, section: "quickshell_barres", target: "barGapsOutVRow" },
        { label: "Pas de redimensionnement", words: "pas redimensionnement resize step",
          tab: 0, section: "esthetique_aspect", target: "resizeRow" },
        { label: "Opacité des fenêtres", words: "opacite fenetres transparence hyprland",
          tab: 0, section: "esthetique_aspect", target: "winOpacityRow" },
        { label: "Opacité des surfaces du shell", words: "opacite surfaces shell verre barre panneau",
          tab: 0, section: "quickshell_barre", target: "shellOpacityRow" },
        { label: "Réglages du visualiseur audio", words: "visualiseur audio onde barres fps colonnes sensibilite lissage epaisseur couleur",
          tab: 1, section: "quickshell_visualiseur", target: "secVisualiseur" },
        { label: "Espaces entre les îlots", words: "espaces ilots transparence transparence vide gap barre media",
          tab: 1, section: "quickshell_barres", target: "barGapsRow" },
        { label: "Taille et passes du flou", words: "flou blur taille passes intensite",
          tab: 0, section: "esthetique_aspect", target: "blurRow" },
        { label: "Flou des surfaces du shell", words: "flou shell layer rule seuil ignore alpha popups",
          tab: 0, section: "quickshell_barre", target: "shellBlurRow" },
        { label: "Écrans, résolution, taux de rafraîchissement", words: "ecran moniteur resolution taux hz echelle scale",
          tab: 3, section: "", target: "monitorsRow" },
        { label: "Fuseau horaire et synchronisation NTP", words: "fuseau timezone heure ntp synchronisation horloge",
          tab: 3, section: "", target: "timezoneRow" },
        { label: "Mise à jour du shell", words: "mise a jour version installateur curl update github aethershell terminal",
          tab: 3, section: "systeme_maj", target: "shellMajRow" },
        { label: "Diagnostic, journaux & sauvegardes", words: "diagnostic logs journaux journalctl services systemd backup hq sauvegarde restaurer",
          tab: 3, section: "systeme_diag", target: "secDiagnostic" },
        { label: "Mise en veille automatique", words: "mise en veille veille inactivité suspend sleep ecran timer energie heure",
          tab: 3, section: "systeme_horloge", target: "idleTimeoutRow" },
        { label: "Disposition du clavier", words: "clavier layout azerty qwerty langue",
          tab: 3, section: "", target: "kbdRow" },
        { label: "Raccourcis Hyprland", words: "raccourcis binds touches clavier hyprland",
          tab: 3, section: "", target: "bindsCol" },
        { label: "Programmes par défaut des raccourcis", words: "applications variables programmes defaut terminal navigateur editeur fichiers chemins",
          tab: 4, section: "apps_programs", target: "secApps" },
        { label: "Historique des lancements", words: "historique lancements recents pilule spotlight memoire",
          tab: 2, section: "widgets_pilule", target: "launchHistoryRow" },
        { label: "Cible du clic sur une notification", words: "notification notifications clic titre cible lien fichier video image dossier commande", 
          tab: 4, section: "quickshell_notifications", target: "secNotifs" },
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
        "donnees_localisation": "secLocalisation",
        "ecrans_captures": "secCaptures",
        "systeme_maj": "shellMajRow"
    })

    // Un nom de section ne dit pas dans quel onglet il vit : sans ça, le clic
    // milieu ouvrait le panneau sur « Bureau » et dépliait une section cachée.
    // Table complète : une section absente d'ici ne fait pas changer d'onglet, donc
    // le clic milieu et la recherche ouvraient le panneau sur « Bureau » en dépliant
    // une section cachée. Neuf sections manquaient.
    readonly property var ongletDeSection: ({
        "esthetique_theme": 0, "esthetique_fonds": 0, "esthetique_aspect": 0,
        "esthetique_icones": 0, "quickshell_barre": 0, "greeter_theme": 0,
        "quickshell_applets": 1, "quickshell_barres": 1, "quickshell_disques": 1,
        "quickshell_visualiseur": 1,
        "ilot_config": 1, "ilot_indicateurs": 1, "ilot_applets": 1,
        "widgets": 2, "widgets_pilule": 2,
        "systeme_nuit": 3, "ecrans_moniteurs": 3, "systeme_horloge": 3,
        "ecrans_captures": 3, "systeme_maj": 3, "systeme_diag": 3,
        "clavier_disposition": 3, "clavier_binds": 3,
        "apps_programs": 4, "apps_autostart": 4, "quickshell_notifications": 4,
        "quickshell_calendrier": 4, "taches_fichiers": 4, "widgets_homelab": 4,
        "donnees_localisation": 4, "widgets_api": 4
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
        geocodage.command = [Quickshell.shellPath("core/as-core"), "weather",
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
        else if (n === 1) h = ongletBarreIlot.item ? ongletBarreIlot.item.implicitHeight : 0
        else if (n === 2) h = ongletBureau.item ? ongletBureau.item.implicitHeight : 0
        else if (n === 3) h = ongletSysteme.item ? ongletSysteme.item.implicitHeight : 0
        else if (n === 4) h = ongletServices.item ? ongletServices.item.implicitHeight : 0
        return h
    }

    function scrollToAnchor(name) {
        const target = root.cibleDe(name)
        if (!target) return
        const y = target.mapToItem(mainFlickable.contentItem, 0, 0).y
        const maxY = Math.max(0, mainFlickable.contentHeight - mainFlickable.height)
        mainFlickable.contentY = Math.max(0, Math.min(y - 12, maxY))
        root.highlightTarget = name
        highlightTimer.restart()
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
    Timer { id: highlightTimer; interval: 1100; onTriggered: root.highlightTarget = "" }

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
        { type: "musique", label: "Musique", icon: "music", preview: "Morceau & pochette" },
        { type: "notes",   label: "Notes rapides", icon: "widgets", preview: "Post-it synchronisé" },
        { type: "sticker", label: "Sticker / Image", icon: "palette", preview: "PNG / SVG / WebP" },
        { type: "systeme", label: "Système" },
        { type: "reseau", label: "Réseau" },
        { type: "disques", label: "Disques" },
        { type: "homelab", label: "Homelab" },
        { type: "hermes",  label: "Hermes" },
        { type: "usb",     label: "Périphériques" },
        { type: "todo",    label: "Tâches" },
        { type: "presse_papiers", label: "Presse-papiers" },
        { type: "deepseek", label: "DeepSeek" },
        { type: "antigravity", label: "Antigravity" },
        // Fusion des trois précédents : un seul widget, blocs empilés.
        { type: "comptes",  label: "Quotas IA" }
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

    Process {
        id: appletsEtatProc
        command: [Quickshell.shellPath("core/as-core"), "bar-applets", "state"]
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
        command: [Quickshell.shellPath("core/as-core"), "calendrier-config", "etat"]
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
        ncEcritProc.command = [Quickshell.shellPath("core/as-core"), "calendrier-config",
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
        command: [Quickshell.shellPath("core/as-core"), "themes-scan", "--sync"]
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
        command: [Quickshell.shellPath("core/as-core"), "installer-theme-couleur", ""]
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
        installThemeProc.command = [Quickshell.shellPath("core/as-core"), "installer-theme-couleur", String(chemin), "--activate"]
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
        const noms = root.nomsTiroirs()
        for (let i = 0; i < noms.length; ++i) {
            if (root.ongletDeSection[noms[i]] !== root.currentTab) continue
            if (root.sectionOpen(noms[i], false))
                return { nom: noms[i], item: root.tiroirDe(noms[i]) }
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

    function rechargerVisualiseur() {
        vizRafraichir.restart()
    }

    function appletCommande(args) {
        appletsCmdProc.command = [Quickshell.shellPath("core/as-core"), "bar-applets"].concat(args)
        appletsCmdProc.running = true
    }

    // ── Disques : la sélection se fait sur la liste réelle des montages ──────
    property var disquesListe: []

    Process {
        id: disquesListeProc
        command: [Quickshell.shellPath("core/as-core"), "disques", "liste"]
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
    // Espaces entre les îlots de la barre du haut : transparents et sans flou
    property bool barGapsTransparent: false
    // Visualiseur audio (style_vars) : capture et dessin.
    property int vizFps: 30
    property int vizCols: 96
    property real vizSensibilite: 1.0
    property real vizLissage: 0.2
    property real vizEpaisseur: 1.4
    property string vizCouleur: "accent"
    property string vizCouleurIsland: "complement"
    property string vizStyleClassic: "onde"
    property string vizStyleIsland: "barres"
    // Jetons proposés au visualiseur — les mêmes que VIZ_COULEURS dans
    // core/config_manager.py, qui refuse tout le reste.
    readonly property var vizCouleurs: [
        { code: "accent", nom: "Accent" },
        { code: "accentMuted", nom: "Accent 2" },
        { code: "complement", nom: "Complém." },
        { code: "fg", nom: "Texte" },
        { code: "warn", nom: "Alerte" },
        { code: "success", nom: "Succès" }
    ]
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
    readonly property var ongletsDeportes: [ ongletApparence, ongletBarreIlot, ongletBureau, ongletSysteme, ongletServices ]

    function tiroirDe(nom) {
        if (root.tiroirs[nom]) return root.tiroirs[nom]
        for (let i = 0; i < root.ongletsDeportes.length; i++) {
            const it = root.ongletsDeportes[i] ? root.ongletsDeportes[i].item : null
            if (it && it.sections && it.sections[nom]) return it.sections[nom]
            // Section née dans un délégué de `Repeater` : son id n'est pas dans
            // la portée du fichier, l'onglet la retrouve par `objectName`.
            if (it && it.sectionsTardives && it.sectionsTardives[nom] && it.objetParObjectName)
                return it.objetParObjectName(String(it.sectionsTardives[nom]))
        }
        return null
    }

    function cibleDe(nom) {
        if (root.targetMap[nom]) return root.targetMap[nom]
        for (let i = 0; i < root.ongletsDeportes.length; i++) {
            const it = root.ongletsDeportes[i] ? root.ongletsDeportes[i].item : null
            if (it && it.cibles && it.cibles[nom]) return it.cibles[nom]
            if (it && it.objetParObjectName) {
                const trouve = it.objetParObjectName(String(nom))
                if (trouve) return trouve
            }
        }
        return null
    }

    // Applique l'état persisté à tous les tiroirs : l'état est la seule source
    // de vérité, donc un tiroir ouvert en referme un autre sans course.
    // Noms de tiroirs connus. La table `tiroirs` du panneau est vide depuis le
    // découpage : les sections vivent dans les composants d'onglet. Seul l'onglet
    // affiché est instancié, et cela suffit — l'accordéon ne referme que des
    // tiroirs du **même** onglet. Sans cette liste, `for (const nom in
    // root.tiroirs)` ne parcourait rien : plus d'accordéon, et les tiroirs à
    // défaut ouvert restaient tous ouverts.
    function nomsTiroirs() {
        const noms = []
        for (const k in root.tiroirs)
            noms.push(k)
        for (let i = 0; i < root.ongletsDeportes.length; ++i) {
            const it = root.ongletsDeportes[i] ? root.ongletsDeportes[i].item : null
            if (!it || !it.sections)
                continue
            for (const k in it.sections)
                if (noms.indexOf(k) < 0)
                    noms.push(k)
            if (it.sectionsTardives)
                for (const k in it.sectionsTardives)
                    if (noms.indexOf(k) < 0)
                        noms.push(k)
        }
        return noms
    }

    function rafraichirTiroirs() {
        // Un seul tiroir ouvert par onglet, et c'est le premier marqué ouvert :
        // l'invariant est tenu ici plutôt que dans chaque bascule, sinon l'ordre
        // des écritures peut laisser deux tiroirs ouverts (cas vu avec le
        // visualiseur sous les applets).
        const ouvertParOnglet = ({})
        const noms = root.nomsTiroirs()
        for (let i = 0; i < noms.length; ++i) {
            const nom = noms[i]
            if (!root.sectionOpen(nom, false)) continue
            const onglet = root.ongletDeSection[nom]
            if (ouvertParOnglet[onglet] === undefined) ouvertParOnglet[onglet] = nom
        }
        for (let i = 0; i < noms.length; ++i) {
            const nom = noms[i]
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
            const noms = root.nomsTiroirs()
            for (let i = 0; i < noms.length; ++i) {
                const autre = noms[i]
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
        const noms = root.nomsTiroirs()
        for (let i = 0; i < noms.length; ++i) {
            const autre = noms[i]
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
        cmdProc.command = [Quickshell.shellPath("core/as-core"), "config"].concat(args)
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

    // Sélecteur unifié de fichier / dossier (SelecteurFichier.qml).
    property string selecteurFichierCible: ""
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
                Theme.configPanelYieldFocus = true
            }
        }
        stderr: SplitParser {
            onRead: donnee => root.depsDetail = String(donnee)
        }
        onExited: code => {
            Theme.configPanelYieldFocus = false
            root.depsEtat = code === 0 ? "à jour" : "incomplet (code " + code + ")"
        }
    }

    function installerDependances() {
        if (depsProc.running)
            return
        depsProc.command = [Quickshell.shellPath("core/as-core"), "deps-install"]
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
        if (typeof data.bar_gaps_transparent === "boolean") root.barGapsTransparent = data.bar_gaps_transparent
        if (typeof data.viz_fps === "number") root.vizFps = data.viz_fps
        if (typeof data.viz_cols === "number") root.vizCols = data.viz_cols
        if (typeof data.viz_sensibilite === "number") root.vizSensibilite = data.viz_sensibilite
        if (typeof data.viz_lissage === "number") root.vizLissage = data.viz_lissage
        if (typeof data.viz_epaisseur === "number") root.vizEpaisseur = data.viz_epaisseur
        if (typeof data.viz_couleur === "string") root.vizCouleur = data.viz_couleur
        if (typeof data.viz_couleur_island === "string") root.vizCouleurIsland = data.viz_couleur_island
        if (typeof data.viz_style_classic === "string") root.vizStyleClassic = data.viz_style_classic
        if (typeof data.viz_style_island === "string") root.vizStyleIsland = data.viz_style_island
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
        command: [Quickshell.shellPath("core/as-core"), "config", "state"]
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
        printErrors: false
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
        printErrors: false
        onSaved: homelabSecretProc.running = true
    }

    Process {
        id: homelabSecretProc
        command: [Quickshell.shellPath("core/as-core"), "config",
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
        dndProc.command = [Quickshell.shellPath("core/as-core"), "config",
                           "style", "do_not_disturb", actif ? "true" : "false"]
        dndProc.running = true
    }

    function reglerNuit(args) {
        nuitProc.command = [Quickshell.shellPath("core/as-core"), "nuit"].concat(args)
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
        command: [Quickshell.shellPath("core/as-core"), "config", "todo_list"]
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
        homelabProc.command = [Quickshell.shellPath("core/as-core"), "config",
                               "homelab_set", cle, valeur]
        homelabProc.running = true
    }

    function homelabSetSecret(valeur) {
        if (String(valeur).trim() === "") return
        homelabSecretFile.setText(JSON.stringify({
            section: "proxmox", nom: "token_secret", valeur: String(valeur).trim()
        }))
    }

    property string plankaTestEtat: ""

    Process {
        id: plankaTestProc
        command: [Quickshell.shellPath("core/as-core"), "config", "planka_test"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text.trim())
                    root.plankaTestEtat = String(res.message || (res.ok ? "Connecté" : "Échec"))
                } catch (e) {
                    root.plankaTestEtat = "Réponse invalide"
                }
            }
        }
    }

    function plankaSetSecret(nom, valeur) {
        const v = String(valeur || "").trim()
        if (v === "") return
        root.plankaTestEtat = ""
        homelabSecretFile.setText(JSON.stringify({
            section: "planka", nom: String(nom), valeur: v
        }))
    }

    function testerPlanka() {
        root.plankaTestEtat = "Test en cours…"
        plankaTestProc.running = true
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
        cleApiProc.command = [Quickshell.shellPath("core/as-core"), "config",
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
                    testCleProc.command = [Quickshell.shellPath("core/as-core"), provider.service, "--force"]
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
                root.majOnglets()
            } else {
                root.dragWidgetType = ""
                root.dragCapsuleId = ""
                root.dragCapsuleLabel = ""
                root.libererOnglets()
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
    function defsOnglets() {
        return [
            [0, ongletApparence, "OngletSubHub.qml", { tabIndex: 0, sourceA: "OngletApparence.qml", sourceB: "OngletConnexion.qml" }],
            [1, ongletBarreIlot, "OngletBarreIlot.qml", { disquesListeProc: disquesListeProc }],
            [2, ongletBureau, "OngletBureau.qml", {}],
            [3, ongletSysteme, "OngletSubHub.qml", { tabIndex: 3, sourceA: "OngletEcrans.qml", sourceB: "OngletClavier.qml" }],
            [4, ongletServices, "OngletSubHub.qml", { tabIndex: 4, sourceA: "OngletDonnees.qml", sourceB: "OngletApps.qml", propsA: { ncEtatProc: ncEtatProc } }]
        ]
    }

    // Un onglet visité **reste monté** jusqu'à la fermeture du panneau : quitter
    // puis revenir ne détruit plus le composant, donc la position de défilement
    // et les champs en cours de saisie sont conservés. Le prix est la mémoire des
    // onglets ouverts ; elle est rendue à la fermeture (`libererOnglets`).
    property var ongletsVisites: ({})

    function majOnglets() {
        const defs = root.defsOnglets()
        for (let i = 0; i < defs.length; ++i) {
            const index = defs[i][0]
            const chargeur = defs[i][1]
            if (root.currentTab !== index)
                continue
            if (chargeur.status === Loader.Null)
                chargeur.setSource(defs[i][2],
                                   Object.assign({ root: root, mainFlickable: mainFlickable }, defs[i][3]))
            if (!root.ongletsVisites[index]) {
                const visites = Object.assign({}, root.ongletsVisites)
                visites[index] = true
                root.ongletsVisites = visites
            }
        }
    }

    function libererOnglets() {
        const defs = root.defsOnglets()
        for (let i = 0; i < defs.length; ++i) {
            const chargeur = defs[i][1]
            if (chargeur.status !== Loader.Null)
                chargeur.source = ""
        }
        root.ongletsVisites = ({})
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
        opacity: root.dragWidgetType !== "" ? 0.12 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
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
        opacity: root.dragWidgetType !== "" ? 0.12 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
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
                        anchors.right: tagOnglet.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: parent.active ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                    }

                    Text {
                        id: tagOnglet
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tabLabels[modelData.tab] || ""
                        color: parent.active ? Qt.alpha(Theme.bg, 0.78) : Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Theme.text2xs
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

    // Barre horizontale d'onglets en haut : profite de la largeur du panneau
    // pour afficher les 5 pôles côte à côte (icône + libellé).
    Row {
        id: navRail
        opacity: root.dragWidgetType !== "" ? 0.12 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.top: searchBar.bottom
        anchors.topMargin: Theme.space3
        anchors.left: parent.left
        anchors.leftMargin: Theme.space4
        anchors.right: parent.right
        anchors.rightMargin: Theme.space4
        height: 36
        spacing: Theme.space2
        z: 5

        Repeater {
            model: [
                { icon: "palette",     label: "Apparence" },
                { icon: "widgets",     label: "Barre & Îlot" },
                { icon: "monitor",     label: "Bureau" },
                { icon: "cog",         label: "Système" },
                { icon: "cloud-check", label: "Services" }
            ]

            Rectangle {
                id: railBtn
                required property int index
                required property var modelData
                readonly property bool active: root.currentTab === index

                width: Math.floor((navRail.width - navRail.spacing * 4) / 5)
                height: 36
                radius: Theme.globalRadius
                color: active
                    ? Theme.accent
                    : (railMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55))
                border.color: active ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: railBtn.modelData.icon
                        size: Theme.iconMd
                        color: railBtn.active ? Theme.bg : Theme.fg
                        opacityLevel: railBtn.active ? 1 : 0.78
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: railBtn.modelData.label
                        color: railBtn.active ? Theme.bg : Theme.fg
                        opacity: railBtn.active ? 1 : 0.86
                        font.pixelSize: Theme.textSm
                        font.bold: railBtn.active
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
        opacity: root.dragWidgetType !== "" ? 0.12 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.top: navRail.bottom
        anchors.topMargin: Theme.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.space4
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
        // Pôle 0 : Apparence & Thème (Apparence + Connexion/Greeter)
        Loader {
            id: ongletApparence
            width: mainFlickable.width
        }

        // Pôle 1 : Barre & Îlot (unifié avec affichage contextuel)
        Loader {
            id: ongletBarreIlot
            width: mainFlickable.width
        }

        // Pôle 2 : Bureau & Widgets
        Loader {
            id: ongletBureau
            width: mainFlickable.width
        }

        // Pôle 3 : Système (Écrans, Clavier & Binds, Nuit, MAJ, Diagnostic)
        Loader {
            id: ongletSysteme
            width: mainFlickable.width
        }

        // Pôle 4 : Services & Comptes (Données, API, Homelab, Apps, Autostart)
        Loader {
            id: ongletServices
            width: mainFlickable.width
        }

        // Surbrillance temporaire sur la ligne ciblée par la recherche
        Rectangle {
            readonly property var cibleObj: root.highlightTarget !== "" ? root.cibleDe(root.highlightTarget) : null
            visible: cibleObj !== null
            x: 0
            y: cibleObj ? cibleObj.mapToItem(mainFlickable.contentItem, 0, 0).y - 3 : 0
            width: mainFlickable.width
            height: cibleObj ? (cibleObj.height + 6) : 0
            radius: Theme.globalRadius
            color: Qt.alpha(Theme.accent, 0.12)
            border.color: Theme.accent
            border.width: 1
            z: 50
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

    // Feuille modale unifiée (fichiers et dossiers via dossierSeulement)
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

    function ouvrirSelecteur(cible, titre, chemin) {
        root.selecteurFichierCible = String(cible)
        root.selecteurFichierParams = ({
            dossierSeulement: true,
            titre: String(titre),
            chemin: root.cheminAbsolu(chemin),
            extensions: [],
            icone: "folder"
        })
        selecteurFichierLoader.active = true
        root.appliquerSelecteurFichier()
    }

    function ouvrirSelecteurFichier(cible, titre, chemin, extensions, icone) {
        root.selecteurFichierCible = String(cible)
        let chem = String(chemin || "")
        if (chem === "") chem = "~"
        root.selecteurFichierParams = ({
            dossierSeulement: false,
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
        it.dossierSeulement = Boolean(p.dossierSeulement)
        it.titre = String(p.titre || "")
        if (p.extensions && p.extensions.length > 0)
            it.extensions = p.extensions
        it.filtrerExtensions = !it.dossierSeulement
        it.icone = String(p.icone || "file-document")
        it.chemin = String(p.chemin || "")
        it.fichierSelectionne = ""
        it.ouvert = true
    }

    function validerSelecteurFichier(chemin) {
        const c = root.selecteurFichierCible
        if (c === "") return
        if (root.selecteurFichierParams && root.selecteurFichierParams.dossierSeulement) {
            root.runConfigCmd(["style", c, String(chemin) + "/"])
        } else if (c === "todo_md") {
            nouveauTodoChemin.text = root.abregerHome(chemin)
            if (nouveauTodoNom.text.trim() === "") {
                const base = String(chemin).split("/").pop().replace(/\.md$/i, "").replace(/\.markdown$/i, "")
                if (base)
                    nouveauTodoNom.text = base
            }
        } else if (c === "install_theme_colors") {
            root.installerThemeCouleur(chemin)
        } else if (c === "lock_bg_image") {
            root.runConfigCmd(["style", "lock_bg_image", String(chemin)])
            root.runConfigCmd(["style", "lock_bg_mode", "image"])
        } else if (c === "icon_pack") {
            root.installerPackIcones(chemin)
        }
        root.selecteurFichierCible = ""
    }

    // Aperçu flottant pendant le glisser-déposer d'un widget vers le bureau.
    Rectangle {
        id: dragGhost
        z: 9999
        visible: root.dragWidgetType !== ""
        x: root.dragPointerX - width / 2
        y: root.dragPointerY - height / 2
        width: Math.max(80, Math.round((dragGhostLoader.item ? dragGhostLoader.item.implicitWidth : 160) + Theme.padH * 2))
        height: Math.max(48, Math.round((dragGhostLoader.item ? dragGhostLoader.item.implicitHeight : 80) + Theme.padH * 2))
        radius: Theme.globalRadius
        color: Qt.alpha(Theme.surfaceBg, 0.85)
        border.color: Theme.accent
        border.width: 2

        Loader {
            id: dragGhostLoader
            anchors.centerIn: parent
            enabled: false
            source: root.dragWidgetType !== "" ? root.widgetSourceFor(root.dragWidgetType) : ""
            onLoaded: {
                if (!item) return
                item.options = root.widgetOptionsFor(root.dragWidgetType)
                item.widgetId = ""
            }
        }
    }

    function dragGhostScreenPos() {
        const p = dragGhost.mapToItem(null, 0, 0)
        return ({ x: p.x, y: p.y })
    }

    // Pilule flottante pendant le glisser-déposer d'un applet entre capsules.
    Rectangle {
        id: dragCapsuleGhost
        z: 9999
        visible: root.dragCapsuleId !== ""
        x: root.dragPointerX - width / 2
        y: root.dragPointerY - height / 2
        width: Math.max(130, dragCapTxt.implicitWidth + 28)
        height: 32
        radius: Theme.globalRadius
        color: Theme.accent
        border.color: Theme.bg
        border.width: 1

        Text {
            id: dragCapTxt
            anchors.centerIn: parent
            text: root.dragCapsuleLabel
            color: Theme.bg
            font.pixelSize: Theme.textXs
            font.bold: true
        }
    }
}
