import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ─────────────────────────────────────────────────────────────────────────────
// 9. SPOTLIGHT PILL — launcher bas-centre qui remplace fuzzel
// ─────────────────────────────────────────────────────────────────────────────
// Chargée par la PanelWindow `shell-spotlight` de main.qml, elle-même pilotée
// par Theme.spotlightVisible (IPC `quickshell ipc call shell toggleSpotlight`).
//
// Trois sources, une seule liste de résultats :
//   • applications — core/app_index.json (core/app_index.py)
//   • alias        — core/app_vars.json, les mêmes que les raccourcis Hyprland
//   • commandes    — préfixe « > », passées telles quelles à sh
//   • prestataires — tout autre préfixe (« = » calcul, « / » fichiers, « ? » aide…)
//     passe à core/launcher_service.py, qui rend la même forme de résultat. La
//     liste des préfixes est lue depuis ce service au démarrage : elle n'est pas
//     recopiée ici, donc elle ne peut pas diverger de ce qui existe vraiment.
// Et, si `launch_history` est activé dans le panneau, les lancements récents
// (core/launch_history.json) affichés à l'ouverture dans le champ vide.
Item {
    id: root

    // Remplit la PanelWindow : c'est la pilule qui se pose en bas au centre.
    property var appIndex: []
    property var aliases: ({})
    property var history: []
    property string query: ""
    property string mode: "apps"    // "apps" | "cmd"
    property var results: []
    property int sel: 0
    onSelChanged: root.majApercu()
    // Résultats d'un prestataire (core/launcher_service.py) : même forme que les
    // entrées locales, plus `action` quand l'effet n'est pas de lancer un programme.
    property var serviceResults: []
    property string serviceKind: ""
    property string prefixSym: ""
    property var prefixes: []      // symboles connus, lus depuis le service
    // Une recherche est en cours : sans ce drapeau, une liste encore vide
    // s'affichait « aucun résultat » pendant que les documents étaient lus.
    property bool recherche: false
    // La recherche a dépassé son délai : la liste vide ne veut pas dire « rien
    // trouvé », et l'afficher ainsi serait un mensonge.
    property bool rechercheCoupee: false
    // Aperçu du fichier sélectionné. `apercuPour` retient le chemin chargé : sans
    // lui, le volet afficherait l'aperçu de la ligne précédente le temps du
    // processus, et l'utilisateur lirait le mauvais fichier.
    property var apercu: ({})
    property string apercuPour: ""
    readonly property var entreeSel: root.results.length > 0 ? root.results[root.sel] : undefined

    // Deux états distincts, et c'est ce qui évite les sauts de la capsule :
    // `apercuAttendu` ne dépend que de la ligne sélectionnée — donc la géométrie
    // de la pilule ne bouge plus quand on passe d'une ligne à l'autre — tandis
    // que `apercuPret` dit seulement si le contenu chargé correspond à cette
    // ligne. Avant, la largeur et la hauteur suivaient `apercu.ok`, qui n'arrive
    // qu'après le processus : la pilule se rétrécissait puis se rallumait à
    // chaque frappe de flèche.
    readonly property bool apercuAttendu: root.entreeSel !== undefined
                                          && root.entreeSel.action === "open"
                                          && (root.entreeSel.kind === "fichier"
                                              || root.entreeSel.kind === "contenu")
    readonly property bool apercuVisible: root.apercuAttendu
    readonly property bool apercuPret: root.apercuAttendu
                                       && root.apercuPour !== ""
                                       && String(root.entreeSel.arg) === root.apercuPour
                                       && root.apercu.ok === true

    readonly property int maxResults: root.serviceKind === "aide" ? 11 : 6
    readonly property int rowHeight: 46
    readonly property bool cmdMode: mode === "cmd"

    // ── index des applications ───────────────────────────────────────────────
    FileView {
        id: indexFile
        path: Quickshell.shellPath("core/app_index.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.appIndex = JSON.parse(text())
            } catch (e) {
                console.warn("spotlight: app_index.json illisible:", e)
                root.appIndex = []
            }
            root.build()
        }
    }

    // ── alias d'applications (partagés avec les raccourcis Hyprland) ─────────
    FileView {
        id: aliasFile
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.aliases = (parsed && typeof parsed === "object") ? parsed : ({})
            } catch (e) {
                root.aliases = ({})
            }
            root.build()
        }
    }

    // ── historique des lancements ────────────────────────────────────────────
    FileView {
        id: historyFile
        path: Quickshell.shellPath("core/launch_history.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.history = Array.isArray(parsed) ? parsed : []
            } catch (e) {
                root.history = []
            }
            root.build()
        }
    }

    // Rafraîchit l'index à l'ouverture : une application installée pendant la
    // session doit apparaître sans redémarrer le shell.
    Process {
        id: indexProc
        command: ["python3", Quickshell.shellPath("core/app_index.py"), "--quiet"]
        onExited: indexFile.reload()
    }

    // La table des préfixes vient du service : une seule source pour ce que le
    // launcher accepte et pour ce que « ? » affiche.
    Process {
        id: tablePrefixes
        command: ["python3", Quickshell.shellPath("core/launcher_service.py"), "--aide"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.prefixes = d.prefixes.map(p => String(p.symbole))
                } catch (e) {
                    root.prefixes = []
                }
            }
        }
    }

    // Une pause de frappe avant d'appeler le service : sans elle, chaque touche
    // lance un python et les processus s'empilent derrière la frappe suivante.
    Timer {
        id: attente
        interval: 260          // une recherche dans les documents prend ~2,4 s
        repeat: false
        onTriggered: {
            if (root.prefixSym === "" || root.prefixSym === ">")
                return
            // La requête précédente n'a plus d'intérêt : sans ça, les recherches
            // s'empilent et la pilule répond avec deux secondes de retard.
            if (svc.running)
                svc.running = false
            root.recherche = true
            svc.command = ["python3", Quickshell.shellPath("core/launcher_service.py"),
                           "--query", root.query, "--limit", String(root.maxResults)]
            svc.running = true
        }
    }

    Process {
        id: svc
        stdout: StdioCollector {
            onStreamFinished: {
                root.recherche = false
                root.rechercheCoupee = false
                try {
                    const d = JSON.parse(text)
                    root.serviceKind = String(d.kind || "")
                    root.serviceResults = d.results || []
                    root.rechercheCoupee = d.interrompu === true
                } catch (e) {
                    root.serviceKind = ""
                    root.serviceResults = []
                }
                // On n'appelle **pas** build() ici : build() relance la recherche,
                // donc chaque réponse en déclenchait une autre, indéfiniment — la
                // pilule passait son temps à osciller entre liste vide et liste
                // pleine, et un python tournait en permanence.
                if (root.prefixSym !== "" && root.prefixSym !== ">") {
                    root.results = root.serviceResults
                    root.sel = 0
                    root.majApercu()
                } else {
                    root.build()
                }
            }
        }
    }

    Process {
        id: procApercu
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apercu = JSON.parse(text)
                } catch (e) {
                    root.apercu = ({})
                }
            }
        }
    }

    // Seuls les résultats « fichier » et « contenu » ont quelque chose à montrer.
    function majApercu() {
        const e = root.entreeSel
        const veut = (e !== undefined && e.action === "open"
                      && (e.kind === "fichier" || e.kind === "contenu"))
                     ? String(e.arg) : ""
        if (veut === root.apercuPour)
            return
        root.apercuPour = veut
        root.apercu = ({})
        if (veut === "")
            return
        procApercu.command = ["python3", Quickshell.shellPath("core/launcher_service.py"),
                              "--apercu", veut]
        procApercu.running = true
    }

    // ── construction de la liste ─────────────────────────────────────────────
    function entry(kind, name, exec, icon, tag) {
        return { kind: kind, name: name, exec: exec, icon: icon, tag: tag }
    }

    // Icône d'un alias : le nom de la commande n'est pas forcément celui de l'icône.
    // « ghostty » installe son icône sous « com.mitchellh.ghostty », donc
    // `image://icon/ghostty` ne rend rien. On cherche donc l'entrée du même binaire
    // dans app_index.json (qui porte le nom d'icône du fichier .desktop).
    function iconForCommand(cmd) {
        const bin = String(cmd || "").trim().split(/\s+/)[0]
        if (bin === "") return ""
        const target = bin.toLowerCase()
        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            const appBin = String(app.exec || "").trim().split(/\s+/)[0].toLowerCase()
            if (appBin === target && app.icon)
                return String(app.icon)
        }
        return bin
    }

    function build() {
        const q = String(root.query).trim()
        const sym = q.length > 0 ? q.charAt(0) : ""

        // Préfixe connu : la liste des résultats vient du service. On ne vide pas
        // les résultats courants pour autant — la pilule garderait un trou le
        // temps du processus.
        if (sym !== "" && sym !== ">" && root.prefixes.indexOf(sym) >= 0) {
            root.mode = "service"
            root.prefixSym = sym
            // « ? » ne dépend pas de la saisie : l'aide doit être immédiate.
            attente.interval = sym === "?" ? 1 : 260
            attente.restart()
            root.results = root.serviceResults
            root.sel = 1
            root.majApercu()
            return
        }
        root.prefixSym = ""
        root.serviceKind = ""
        root.serviceResults = []
        root.recherche = false

        // Mode commande : tout ce qui suit « > » part tel quel dans sh.
        if (q.indexOf(">") === 0) {
            root.mode = "cmd"
            const cmd = q.substring(1).trim()
            root.results = cmd === "" ? [] : [root.entry("cmd", cmd, cmd, "", "commande")]
            root.sel = 1
            return
        }
        root.mode = "apps"

        // Champ vide : les lancements récents, si l'historique est activé.
        if (q === "") {
            root.results = Theme.launchHistory
                    ? root.history.slice(0, root.maxResults).map(h => root.entry(
                          "recent", h.name, h.exec, h.icon || "", "récent"))
                    : []
            root.sel = 1
            return
        }

        const needle = q.toLowerCase()
        const scored = []

        for (const name in root.aliases) {
            const cmd = String(root.aliases[name] || "")
            if (cmd === "") continue
            const low = name.toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 95 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 70 - low.length
            else if (low.indexOf(needle) >= 0) score = 50 - low.length
            if (score >= 0) {
                scored.push({
                    entry: root.entry("alias", name, cmd,
                                      root.iconForCommand(cmd), "alias"),
                    score: score,
                })
            }
        }

        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            const low = String(app.name).toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 100 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 60 - low.length
            else if (low.indexOf(needle) >= 0) score = 40 - low.length
            else if (String(app.comment || "").toLowerCase().indexOf(needle) >= 0) score = 10
            if (score >= 0) {
                scored.push({
                    entry: root.entry("app", app.name, app.exec, app.icon || "",
                                      app.category || ""),
                    score: score,
                })
            }
        }

        scored.sort((a, b) => b.score - a.score
                    || a.entry.name.localeCompare(b.entry.name))
        root.results = scored.slice(0, root.maxResults).map(x => x.entry)
        root.sel = 0
    }

    // Souligne la sous-chaîne trouvée (texte enrichi QML : pas de <span style>).
    function markup(name, highlightColor) {
        const q = String(root.query).trim()
        const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        if (q === "" || q.indexOf(">") === 0) return esc(name)
        const at = name.toLowerCase().indexOf(q.toLowerCase())
        if (at < 0) return esc(name)
        return esc(name.substring(0, at))
             + "<font color=\"" + highlightColor + "\"><u>"
             + esc(name.substring(at, at + q.length))
             + "</u></font>"
             + esc(name.substring(at + q.length))
    }

    // ── actions ──────────────────────────────────────────────────────────────
    // Coller du texte : on le passe en argv d'un python, qui écrit sur stdin de
    // wl-copy. Aucun guillemet à échapper, et un texte multiligne passe intact.
    function copier(texte) {
        Quickshell.execDetached(["python3", "-c",
            "import subprocess,sys;subprocess.run(['wl-copy'],input=sys.argv[1].encode())",
            String(texte)])
    }

    // Un résultat peut avoir un effet qui n'est pas « lancer un programme » :
    // copier, ouvrir, révéler, tuer, préremplir. Rend true si l'action a été prise.
    function gererAction(entry) {
        const arg = entry.arg === undefined ? "" : String(entry.arg)
        switch (entry.action) {
        case "prefill":
            root.query = arg
            searchInput.text = arg
            searchInput.cursorPosition = arg.length
            return true
        case "copy":
            if (entry.kind === "presse")
                // L'identifiant passe par `"$1"` : concaténé dans la chaîne, il
                // fonctionnerait tant que cliphist ne rend que des nombres, et
                // deviendrait une injection le jour où il rend autre chose.
                Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy',
                                         "_", arg])
            else
                root.copier(arg)
            return true
        case "open":
        case "open-url":
            Quickshell.execDetached(["xdg-open", arg])
            return true
        case "kill":
            Quickshell.execDetached(["kill", "-TERM", arg])
            return true
        }
        return false
    }

    function run(entry) {
        if (!entry) return
        if (entry.action) {
            const surPlace = entry.action === "prefill"
            if (root.gererAction(entry)) {
                if (!surPlace)
                    Theme.spotlightVisible = false
                return
            }
        }
        // `cd $HOME` : un lanceur démarre dans le dossier personnel, pas dans
        // celui du shell (hérité de Quickshell).
        const shell = entry.kind === "cmd"
                ? "cd \"$HOME\" && " + entry.exec
                : "cd \"$HOME\" && exec " + entry.exec
        Quickshell.execDetached(["setsid", "sh", "-c", shell])
        if (Theme.launchHistory && entry.exec) {
            Quickshell.execDetached(["python3",
                Quickshell.shellPath("core/launch_history.py"),
                "add", entry.name, entry.exec, entry.icon || ""])
        }
        Theme.spotlightVisible = false
    }

    // SHIFT+P : épingle l'entrée de presse-papiers sélectionnée, ou la détache si
    // elle l'est déjà. L'épinglage vit dans le service (il survit à la rotation de
    // cliphist), le launcher ne fait qu'appeler et relire.
    // SHIFT+D : efface l'entrée sélectionnée. SHIFT+W : vide tout — action sans
    // retour, donc un premier appui arme et le second confirme dans les 4 s.
    function supprimerSelection() {
        const e = root.entreeSel
        if (e === undefined || e.kind !== "presse") return
        const id = String(e.arg || "")
        if (id === "") return
        action.identifiant = id
        action.mode = "--supprimer"
        action.running = false
        action.running = true
    }

    function viderHistorique() {
        if (root.entreeSel === undefined || root.entreeSel.kind !== "presse") return
        action.identifiant = ""
        action.mode = "--vider"
        action.running = false
        action.running = true
    }

    function epinglerSelection() {
        const e = root.entreeSel
        if (e === undefined || e.kind !== "presse") return
        const id = String(e.arg || "")
        if (id === "") return
        const dejaEpinglee = String(e.detail || "").indexOf("épinglé") === 0
        epinglage.mode = dejaEpinglee ? "--desepingler" : "--epingler"
        epinglage.identifiant = id
        epinglage.running = false
        epinglage.running = true
    }

    Process {
        id: action
        property string identifiant: ""
        property string mode: "--supprimer"
        command: ["python3", Quickshell.shellPath("core/launcher_service.py"),
                  action.mode, action.identifiant]
        onExited: root.build()
    }

    Process {
        id: epinglage
        property string identifiant: ""
        property string mode: "--epingler"
        command: ["python3", Quickshell.shellPath("core/launcher_service.py"),
                  epinglage.mode, epinglage.identifiant]
        onExited: root.build()
    }

    function runSelected() {
        if (root.results.length === 0) return
        root.run(root.results[root.sel])
    }

    function move(delta) {
        if (root.results.length === 0) return
        root.sel = (root.sel + delta + root.results.length) % root.results.length
    }

    function complete() {
        if (root.results.length === 0 || root.cmdMode) return
        searchInput.text = root.results[root.sel].name
        searchInput.cursorPosition = searchInput.text.length
    }

    // ── la pilule ────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        width: root.apercuVisible ? 1150 : 720
        height: field.height
                + (root.results.length > 0
                   ? Math.max(list.height + footer.height,
                              root.apercuVisible ? volet.height + 14 : 0)
                   : 0)
                + (root.results.length === 0 && root.query !== "" ? footer.height + 40 : 0)
        radius: 26
        // Même opacité que les popups (shell_opacity) : la pilule reste une
        // surface du shell, pas un panneau opaque.
        color: Theme.surfaceBg
        border.color: Qt.alpha(Theme.accent, 0.26)
        border.width: 1

        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // Absorbe les clics sur les zones inertes de la pilule (pied, marges) :
        // sans ça, ils traversent jusqu'au fond cliquable et ferment la surface.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: {}
        }

        // ── champ de recherche ───────────────────────────────────────────────
        Item {
            id: field
            width: parent.width
            height: 62

            Icon {
                id: lens
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.cmdMode ? "chevron-right" : "search"
                size: Theme.iconMd
                color: Theme.accent
                opacityLevel: 1
            }

            TextInput {
                id: searchInput
                anchors.left: lens.right
                anchors.leftMargin: 14
                anchors.right: escChip.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.textLg
                font.family: root.cmdMode ? "monospace" : Qt.application.font.family
                selectByMouse: true
                clip: true
                focus: Theme.spotlightVisible

                onTextChanged: {
                    root.query = text
                    root.build()
                }
                onAccepted: root.runSelected()
                Keys.onEscapePressed: {
                    if (text !== "") {
                        text = ""
                        root.build()
                    } else {
                        Theme.spotlightVisible = false
                    }
                }
                Keys.onDownPressed: root.move(1)
                Keys.onUpPressed: root.move(-1)
                Keys.onTabPressed: root.complete()
                // SHIFT+P plutôt que CTRL+P : ce dernier est le raccourci
                // d'impression, et le détourner dans un launcher surprend.
                Keys.onPressed: (event) => {
                    // CTRL+SHIFT+D vide tout. Testé avant SHIFT+D seul : les deux
                    // modificateurs satisfont aussi le test « Shift », et sans cet
                    // ordre le vidage serait pris pour une suppression de ligne.
                    if (event.key === Qt.Key_D
                        && (event.modifiers & Qt.ShiftModifier)
                        && (event.modifiers & Qt.ControlModifier)
                        && root.entreeSel !== undefined && root.entreeSel.kind === "presse") {
                        root.viderHistorique()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_D && (event.modifiers & Qt.ShiftModifier)
                        && root.entreeSel !== undefined && root.entreeSel.kind === "presse") {
                        root.supprimerSelection()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_P
                        && (event.modifiers & Qt.ShiftModifier)
                        && root.entreeSel !== undefined
                        && root.entreeSel.kind === "presse") {
                        root.epinglerSelection()
                        event.accepted = true
                    }
                }
            }

            Text {
                visible: searchInput.text === ""
                anchors.left: searchInput.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Rechercher une application…   (? pour de l'aide)"
                color: Qt.alpha(Theme.fg, 0.42)
                font.pixelSize: Theme.textLg
            }

            Rectangle {
                id: escChip
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: escLabel.implicitWidth + 16
                height: 22
                radius: 7
                color: "transparent"
                border.color: Qt.alpha(Theme.fg, 0.14)
                border.width: 1

                Text {
                    id: escLabel
                    anchors.centerIn: parent
                    text: "Échap"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }
            }
        }

        // ── volet d'aperçu ───────────────────────────────────────────────────
        // Il ne s'affiche que lorsqu'une ligne « fichier » ou « contenu » est
        // sélectionnée : ailleurs il n'y a rien à montrer, et une pilule qui
        // s'élargit sans raison fatigue l'œil.
        Rectangle {
            id: volet
            visible: root.apercuVisible
            anchors.top: field.bottom
            anchors.topMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 14
            width: 400
            height: 400
            radius: 16
            color: Qt.alpha(Theme.fg, 0.045)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.09)
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 6

                Text {
                    width: parent.width
                    // La liaison s'évalue même quand le volet est invisible :
                    // sans garde, une liste vide levait « Cannot read property
                    // 'name' of undefined » à chaque frappe.
                    text: root.apercuPret
                          && root.apercu.meta !== undefined
                          && root.apercu.meta.nom !== undefined
                          ? String(root.apercu.meta.nom)
                          : (root.entreeSel !== undefined ? String(root.entreeSel.name) : "")
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                    elide: Text.ElideMiddle
                }

                Text {
                    width: parent.width
                    text: {
                        if (!root.apercuPret)
                            return "chargement…"
                        const m = root.apercu.meta
                        if (m === undefined || m.taille === undefined)
                            return ""
                        // `note` précise la nature de l'aperçu (« texte extrait »
                        // pour un PDF) ; sinon on signale la troncature.
                        const suffixe = root.apercu.note !== undefined
                              ? " · " + String(root.apercu.note)
                              : (root.apercu.tronque ? " · début du fichier" : "")
                        return String(m.taille) + " · " + String(m.date || "") + suffixe
                    }
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }

                Image {
                    visible: root.apercuPret && root.apercu.type === "image"
                    width: parent.width
                    height: visible ? Math.min(parent.height - 40, width * 0.62) : 0
                    fillMode: Image.PreserveAspectFit
                    source: root.apercu.type === "image" ? String(root.apercu.url) : ""
                }

                Text {
                    visible: root.apercuPret && root.apercu.type !== "image"
                    width: parent.width
                    text: (root.apercu.texte !== undefined && String(root.apercu.texte) !== "")
                          ? String(root.apercu.texte)
                          : String(root.apercu.message !== undefined ? root.apercu.message : "")
                    color: Qt.alpha(Theme.fg, 0.76)
                    font.pixelSize: Theme.textXs
                    font.family: "monospace"
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    maximumLineCount: 22
                }
            }
        }

        // ── résultats ────────────────────────────────────────────────────────
        Item {
            id: list
            anchors.top: field.bottom
            width: parent.width - (root.apercuVisible ? volet.width + 26 : 0)
            height: resultsCol.height + 12

            Column {
                id: resultsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 2

                Repeater {
                    model: root.results

                    Rectangle {
                        required property var modelData
                        required property int index

                        width: resultsCol.width
                        height: root.rowHeight
                        radius: 13
                        color: root.sel === index ? Theme.accent : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 12

                            // Pastille d'icône : l'icône du thème si elle existe,
                            // sinon l'initiale — ou « > » pour une commande.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                radius: 9
                                color: root.sel === index ? Qt.alpha(Theme.bg, 0.18)
                                                          : Qt.alpha(Theme.accent, 0.14)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.sym !== undefined
                                          ? String(modelData.sym)
                                          : (modelData.kind === "cmd"
                                             ? ">"
                                             : String(modelData.name).charAt(0).toUpperCase())
                                    color: root.sel === index ? Theme.bg : Theme.accent
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }

                                Image {
                                    anchors.centerIn: parent
                                    // Une vignette de presse-papiers est une image réelle :
                                    // à 18 px on ne distingue qu'une tache de couleur. Les
                                    // glyphes, eux, gardent leur taille.
                                    readonly property bool fichier: String(modelData.icon).charAt(0) === "/"
                                    width: fichier ? 34 : 18
                                    height: fichier ? 30 : 18
                                    fillMode: Image.PreserveAspectCrop
                                    visible: status === Image.Ready
                                    sourceSize.width: fichier ? 68 : 36
                                    sourceSize.height: fichier ? 60 : 36
                                    // Un chemin absolu est une vignette (presse-papiers
                                    // image) : `image://icon/` ne sait résoudre que des
                                    // noms de glyphes, donc on passe par le fichier.
                                    source: modelData.icon === "" ? ""
                                            : (String(modelData.icon).charAt(0) === "/"
                                               ? "file://" + modelData.icon
                                               : "image://icon/" + modelData.icon)
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28 - 12 - tagText.implicitWidth - 12
                                spacing: 1

                                Text {
                                    width: parent.width
                                    textFormat: Text.StyledText
                                    text: root.markup(modelData.name,
                                                      root.sel === index ? Theme.bg : Theme.accentMuted)
                                    color: root.sel === index ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textLg
                                    font.family: modelData.kind === "cmd" ? "monospace" : Qt.application.font.family
                                    elide: Text.ElideRight
                                }

                                // Le contexte du résultat : chemin, pid et charge,
                                // url, extrait. Vide pour les applications, donc
                                // leur ligne ne change pas.
                                Text {
                                    width: parent.width
                                    visible: modelData.detail !== undefined
                                             && String(modelData.detail) !== ""
                                    text: visible ? String(modelData.detail) : ""
                                    color: root.sel === index ? Qt.alpha(Theme.bg, 0.7)
                                                              : Qt.alpha(Theme.fg, 0.45)
                                    font.pixelSize: Theme.textXs
                                    font.family: "monospace"
                                    elide: Text.ElideMiddle
                                }
                            }

                            Text {
                                id: tagText
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.tag ? String(modelData.tag).toUpperCase() : ""
                                color: root.sel === index ? Qt.alpha(Theme.bg, 0.75)
                                                          : Qt.alpha(Theme.fg, 0.34)
                                font.pixelSize: Theme.textXs
                                font.letterSpacing: 0.6
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = index
                            onClicked: root.run(modelData)
                        }
                    }
                }
            }
        }

        // ── aucun résultat ───────────────────────────────────────────────────
        Item {
            visible: root.results.length === 0 && root.query !== ""
            anchors.top: field.bottom
            width: parent.width
            height: 40

            Text {
                anchors.centerIn: parent
                text: root.cmdMode
                      ? "Tapez une commande après « > »"
                      : (root.recherche
                         ? "Recherche en cours…"
                         : (root.rechercheCoupee
                            ? "Recherche interrompue — relancez"
                            : "Aucun résultat pour « " + root.query + " »"))
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: Theme.textSm
            }
        }

        // ── pied ─────────────────────────────────────────────────────────────
        Rectangle {
            id: footer
            anchors.top: list.bottom
            anchors.topMargin: root.results.length > 0 ? 0 : 40
            visible: root.results.length > 0
            width: parent.width
            height: 36
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Qt.alpha(Theme.fg, 0.07)
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "↑ ↓"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text { text: "naviguer"; color: Qt.alpha(Theme.fg, 0.40); font.pixelSize: Theme.textXs }
                }
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Entrée"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text {
                        text: root.cmdMode ? "exécuter" : "lancer"
                        color: Qt.alpha(Theme.fg, 0.40)
                        font.pixelSize: Theme.textXs
                    }
                }
                Row {
                    visible: !root.cmdMode
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Tab"; color: Qt.alpha(Theme.fg, 0.55); font.pixelSize: Theme.textXs }
                    Text { text: "compléter"; color: Qt.alpha(Theme.fg, 0.40); font.pixelSize: Theme.textXs }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: root.cmdMode
                      ? "shell"
                      : root.results.length + (root.results.length > 1 ? " résultats" : " résultat")
                color: Qt.alpha(Theme.fg, 0.28)
                font.pixelSize: Theme.textXs
            }
        }
    }

    // Le panneau vient de s'ouvrir : champ vide, focus clavier, index à jour.
    Connections {
        target: Theme
        function onSpotlightVisibleChanged() {
            if (!Theme.spotlightVisible) return
            searchInput.text = ""
            root.query = ""
            root.mode = "apps"
            root.sel = 0
            indexFile.reload()
            aliasFile.reload()
            historyFile.reload()
            root.build()
            searchInput.forceActiveFocus()
            indexProc.running = true
        }
        // Activer/désactiver l'historique depuis le panneau agit tout de suite.
        function onLaunchHistoryChanged() {
            root.build()
        }
    }

    Component.onCompleted: {
        if (Theme.spotlightVisible) searchInput.forceActiveFocus()
    }
}
