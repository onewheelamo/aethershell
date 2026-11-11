import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET FENÊTRES MINIMISÉES — une icône par fenêtre mise de côté.
//
// Hyprland 0.57 n'a pas de « minimiser » : le geste (SUPER + D) envoie la
// fenêtre au focus sur le workspace spécial `special:minimized`, invisible. Cet
// applet en montre une icône par fenêtre ; un clic la rappelle sur le bureau
// courant, au premier plan.
//
// Rien n'est tenu dans un fichier : la liste est lue sur les toplevels vivants
// (`Theme.fenetresMinimisees`). Une fenêtre fermée, ou revenue d'elle-même,
// quitte la rangée sans laisser d'entrée fantôme — c'est la raison de ne pas
// mémoriser le bureau d'origine.
//
// Largeur nulle quand rien n'est minimisé : le catalogue le marque
// `efface_vide`, et `Applet.qml` masque alors l'applet, sinon la rangée de
// l'îlot garderait un espace vide de la largeur de son `spacing`.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0
    property bool verticale: false

    implicitWidth: rangee.implicitWidth
    implicitHeight: rangee.implicitHeight

    // Fenêtres lues à l'instant : [{ adresse, classe, titre }], dans l'ordre des
    // minimisations (la plus récente en dernier, comme une pile).
    property var fenetres: []
    // classe → { icone, nom } résolu par `core/app_classes.py`. Une invocation
    // par classe nouvelle de la session : le QML ne parse pas de .desktop.
    property var infos: ({})
    property var enCours: []
    property var enAttente: []

    // ── lecture des fenêtres ─────────────────────────────────────────────────
    function rafraichir() {
        const liste = []
        const tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            if (!t || !t.address) continue
            if (!Theme.estMinimisee(t)) continue
            const client = t.lastIpcObject || ({})
            liste.push({
                adresse: String(t.address),
                classe: String(client["class"] || ""),
                titre: String(t.title || client["title"] || "")
            })
        }
        // L'ordre de la session vient de `Theme` ; ce qui est arrivé sur le
        // workspace spécial par un autre chemin se range à la fin.
        const rang = function (adresse) {
            const i = Theme.ordreMinimisees.indexOf(String(adresse))
            return i < 0 ? 1000 : i
        }
        liste.sort(function (a, b) { return rang(a.adresse) - rang(b.adresse) })
        root.fenetres = liste
        root.demanderDetails()
    }

    // ── icônes ───────────────────────────────────────────────────────────────
    // Trois essais, dans cet ordre : l'icône déclarée par l'entrée .desktop, la
    // classe elle-même (souvent un nom d'icône valide : `firefox`), puis une
    // icône générique — jamais une case vide et muette.
    function sourceIcone(classe) {
        const connu = root.infos[classe] || ({})
        const essais = [String(connu.icone || ""), String(classe || ""), "application-x-executable"]
        for (let i = 0; i < essais.length; i++) {
            const nom = essais[i]
            // `iconPath` rend déjà une URL (`image://icon/…`) : la préfixer de
            // `file://` donne une source morte — mesuré, repli sur le glyphe
            // alors que l'icône existe.
            if (nom !== "" && Quickshell.hasThemeIcon(nom))
                return Quickshell.iconPath(nom, true)
        }
        return ""
    }

    function demanderDetails() {
        const manquantes = []
        for (let i = 0; i < root.fenetres.length; i++) {
            const c = root.fenetres[i].classe
            if (c !== "" && root.infos[c] === undefined && manquantes.indexOf(c) < 0
                    && root.enAttente.indexOf(c) < 0)
                manquantes.push(c)
        }
        if (manquantes.length === 0) return
        if (details.running) {
            root.enAttente = root.enAttente.concat(manquantes)
            return
        }
        root.lancer(manquantes)
    }

    function lancer(classes) {
        root.enAttente = []
        root.enCours = classes
        details.command = ["python3", Quickshell.shellPath("core/app_classes.py"),
                           "--classes=" + classes.join(",")]
        details.running = true
    }

    Process {
        id: details
        stdout: StdioCollector {
            onStreamFinished: {
                let lus = ({})
                try {
                    lus = JSON.parse(text.trim())
                } catch (e) {
                    console.warn("minimise: réponse illisible")
                    return
                }
                const suite = Object.assign({}, root.infos)
                for (const c in lus) suite[c] = lus[c]
                root.infos = suite
            }
        }
        onExited: {
            // Un échec ne doit pas boucler : les classes demandées sont
            // inscrites vides, donc plus jamais redemandées, et la rangée
            // retombe sur sa classe puis sur l'icône générique.
            if (code !== 0) {
                const suite = Object.assign({}, root.infos)
                for (let i = 0; i < root.enCours.length; i++)
                    suite[root.enCours[i]] = ({ icone: "", nom: "" })
                root.infos = suite
            }
            root.enCours = []
            if (root.enAttente.length > 0)
                root.lancer(root.enAttente)
            else
                root.demanderDetails()
        }
    }

    // ── rappel ───────────────────────────────────────────────────────────────
    function rappeler(adresse) {
        Theme.rappelerFenetre(adresse)
    }

    // ── suivi vivant ─────────────────────────────────────────────────────────
    // Les événements de fenêtre suffisent ; le minuteur n'est qu'un filet de
    // sécurité (il ne lance aucun processus).
    // Le rafraîchissement est **différé** : au moment où l'événement arrive,
    // Hyprland n'a pas encore republié le workspace de la fenêtre, et une
    // lecture immédiate rend l'état d'avant — mesuré : la rangée restait une
    // fenêtre en retard, jusqu'au minuteur de sécurité (dix secondes).
    Timer {
        id: rafraichissementDiffere
        interval: 350
        onTriggered: root.rafraichir()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const nom = String(event ? event.name : "")
            // Les événements de fenêtre n'ont pas tous un nom qui commence par
            // « window » : mesuré sur cette session, un rappel émet
            // `movewindow`, `movewindowv2`, `destroyworkspacev2`,
            // `activewindowv2` — un filtre par préfixe ne réveillait donc
            // jamais la rangée, qui restait en retard jusqu'au minuteur de dix
            // secondes. On ignore seulement ce qui ne touche pas l'ensemble des
            // fenêtres (`activelayout` part à chaque re-tuilage).
            if (nom === "" || nom === "activelayout") return
            rafraichissementDiffere.restart()
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.rafraichir()
    }

    Component.onCompleted: root.rafraichir()

    // Sonde de diagnostic, comme `shell notifTargets` : elle dit ce que la
    // rangée montre vraiment — le nombre de fenêtres et sa largeur — sans
    // capture d'écran.
    //   quickshell ipc -n call minimise etat
    IpcHandler {
        target: "minimise"

        function etat(): string {
            const liste = []
            for (let i = 0; i < root.fenetres.length; i++)
                liste.push({ adresse: root.fenetres[i].adresse,
                             classe: root.fenetres[i].classe,
                             titre: root.fenetres[i].titre,
                             icone: root.sourceIcone(root.fenetres[i].classe) })
            // Position à l'écran de chaque icône : c'est ce qui rend le clic
            // vérifiable par un pointeur scripté, sans capture d'écran.
            const rendus = []
            for (let i = 0; i < repeteur.count; i++) {
                const item = repeteur.itemAt(i)
                const centre = item ? item.mapToItem(null, item.width / 2, item.height / 2) : null
                rendus.push(item ? { etat: item.etatIcone,
                                     x: centre ? Math.round(centre.x) : -1,
                                     y: centre ? Math.round(centre.y) : -1 } : { etat: -1, x: -1, y: -1 })
            }
            return JSON.stringify({ fenetres: liste.length,
                                    largeur: Math.round(root.implicitWidth),
                                    icones: rendus,
                                    detail: liste })
        }

        function rafraichir() {
            root.rafraichir()
        }

    }

    // ── rangée ───────────────────────────────────────────────────────────────
    // Un `Grid` et non un `Row` : sur une barre de côté les icônes s'empilent.
    Grid {
        id: rangee
        columns: root.verticale ? 1 : 64
        spacing: Math.max(2, Math.round(4 * root.echelle))

        Repeater {
            id: repeteur
            model: root.fenetres

            delegate: Item {
                id: caseFenetre
                required property var modelData

                readonly property int cote: Math.max(16, Math.round(22 * root.echelle))
                readonly property string source: root.sourceIcone(caseFenetre.modelData.classe)
                // Publié pour la sonde : une icône « résolue » mais illisible
                // (source morte) se voyait comme un glyphe de repli, sans erreur.
                readonly property int etatIcone: imageIcone.status

                width: caseFenetre.cote
                height: caseFenetre.cote

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.globalRadius
                    color: souris.containsMouse ? Theme.surfaceVariant : "transparent"
                }

                Image {
                    id: imageIcone
                    anchors.fill: parent
                    anchors.margins: Math.round(3 * root.echelle)
                    source: caseFenetre.source
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: source !== "" && status === Image.Ready
                }

                // Repli : pas d'icône dans le thème, ou fichier illisible. Un
                // glyphe monochrome, comme partout ailleurs dans le shell.
                Icon {
                    anchors.centerIn: parent
                    visible: !imageIcone.visible
                    glyph: "monitor"
                    size: Math.max(12, Math.round(Theme.iconSm * root.echelle))
                    color: Theme.fg
                    opacityLevel: 0.85
                }

                MouseArea {
                    id: souris
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rappeler(caseFenetre.modelData.adresse)
                    onEntered: {
                        root.survol = caseFenetre
                        root.survolTitre = caseFenetre.modelData.titre
                        delaiSurvol.restart()
                    }
                    onExited: {
                        delaiSurvol.stop()
                        root.montrerSurvol = false
                        root.survol = null
                        root.survolTitre = ""
                    }
                }
            }
        }
    }

    // ── titre au survol ──────────────────────────────────────────────────────
    // Deux fenêtres d'une même application donnent deux icônes identiques : le
    // titre est le seul moyen de les distinguer avant le clic.
    property Item survol: null
    property string survolTitre: ""
    property bool montrerSurvol: false

    Timer {
        id: delaiSurvol
        interval: 300
        onTriggered: root.montrerSurvol = root.survol !== null && root.survolTitre !== ""
    }

    Popup {
        id: infobulle
        ancre: root.survol ? root.survol : root
        ile: String(root.applet.ile || "")
        alignement: "centre"
        visible: root.montrerSurvol
        implicitWidth: Math.ceil(texteTitre.implicitWidth + Theme.space3 * 2)
        implicitHeight: Math.ceil(texteTitre.implicitHeight + Theme.space2 * 2)
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Qt.alpha(Theme.accent, 0.55)
            border.width: 1

            Text {
                id: texteTitre
                anchors.centerIn: parent
                text: root.survolTitre
                color: Theme.fg
                font.pixelSize: Math.round(Theme.textXs * root.echelle)
            }
        }
    }
}
