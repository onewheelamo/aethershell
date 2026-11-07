import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ────────────────────────────────────────────────────────────────────────────
// ASSISTANT DE PREMIER LANCEMENT
// ────────────────────────────────────────────────────────────────────────────
// Cinq pages, une seule fois dans la vie de l'installation :
//   0  disposition du clavier (réécrit input.lua et la nomenclature de binds.lua)
//   1  dossiers Images / Vidéos / Documents / Musique (dossiers XDG)
//   2  programmes par défaut (alias d'app_vars, avec les programmes réellement
//      installés en proposition)
//   3  widgets du bureau (une case par nature, comme dans le panneau)
//   4  l'astuce des raccourcis, en gras, et le bouton devient « Terminé ! »
//
// Rien n'est appliqué avant la dernière page : les choix vivent en mémoire, et
// `core/first_run_apply.py` les applique d'un bloc puis pose la marque de premier
// lancement. Un abandon à mi-chemin ne laisse donc pas d'environnement à moitié
// configuré — et l'assistant revient au lancement suivant.
//
// L'état initial vient de `core/first_run_state.py` : dossiers XDG courants,
// alias d'app_vars et présence de leur binaire, widgets déjà posés.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property int etape: 0
    readonly property int etapeFinale: 5

    property string clavier: "fr"
    property var dossiers: []          // [{ nom, xdg, chemin, existe }]
    property var programmes: []        // [{ alias, commande, present, candidats }]
    property var widgets: []           // [{ type, label, pose }]
    property bool pret: false
    property bool applicationEnCours: false
    property string chargeAAppliquer: ""
    property string rapport: ""        // résumé de l'application, en cas d'échec

    readonly property var dispositions: [
        { code: "fr", drapeau: "FR", titre: "Français (AZERTY)",
          detail: "Workspaces : &  é  \"  '  (" },
        { code: "us", drapeau: "US", titre: "English (US QWERTY)",
          detail: "Workspaces : 1  2  3  4  5" },
        { code: "be", drapeau: "BE", titre: "Belge (AZERTY)",
          detail: "Workspaces : &  é  \"  '  (" },
        { code: "gb", drapeau: "GB", titre: "English (UK QWERTY)",
          detail: "Workspaces : 1  2  3  4  5" },
        { code: "de", drapeau: "DE", titre: "Deutsch (QWERTZ)",
          detail: "Workspaces : 1  2  3  4  5" },
        { code: "ch", drapeau: "CH", titre: "Suisse (QWERTZ)",
          detail: "Workspaces : 1  2  3  4  5" }
    ]

    readonly property var titres: [
        "Disposition du clavier",
        "Dossiers personnels",
        "Programmes par défaut",
        "Widgets du bureau",
        "Barre principale",
        "Bienvenue"
    ]

    // Le bord de la barre principale. Les barres supplémentaires du registre
    // disparaissent au profit de ce choix unique : une seule barre, où l'on veut.
    property string barre: "haut"
    readonly property var barresPossibles: [
        { code: "haut", titre: "En haut", detail: "Le classique, trois îlots" },
        { code: "bas", titre: "En bas", detail: "Comme un dock" },
        { code: "cote-gauche", titre: "À gauche", detail: "Bureaux en haut, état en bas" },
        { code: "cote-droite", titre: "À droite", detail: "Bureaux en haut, état en bas" }
    ]

    // ── mutations : la liste est un tableau JS, une mutation en place ne
    //    réveillerait aucune liaison (même raison que dans le tiroir d'historique).
    function majDossier(xdg, chemin) {
        const copie = []
        for (let i = 0; i < dossiers.length; i++) {
            const d = dossiers[i]
            copie.push(d.xdg === xdg ? { nom: d.nom, xdg: d.xdg, chemin: chemin, existe: d.existe } : d)
        }
        dossiers = copie
    }

    function majProgramme(alias, commande) {
        const copie = []
        for (let i = 0; i < programmes.length; i++) {
            const p = programmes[i]
            copie.push(p.alias === alias
                ? { alias: p.alias, commande: commande, present: p.present, candidats: p.candidats }
                : p)
        }
        programmes = copie
    }

    function basculerWidget(nature) {
        const copie = []
        for (let i = 0; i < widgets.length; i++) {
            const w = widgets[i]
            copie.push(w.type === nature
                ? { type: w.type, label: w.label, pose: !w.pose, initial: w.initial }
                : w)
        }
        widgets = copie
    }

    // ── chargement de l'état ────────────────────────────────────────────────
    Process {
        id: etatProc
        command: ["python3", Quickshell.shellPath("core/first_run_state.py")]
        stdout: StdioCollector {
            onStreamFinished: root.lireEtat(text)
        }
    }

    // Lancement explicite plutôt qu'une liaison sur `running` : à la sortie du
    // processus, Quickshell remet `running` à faux, ce qui casserait la liaison
    // et relancerait le script en boucle.
    Component.onCompleted: {
        if (Theme.showKeyboardOnboarding) etatProc.running = true
    }

    Connections {
        target: Theme
        function onShowKeyboardOnboardingChanged() {
            if (Theme.showKeyboardOnboarding && !root.pret) etatProc.running = true
        }
    }

    function lireEtat(texte) {
        let data
        try {
            data = JSON.parse(String(texte))
        } catch (e) {
            console.warn("assistant de premier lancement : état illisible — " + e)
            return
        }
        clavier = String(data.kb_layout || "fr")
        if (String(data.barre || "") !== "") barre = String(data.barre)
        dossiers = data.dossiers || []
        programmes = data.programmes || []
        const liste = []
        const poses = data.widgets || []
        for (let i = 0; i < poses.length; i++) {
            liste.push({ type: poses[i].type, label: poses[i].label,
                         pose: Boolean(poses[i].pose), initial: Boolean(poses[i].pose) })
        }
        widgets = liste
        pret = true
    }

    // ── application des choix ───────────────────────────────────────────────
    // Les choix passent par un fichier, jamais par l'entrée standard : l'écriture
    // est vérifiée (signal `saved`) avant de lancer le script, donc rien ne peut
    // partir dans le vide.
    FileView {
        id: chargeFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-first-run.json"
        atomicWrites: true
        printErrors: true
        onSaved: root.lancerApplication()
        onSaveFailed: err => {
            root.applicationEnCours = false
            root.rapport = "écriture des choix impossible (" + err + ")"
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: root.lireRapport(text)
        }
        onExited: code => {
            root.applicationEnCours = false
            // Le shell relit style_vars : la marque de premier lancement y est
            // déjà écrite par le script quand tout a réussi.
            if (code === 0) {
                Theme.showKeyboardOnboarding = false
                Theme.firstRunCompleted = true
            } else if (root.rapport === "") {
                // Un échec sans message serait invisible : on en fabrique un.
                root.rapport = "l'application des réglages a échoué (code " + code + ")"
            }
        }
    }

    function lireRapport(texte) {
        try {
            const r = JSON.parse(String(texte))
            const problemes = r.erreurs || []
            if (problemes.length > 0)
                rapport = problemes.join(" · ")
        } catch (e) { /* rapport illisible : sans conséquence */ }
    }

    function terminer() {
        const chemins = ({})
        for (let i = 0; i < dossiers.length; i++)
            chemins[dossiers[i].xdg] = dossiers[i].chemin

        const alias = ({})
        for (let i = 0; i < programmes.length; i++) {
            const p = programmes[i]
            if (String(p.commande || "").trim() !== "")
                alias[p.alias] = p.commande
        }

        const ajouter = []
        const retirer = []
        for (let i = 0; i < widgets.length; i++) {
            const w = widgets[i]
            if (w.pose && !w.initial) ajouter.push(w.type)
            if (!w.pose && w.initial) retirer.push(w.type)
        }

        const charge = JSON.stringify({
            kb_layout: clavier,
            dossiers: chemins,
            programmes: alias,
            widgets_ajouter: ajouter,
            widgets_retirer: retirer,
            barre: barre
        })
        chargeAAppliquer = charge
        ecrireEtAppliquer()
    }

    // « Passer » : on ne change rien, on pose seulement la marque de premier
    // lancement. La charge vide dit exactement cela au script.
    function passer() {
        chargeAAppliquer = "{}"
        ecrireEtAppliquer()
    }

    function ecrireEtAppliquer() {
        applicationEnCours = true
        rapport = ""
        chargeFile.setText(chargeAAppliquer)   // → onSaved → lancerApplication()
    }

    function lancerApplication() {
        applyProc.command = ["python3", Quickshell.shellPath("core/first_run_apply.py"),
                             chargeFile.path]
        applyProc.running = true
    }

    // ── la surface ──────────────────────────────────────────────────────────
    PanelWindow {
        id: assistant
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Qt.alpha("#000000", 0.62)
        aboveWindows: true
        visible: Theme.showKeyboardOnboarding
        WlrLayershell.layer: WlrLayer.Overlay
        // Aucun clavier : tout se fait à la souris. Le champ du panneau reste
        // inerte par construction, et rien ne peut avaler une frappe destinée à
        // une fenêtre en dessous.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-onboarding"

        Rectangle {
            id: carte
            width: 640
            height: colonne.implicitHeight + 44
            anchors.centerIn: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 2

            Column {
                id: colonne
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 22
                spacing: 14

                // ── en-tête : titre + pastilles d'étape ──────────────────
                Item {
                    width: parent.width
                    height: 26

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "AetherShell — premier lancement — " + root.titres[root.etape]
                        color: Theme.accent
                        font.pixelSize: Theme.textXl
                        font.bold: true
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: root.etapeFinale + 1

                            Rectangle {
                                required property int index
                                width: index === root.etape ? 18 : 7
                                height: 7
                                radius: 4
                                color: index === root.etape ? Theme.accent
                                     : (index < root.etape ? Qt.alpha(Theme.accent, 0.45)
                                                           : Qt.alpha(Theme.fg, 0.2))
                            }
                        }
                    }
                }

                // ── page 1 : clavier ────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 12
                    visible: root.etape === 0

                    Text {
                        width: parent.width
                        text: "Choisis la disposition de ton clavier. Ce choix configure Hyprland "
                            + "(input.lua) et adapte la nomenclature des raccourcis des workspaces "
                            + "1 à 5 dans binds.lua, pour éviter tout conflit."
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        wrapMode: Text.WordWrap
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 10

                        Repeater {
                            model: root.dispositions

                            Rectangle {
                                id: carteClavier
                                required property var modelData
                                readonly property bool choisi: root.clavier === modelData.code
                                width: (parent.width - 12) / 2
                                height: 58
                                radius: Theme.globalRadius
                                color: choisi
                                    ? Qt.alpha(Theme.accent, 0.25)
                                    : (sourisClavier.containsMouse ? Theme.surfaceVariant
                                                                   : Qt.alpha(Theme.surfaceVariant, 0.55))
                                border.color: choisi ? Theme.accent : Theme.surfaceVariant
                                border.width: choisi ? 2 : 1

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    Rectangle {
                                        width: 30
                                        height: 20
                                        radius: 4
                                        color: carteClavier.choisi ? Theme.accent
                                                                   : Qt.alpha(Theme.fg, 0.14)

                                        Text {
                                            anchors.centerIn: parent
                                            text: carteClavier.modelData.drapeau
                                            color: carteClavier.choisi ? Theme.bg : Theme.fg
                                            font.pixelSize: Theme.text2xs
                                            font.bold: true
                                        }
                                    }

                                    Column {
                                        spacing: 3

                                        Text {
                                            text: carteClavier.modelData.titre
                                            color: carteClavier.choisi ? Theme.accent : Theme.fg
                                            font.pixelSize: Theme.textMd
                                            font.bold: true
                                        }

                                        Text {
                                            text: carteClavier.modelData.detail
                                            color: Qt.alpha(Theme.fg, 0.75)
                                            font.pixelSize: Theme.textXs
                                        }
                                    }
                                }

                                MouseArea {
                                    id: sourisClavier
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.clavier = carteClavier.modelData.code
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: Theme.globalRadius
                        color: Theme.bg
                        border.color: Theme.accentMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (root.clavier === "fr" || root.clavier === "be")
                                ? "Nomenclature binds.lua : ampersand, eacute, quotedbl, apostrophe, parenleft"
                                : "Nomenclature binds.lua : 1, 2, 3, 4, 5 (aucun conflit QWERTY)"
                            color: Theme.info
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }
                }

                // ── page 2 : dossiers ───────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: root.etape === 1

                    Text {
                        width: parent.width
                        text: "Où ranger tes images, vidéos, documents et musique. Ce sont les dossiers "
                            + "XDG standard : les autres applications les suivront. Un dossier absent "
                            + "est créé."
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.dossiers

                        Row {
                            id: ligneDossier
                            required property var modelData
                            width: parent.width
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                text: ligneDossier.modelData.nom
                                color: Qt.alpha(Theme.fg, 0.8)
                                font.pixelSize: Theme.textSm
                            }

                            Rectangle {
                                width: ligneDossier.width - 84 - 10
                                height: 32
                                color: Theme.bg
                                radius: Theme.globalRadius
                                border.color: champDossier.activeFocus ? Theme.accent : Theme.surfaceVariant
                                border.width: 1

                                TextInput {
                                    id: champDossier
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: ligneDossier.modelData.chemin
                                    color: Theme.info
                                    font.pixelSize: Theme.textSm
                                    selectByMouse: true
                                    onTextEdited: root.majDossier(ligneDossier.modelData.xdg, text)
                                }
                            }
                        }
                    }
                }

                // ── page 3 : programmes ────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 9
                    visible: root.etape === 2

                    Text {
                        width: parent.width
                        text: "Les programmes que le shell lance (terminal, navigateur, fichiers…). "
                            + "Une commande absente de la machine est signalée : clique une "
                            + "proposition pour la remplacer."
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: root.programmes

                        Column {
                            id: blocProgramme
                            required property var modelData
                            width: parent.width
                            spacing: 4

                            Row {
                                width: parent.width
                                spacing: 10

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 84
                                    text: blocProgramme.modelData.alias
                                    color: Qt.alpha(Theme.fg, 0.8)
                                    font.pixelSize: Theme.textSm
                                }

                                Rectangle {
                                    width: blocProgramme.width - 84 - 34 - 20
                                    height: 30
                                    color: Theme.bg
                                    radius: Theme.globalRadius
                                    border.color: champProgramme.activeFocus ? Theme.accent : Theme.surfaceVariant
                                    border.width: 1

                                    TextInput {
                                        id: champProgramme
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: blocProgramme.modelData.commande
                                        color: Theme.info
                                        font.pixelSize: Theme.textSm
                                        selectByMouse: true
                                        onTextEdited: root.majProgramme(blocProgramme.modelData.alias, text)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24
                                    text: blocProgramme.modelData.present ? "✓" : "⚠"
                                    color: blocProgramme.modelData.present ? Theme.success : Theme.error
                                    font.pixelSize: Theme.textMd
                                    font.bold: true
                                }
                            }

                            Row {
                                x: 94
                                spacing: 8

                                Repeater {
                                    model: blocProgramme.modelData.candidats

                                    Text {
                                        required property var modelData
                                        text: (modelData.nom === "" ? modelData.commande : modelData.nom)
                                        color: zoneCandidat.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                                        font.pixelSize: Theme.text2xs

                                        MouseArea {
                                            id: zoneCandidat
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.majProgramme(blocProgramme.modelData.alias,
                                                                         modelData.commande)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── page 4 : widgets ───────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: root.etape === 3

                    Text {
                        width: parent.width
                        text: "Les widgets qui vivent derrière les fenêtres. Un seul exemplaire par "
                            + "nature : sur un bureau précis ou sur tous. Tu pourras les déplacer "
                            + "plus tard avec SUPER + MAJ + clic dessus."
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        wrapMode: Text.WordWrap
                    }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: root.widgets

                            Rectangle {
                                id: caseWidget
                                required property var modelData
                                width: (parent.width - 16) / 3
                                height: 34
                                radius: Theme.globalRadius
                                color: modelData.pose ? Qt.alpha(Theme.accent, 0.16) : Theme.surfaceVariant
                                border.width: 1
                                border.color: modelData.pose ? Theme.accent : Theme.surfaceVariant

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Rectangle {
                                        width: 13
                                        height: 13
                                        radius: 3
                                        color: caseWidget.modelData.pose ? Theme.accent : "transparent"
                                        border.width: 1
                                        border.color: caseWidget.modelData.pose
                                            ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: caseWidget.modelData.pose
                                            text: "✓"
                                            color: Theme.bg
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: caseWidget.modelData.label
                                        color: Theme.fg
                                        font.pixelSize: Theme.textSm
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.basculerWidget(caseWidget.modelData.type)
                                }
                            }
                        }
                    }
                }

                // ── page 5 : barre principale ─────────────────────────
                // Le choix du bord décide aussi de la place des applets : on ne
                // demande pas deux fois la même chose à quelqu'un qui découvre
                // l'environnement.
                Column {
                    width: parent.width
                    spacing: 12
                    visible: root.etape === 4

                    Text {
                        width: parent.width
                        text: "Où veux-tu la barre ? Les bureaux iront au début, "
                            + "l'horloge au centre, et l'état de la machine à la fin "
                            + "(systray, réseau, volume, luminosité et batterie, alimentation). "
                            + "Tout reste déplaçable ensuite dans Quickshell → Applets."
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        wrapMode: Text.WordWrap
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 10

                        Repeater {
                            model: root.barresPossibles

                            Rectangle {
                                id: carteBarre
                                required property var modelData
                                readonly property bool choisi: root.barre === modelData.code
                                width: (parent.width - 12) / 2
                                height: 66
                                radius: Theme.globalRadius
                                color: choisi
                                    ? Qt.alpha(Theme.accent, 0.25)
                                    : (sourisBarre.containsMouse ? Theme.surfaceVariant
                                                                 : Qt.alpha(Theme.surfaceVariant, 0.55))
                                border.color: choisi ? Theme.accent : Theme.surfaceVariant
                                border.width: choisi ? 2 : 1

                                // Aperçu : un écran vide et une bande à l'endroit
                                // du bord choisi. Plus parlant qu'un mot.
                                Rectangle {
                                    id: apercu
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 44
                                    height: 30
                                    radius: 4
                                    color: Qt.alpha(Theme.fg, 0.08)
                                    border.color: Qt.alpha(Theme.fg, 0.25)
                                    border.width: 1

                                    Rectangle {
                                        readonly property string c: carteBarre.modelData.code
                                        width: c === "cote-gauche" || c === "cote-droite" ? 4 : apercu.width - 6
                                        height: c === "cote-gauche" || c === "cote-droite" ? apercu.height - 6 : 4
                                        radius: 2
                                        color: carteBarre.choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                        x: c === "cote-gauche" ? 3
                                           : (c === "cote-droite" ? apercu.width - 7 : 3)
                                        y: c === "haut" ? 3
                                           : (c === "bas" ? apercu.height - 7 : 3)
                                    }
                                }

                                Column {
                                    anchors.left: apercu.right
                                    anchors.leftMargin: 10
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Text {
                                        text: carteBarre.modelData.titre
                                        color: carteBarre.choisi ? Theme.accent : Theme.fg
                                        font.pixelSize: Theme.textMd
                                        font.bold: true
                                    }

                                    Text {
                                        width: parent.width
                                        text: carteBarre.modelData.detail
                                        color: Qt.alpha(Theme.fg, 0.75)
                                        font.pixelSize: Theme.textXs
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                MouseArea {
                                    id: sourisBarre
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.barre = carteBarre.modelData.code
                                }
                            }
                        }
                    }
                }

                // ── page 5 : l'astuce, en gras ─────────────────────────
                Column {
                    width: parent.width
                    spacing: 12
                    visible: root.etape === root.etapeFinale

                    Text {
                        width: parent.width
                        text: "Ton environnement est prêt. Retiens surtout ceci :"
                        color: Theme.fg
                        font.pixelSize: Theme.textMd
                        wrapMode: Text.WordWrap
                    }

                    // Deux gestes à retenir, côte à côte : les raccourcis et le
                    // panneau de réglages. Le second ouvre aussi les applets de la
                    // barre, c'est par là qu'on personnalise tout le reste.
                    Row {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 78
                            radius: Theme.globalRadius
                            color: Qt.alpha(Theme.accent, 0.16)
                            border.color: Theme.accent
                            border.width: 1

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "SUPER + K"
                                    color: Theme.accent
                                    font.pixelSize: Theme.textXl
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "tous les raccourcis du clavier"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 78
                            radius: Theme.globalRadius
                            color: Qt.alpha(Theme.accent, 0.16)
                            border.color: Theme.accent
                            border.width: 1

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                spacing: 4

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "SUPER + H"
                                    color: Theme.accent
                                    font.pixelSize: Theme.textXl
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "panneau de réglages : barre, applets, thème"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "SUPER + H  →  panneau de réglages\n"
                            + "SUPER + MAJ + S  →  captures d'écran et vidéos\n"
                            + "SUPER + MAJ + N  →  historique des notifications"
                        color: Qt.alpha(Theme.fg, 0.85)
                        font.pixelSize: Theme.textSm
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.rapport !== ""
                        text: "Certains réglages n'ont pas pu être appliqués : " + root.rapport
                        color: Theme.error
                        font.pixelSize: Theme.textXs
                        wrapMode: Text.WordWrap
                    }
                }

                // ── pied : Précédent / Suivant / Terminé ───────────────
                Row {
                    width: parent.width
                    spacing: 10

                    // Sortie rapide : tout garder tel quel et refermer.
                    Rectangle {
                        width: 78
                        height: 40
                        radius: Theme.globalRadius
                        visible: root.etape < root.etapeFinale
                        color: passerSouris.containsMouse ? Qt.alpha(Theme.accent, 0.18) : "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.22)

                        Text {
                            anchors.centerIn: parent
                            text: root.applicationEnCours ? "…" : "Passer"
                            color: passerSouris.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.65)
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            id: passerSouris
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.pret && !root.applicationEnCours
                            onClicked: root.passer()
                        }
                    }

                    Rectangle {
                        width: 110
                        height: 40
                        radius: Theme.globalRadius
                        visible: root.etape > 0
                        color: precedent.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.6)
                        border.width: 1
                        border.color: Theme.surfaceVariant

                        Text {
                            anchors.centerIn: parent
                            text: "Précédent"
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                        }

                        MouseArea {
                            id: precedent
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.etape > 0) root.etape -= 1
                        }
                    }

                    Rectangle {
                        width: parent.width
                             - (root.etape > 0 ? 120 : 0)
                             - (root.etape < root.etapeFinale ? 88 : 0)
                        height: 40
                        radius: Theme.globalRadius
                        color: suivant.containsMouse ? Theme.accentMuted : Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: root.applicationEnCours ? "Application…"
                                  : (root.etape === root.etapeFinale ? "Terminé !"
                                  : (root.etape === 0 ? "Choisir mes dossiers" : "Suivant"))
                            color: Theme.bg
                            font.pixelSize: Theme.textMd
                            font.bold: true
                        }

                        MouseArea {
                            id: suivant
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.pret && !root.applicationEnCours
                            onClicked: {
                                if (root.etape < root.etapeFinale) root.etape += 1
                                else root.terminer()
                            }
                        }
                    }
                }
            }
        }
    }
}
