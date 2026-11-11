import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET DE BARRE — une icône, une valeur, un popup.
//
// Ce composant ne sait rien de ce qu'il affiche : il lance le service déclaré
// dans le catalogue (`applets_catalogue.json`), lit le contrat
// (core/applet_contrat.py) et dessine. Un applet de plus = une entrée de
// catalogue + un service ; aucun QML à écrire.
//
// La barre ne montre qu'une valeur (`compact.valeur`) : c'est le service qui
// choisit ce qui compte, parce que lui seul sait ce qui est grave.
Item {
    id: root
    // Entrée résolue par bar_applets.py : id, nom, icone, service, popup,
    // cadence, text_scale, options.
    property var applet: ({})

    readonly property string appletId: String(applet.id || "")
    readonly property string service: String(applet.service || "")
    readonly property real echelle: {
        const v = Number(applet.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    // En minutes, et fractionnaire : un applet qui attend une réponse humaine
    // ne peut pas se contenter d'une minute (0.17 ≈ 10 s). L'arrondi à l'entier
    // interdisait toute cadence sous la minute.
    readonly property real cadenceMin: {
        const v = Number(applet.cadence)
        return (v > 0 && v <= 120) ? v : 5
    }

    property var donnees: ({})
    property bool charge: false
    property bool occupe: false

    readonly property bool ok: charge && donnees && donnees.ok === true
    readonly property var ligne: (ok && donnees.compact) ? donnees.compact : ({})
    readonly property bool alerte: ok && donnees.alerte === true
    // « … » tant que le service n'a pas répondu, « — » s'il a échoué : dans les
    // deux cas on n'invente pas de valeur.
    readonly property string valeur: ok ? String(ligne.valeur || "")
                                       : (charge ? "—" : "…")
    // Certains services donnent aussi une forme courte de leur valeur
    // (`compact.court` : « 06/11 » pour « ven. 6 nov. ») : c'est la seule qu'une
    // colonne étroite peut afficher sans la couper.
    readonly property string valeurCourte: (ok && ligne.court) ? String(ligne.court) : ""
    // Mode jauge : plusieurs mesures, une mini-barre chacune (applet système).
    readonly property var barres: (ok && ligne.barres && ligne.barres.length)
                                  ? ligne.barres : []
    // Carte de survol : le contrat peut publier `survol` — la liste de ce que la
    // barre ne montre pas. Elle s'affiche après un court délai, sans clic et sans
    // prendre le focus ; le popup complet reste au clic. Deux affordances
    // distinctes : effleurer pour voir, cliquer pour agir.
    readonly property var survol: (ok && donnees.survol && donnees.survol.length)
                                  ? donnees.survol : []
    property bool carteSurvol: false

    // Clic milieu : les réglages de cet applet, comme un widget qui ouvre ses
    // préférences. Déclaré avant les autres surfaces, donc dessous : les applets
    // ne réclament que le bouton gauche, le milieu retombe ici. Le catalogue
    // peut nommer une section (`panneau`), sinon c'est la liste des applets.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: Theme.openConfigSection(String(root.applet.panneau || "quickshell_applets"))
    }

    HoverHandler {
        id: survolHover
        onHoveredChanged: {
            if (hovered) {
                delaiMontrer.restart()
            } else {
                delaiMontrer.stop()
                delaiCacher.restart()
            }
        }
    }

    Timer {
        id: delaiMontrer
        interval: 350
        onTriggered: root.carteSurvol = true
    }

    Timer {
        id: delaiCacher
        interval: 220
        onTriggered: root.carteSurvol = false
    }

    readonly property string infobulle: {
        if (!ok) return String((donnees && donnees.error) || "")
        const libelle = String(ligne.libelle || "")
        const nom = String(applet.nom || "")
        return libelle !== "" ? nom + " · " + libelle : nom
    }
    // Deux façons d'ouvrir un popup, selon ce que déclare le catalogue :
    //  - `popup` : un fichier QML chargé dans la fenêtre de l'applet (cas général) ;
    //  - `popup_cle` : un panneau qui vit encore dans un îlot (calendrier, média).
    //    C'est une dette assumée : ces panneaux font plusieurs centaines de lignes
    //    et les déplacer n'apporterait rien à l'utilisateur ; l'applet en est le
    //    seul déclencheur, et la clé est la même que celle des îlots.
    readonly property string popupCle: String(applet.popup_cle || "")
    readonly property bool popupExterne: popupCle !== ""
    // L'applet connaît son emplacement (« barre:place ») : c'est ce qui donne
    // l'orientation du popup et, pour les panneaux autonomes, de quel côté ils
    // doivent s'ouvrir.
    readonly property string ile: String(applet.ile || "")

    // ── deux genres d'applet ─────────────────────────────────────────────────
    // « service » : un script Python rend un contrat JSON, l'applet dessine.
    // « qml » : le catalogue désigne un composant QML qui se dessine lui-même et
    // possède son propre popup. Nécessaire dès qu'il n'y a rien à interroger
    // (horloge, workspaces) ou qu'il faut un état vivant, réactif au clic
    // (volume, réseau, systray). Sans cette seconde voie, la barre ne serait
    // modulaire qu'à moitié : les applets « système » resteraient en dur.
    readonly property bool estQml: String(applet.genre || "service") === "qml"
    readonly property string composant: String(applet.composant || "")

    // Orientation : c'est la barre qui porte l'applet qui la donne, et `ile`
    // s'écrit « barre:place ». Sur un côté, la bande fait `barHeight` de large :
    // une rangée horizontale n'y tient pas, l'applet se dessine donc en colonne
    // (icône au-dessus de la valeur).
    readonly property bool verticale: String(applet.ile || "").indexOf("cote-") === 0
    // Valeur vide : l'applet s'efface au lieu d'afficher un tiret (cas du
    // morceau : rien ne joue).
    readonly property bool sansValeur: ok && valeur === ""
    // Certains applets n'ont de valeur que tant qu'une mesure est choisie : sans
    // valeur ils disparaîtraient, alors que leur popup est le seul endroit où
    // rallumer cette mesure. Le catalogue les marque `garde` pour les garder.
    readonly property bool garde: applet.garde === true
    // Un applet « qml » peut n'avoir rien à montrer — la rangée des fenêtres
    // minimisées est vide la plupart du temps. Le catalogue le marque
    // `efface_vide` pour que l'îlot referme la place : sans ça, la rangée
    // garderait son `spacing` et la barre montrerait un trou de la largeur d'un
    // espace. Le test porte sur la largeur chargée, pas sur un état interne.
    readonly property bool effaceVide: estQml && applet.efface_vide === true
    readonly property bool vide: effaceVide && chargeurQml.implicitWidth <= 0
    visible: (!sansValeur || garde) && !vide

    // Un seul popup ouvert à la fois, et il est identifié par son applet : deux
    // applets ne peuvent donc pas s'ouvrir l'un sur l'autre.
    readonly property bool ouvert: popupExterne
                                   ? (Theme.activePopup === popupCle)
                                   : (Theme.activePopup === "applet:" + appletId)

    implicitWidth: estQml ? (verticale ? Math.min(chargeurQml.implicitWidth, Theme.barSideWidth)
                                      : chargeurQml.implicitWidth)
                          : (verticale ? contenuVertical.implicitWidth : contenu.implicitWidth)
    implicitHeight: estQml ? chargeurQml.implicitHeight
                           : (verticale ? contenuVertical.implicitHeight : contenu.implicitHeight)

    function rafraichir(force) {
        if (root.estQml || root.service === "" || root.occupe) return
        root.occupe = true
        const args = ["python3", Quickshell.shellPath(root.service)]
        // Les options de l'applet (quelles mesures, quel dossier…) viennent du
        // registre : le service n'a pas à savoir qui les a choisies.
        const opts = root.applet.options || ({})
        if (Object.keys(opts).length > 0) args.push("--options=" + JSON.stringify(opts))
        if (force) args.push("--force")
        proc.command = args
        proc.running = true
    }

    onServiceChanged: if (!root.estQml && root.service !== "") root.rafraichir(false)
    Component.onCompleted: if (!root.estQml && root.service !== "") root.rafraichir(false)

    Timer {
        interval: Math.max(1000, root.cadenceMin * 60000)
        repeat: true
        running: !root.estQml
        // La cadence choisie est la cadence réelle : sans --force, le cache du
        // service ignorerait un réglage à 1 ou 2 minutes.
        onTriggered: root.rafraichir(true)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.donnees = JSON.parse(text.trim())
                } catch (e) {
                    root.donnees = { ok: false, error: "réponse illisible" }
                }
                root.charge = true
                root.occupe = false
            }
        }
        onExited: root.occupe = false
    }

    Row {
        id: contenu
        visible: !root.estQml && !root.verticale
        // En mode jauge, les mesures ont besoin d'air pour ne pas se lire comme
        // une seule barre bariolée.
        spacing: root.barres.length > 0
                 ? Math.max(8, Math.round(Theme.space3 * root.echelle))
                 : Math.max(3, Math.round(Theme.space2 * root.echelle))

        // ── Mode jauge : une mini-barre par mesure ───────────────────────────
        // La piste garde une largeur fixe (26 px) pour que les barres ne
        // bougent pas quand le pourcentage passe de « 9% » à « 100% ».
        Repeater {
            model: root.barres

            delegate: Row {
                spacing: 4

                // Le remplissage porte la couleur ; le texte reste lisible même
                // à l'état normal, sinon quatre pourcentages colorés hurlent.
                function couleur(niveau) {
                    if (niveau === "critique") return Theme.error
                    if (niveau === "attention") return Theme.warn
                    return Theme.accent
                }

                function couleurTexte(niveau) {
                    if (niveau === "critique") return Theme.error
                    if (niveau === "attention") return Theme.warn
                    return Theme.fg
                }

                // Icône SVG : Nerd Font n'a ni puce, ni carte graphique, ni
                // thermomètre (un glyphe absent rend une icône vide et muette).
                IconSvg {
                    anchors.verticalCenter: parent.verticalCenter
                    nom: String(modelData.icone || "")
                    size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
                    couleur: parent.couleurTexte(String(modelData.niveau || "ok"))
                    opacite: 0.75
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(26 * root.echelle)
                    height: Math.max(3, Math.round(4 * root.echelle))
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.18)

                    Rectangle {
                        width: Math.max(0, Math.min(parent.width,
                                     parent.width * (Number(modelData.remplissage) || 0) / 100))
                        height: parent.height
                        radius: parent.radius
                        color: parent.parent.couleur(String(modelData.niveau || "ok"))
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.texte || "")
                    color: parent.couleurTexte(String(modelData.niveau || "ok"))
                    font.pixelSize: Math.round(Theme.textXs * 0.92 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        // ── Mode valeur simple : une icône et un chiffre ─────────────────────
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.barres.length === 0
            glyph: String(root.applet.icone || "")
            size: Math.max(10, Math.round(Theme.iconSm * root.echelle))
            color: root.alerte ? Theme.warn : Theme.fg
            opacityLevel: root.ok ? 0.92 : 0.45
        }

        // La valeur passe par un texte borné : une valeur plus longue que la
        // place disponible (un titre de morceau, par exemple) défile au lieu de
        // pousser l'îlot — et donc toute la barre avec lui. Quand elle tient, le
        // rendu est celui d'un `Text` simple, sans animation.
        Defilement {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.barres.length === 0 && texte !== ""
            texte: root.valeur
            couleur: root.alerte ? Theme.warn : Theme.fg
            taillePolice: Math.round(Theme.textXs * root.echelle)
            largeurMax: Math.round(200 * root.echelle)
        }
    }

    // Rendu vertical (barre de côté) : l'icône au-dessus de la valeur, rien de
    // plus — `barSideWidth` de large ne laisse pas la place à une rangée. Les
    // jauges ne s'y empilent pas non plus (quatre pistes de 26 px ne tiennent
    // pas dans cette largeur) : l'applet montre alors sa valeur comme les autres.
    Column {
        id: contenuVertical
        visible: !root.estQml && root.verticale
        spacing: Math.max(1, Math.round(Theme.space1 * root.echelle))

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            glyph: String(root.applet.icone || "")
            size: Math.max(10, Math.round(Theme.iconSm * 0.9 * root.echelle))
            color: root.alerte ? Theme.warn : Theme.fg
            opacityLevel: root.ok ? 0.92 : 0.45
        }

        Defilement {
            anchors.horizontalCenter: parent.horizontalCenter
            // En colonne, la valeur ne s'affiche que si elle tient entièrement
            // dans la bande : une valeur coupée se lit mal, et le détail est
            // dans le popup. Sur une barre horizontale, elle défile au besoin.
            visible: texte !== "" && (!root.verticale || largeurTexte <= largeurMax)
            texte: root.valeurCourte !== "" ? root.valeurCourte : root.valeur
            couleur: root.alerte ? Theme.warn : Theme.fg
            // Même taille que la barre horizontale, et toute la largeur de la
            // bande : une valeur courte (« 06/11 ») doit se lire, pas se
            // deviner. Ce qui ne tient pas est masqué par le test ci-dessus.
            taillePolice: Math.round(Theme.textXs * root.echelle)
            largeurMax: Math.max(20, Math.round(Theme.barSideWidth - 2))
        }
    }

    // Composant QML : il gère son propre clic et son propre popup.
    Loader {
        id: chargeurQml
        // Source relative : avec une URL absolue (`file://` + chemin), Quickshell
        // recompilait le composant dans un second moteur QML — les applets
        // obtenaient alors leur PROPRE instance du singleton Theme, et tout ce
        // qu'ils écrivaient (compteur, ouverture du tiroir d'historique) restait
        // invisible pour le reste de la coquille.
        source: (root.estQml && root.composant !== "") ? String(root.composant) : ""
        // Sur une barre de côté, la bande fait `barSideWidth` de large : le
        // composant garde sa rangée naturelle (il commence par son icône) et le
        // reste est découpé. Il reste monté, donc son clic et son popup
        // continuent de fonctionner — c'est le nom, au survol, qui dit de quel
        // applet il s'agit. `clip` n'agit qu'en colonne : sur une barre
        // horizontale, la rangée garde sa largeur naturelle.
        width: root.verticale ? Math.min(implicitWidth, Theme.barSideWidth) : implicitWidth
        clip: root.verticale
        onLoaded: {
            if (!item) return
            item.echelle = Qt.binding(() => root.echelle)
            item.applet = Qt.binding(() => root.applet)
            // Les composants QML qui savent se dessiner en colonne le lisent ici
            // (workspaces : bureaux empilés, le n°1 en haut). Les autres ne
            // déclarent pas la propriété : y écrire lève « Cannot assign to
            // non-existent property », donc on ne la pose que si elle existe.
            if (item.verticale !== undefined) item.verticale = Qt.binding(() => root.verticale)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.estQml
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const cle = root.popupExterne ? root.popupCle : ("applet:" + root.appletId)
            Theme.activePopup = root.ouvert ? "" : cle
            // Une ouverture est aussi une occasion de rafraîchir le détail.
            if (!root.ouvert) root.rafraichir(true)
        }
    }

    // ── carte de survol ──────────────────────────────────────────────────────
    // Sans attrapeur de clic et sans focus : elle ne doit rien intercepter, sinon
    // effleurer l'applet suffirait à bloquer la barre.
    //
    // Sur une barre de côté, un applet QML n'affiche que son icône (le reste est
    // découpé) : son nom se lit au survol. Un `HoverHandler` et non une
    // `MouseArea` — il ne prend jamais le clic, qui doit rester à l'applet.
    readonly property bool nomAuSurvol: estQml && verticale && survolNom.hovered
    HoverHandler {
        id: survolNom
        enabled: root.estQml && root.verticale
    }

    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "gauche"
        id: carte
        // Sans marge, l'ajustement colle le volet au bord de l'écran : un panneau
        // posé pile sur la bordure se lit mal, et son ombre disparaît. La marge
        // est un type `Margins` (quatre entiers), pas un nombre : l'assigner d'un
        // entier échoue à l'exécution — « Cannot assign value 14 to property
        // margins » — sans que qmllint le voie.
        // Rien en haut : la marge de 14 px décalait *tous* les popups de quatorze
        // pixels vers le bas, et c'est ce qui les faisait paraître « trop bas » par
        // rapport au centre de notifications. Mesuré : ancre 42 + marge 14 = 56.
        implicitWidth: Math.ceil(colonneCarte.implicitWidth + Theme.space4 * 2)
        implicitHeight: Math.ceil(colonneCarte.implicitHeight + Theme.space3 * 2)
        color: "transparent"
        // Le nom seul ne dépend pas du réglage de carte de survol : sur une barre
        // de côté, c'est le seul moyen d'identifier un applet réduit à son icône.
        visible: !root.ouvert && (root.nomAuSurvol
                                  || (root.carteSurvol && root.survol.length > 0))

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Qt.alpha(Theme.accent, 0.55)
            border.width: 1

            Column {
                id: colonneCarte
                anchors.centerIn: parent
                spacing: Math.round(5 * root.echelle)

                Text {
                    text: String(root.applet.nom || "")
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(Theme.textXs * 0.85 * root.echelle)
                }

                // Deux colonnes plutôt qu'une grille : chaque colonne prend la
                // largeur de son texte le plus long, les lignes restent alignées,
                // et « Ollama Cloud » n'est plus tronqué.
                Row {
                    spacing: Math.round(10 * root.echelle)

                    Column {
                        spacing: Math.round(3 * root.echelle)

                        Repeater {
                            model: root.survol
                            delegate: Text {
                                required property var modelData
                                text: String(modelData.nom || "")
                                color: Qt.alpha(Theme.fg, 0.75)
                                font.pixelSize: Math.round(Theme.textXs * root.echelle)
                            }
                        }
                    }

                    Column {
                        spacing: Math.round(3 * root.echelle)

                        Repeater {
                            model: root.survol
                            delegate: Text {
                                required property var modelData
                                text: String(modelData.valeur || "")
                                color: modelData.alerte ? Theme.warn : Theme.fg
                                font.pixelSize: Math.round(Theme.textXs * root.echelle)
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── popup ────────────────────────────────────────────────────────────────
    // Le contenu vient du catalogue (`popup`) : l'applet « comptes » charge le
    // composant des widgets de compte, donc le détail n'est pas réécrit ici.
    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "gauche"
        id: fenetre
        // Sans marge, l'ajustement colle le volet au bord de l'écran : un panneau
        // posé pile sur la bordure se lit mal, et son ombre disparaît. La marge
        // est un type `Margins` (quatre entiers), pas un nombre : l'assigner d'un
        // entier échoue à l'exécution — « Cannot assign value 14 to property
        // margins » — sans que qmllint le voie.
        // Rien en haut : la marge de 14 px décalait *tous* les popups de quatorze
        // pixels vers le bas, et c'est ce qui les faisait paraître « trop bas » par
        // rapport au centre de notifications. Mesuré : ancre 42 + marge 14 = 56.
        implicitWidth: Math.ceil(chargeur.implicitWidth + Theme.space4 * 2)
        implicitHeight: Math.ceil(chargeur.implicitHeight + Theme.space4 * 2)
        color: "transparent"
        // Un popup externe est dessiné par son îlot : cette fenêtre reste fermée.
        visible: root.ouvert && !root.popupExterne && !root.estQml

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Loader {
                id: chargeur
                anchors.centerIn: parent
                // Source **relative** : une URL absolue (`"file://" +
                // Quickshell.shellPath(...)`) fait recompiler le composant dans
                // un second moteur QML, et un singleton appartenant à son moteur,
                // le popup reçoit sa **propre** instance de `Theme`. Tout ce qu'il
                // y écrit (fermeture après un clic, par exemple) reste alors
                // invisible pour le reste de la coquille, sans aucune erreur.
                // C'est le même piège que le Loader d'applet, corrigé ici aussi ;
                // mesuré : `file://` donnait Theme_QMLTYPE_4, le relatif donne
                // l'instance de la racine.
                // Un panneau autonome (calendrier, média) a son propre Loader :
                // ce composant-ci ne charge que les popups de contenu, qui sont
                // enveloppés dans la fenêtre ci-dessus. Charger les deux ici
                // revenait à instancier le panneau deux fois, et à lui écrire
                // `options`, qu'il ne déclare pas.
                source: (root.popupExterne || String(root.applet.popup || "") === "")
                        ? "" : String(root.applet.popup)
                onLoaded: {
                    if (!item) return
                    item.options = {
                        text_scale: root.applet.text_scale,
                        entete: true,
                        services: (root.applet.options || {}).services
                    }
                    item.widgetId = ""
                    // Le popup a besoin de savoir qu'il est ouvert : sans cela son
                    // timer de relecture (approbations, états vivants) ne démarre
                    // pas, et le panneau reste figé sur l'état de l'ouverture.
                    if ("ouvert" in item) item.ouvert = Qt.binding(function () { return root.ouvert })
                    if ("notifier" in item) item.notifier = function () { root.rafraichir(true) }
                }
            }
        }
    }

    // ── panneau autonome (calendrier, média) ─────────────────────────────────
    // Ces deux composants apportent leur propre `PopupWindow`, leur attrapeur de
    // clic extérieur et leur touche Échap : l'applet ne leur donne que son ancre
    // (lui-même) et son état d'ouverture. C'est ce qui les fait suivre l'applet
    // sur n'importe quelle barre — avant, l'îlot central les possédait, et
    // poser l'applet sur un côté ouvrait son panneau sous la barre du haut.
    //
    // `ancre` et `ouvert` sont posés après la création : les panneaux ne les
    // déclarent donc pas `required`, et n'affichent leur fenêtre qu'une fois
    // l'ancre connue.
    Loader {
        id: chargeurPanneau
        source: (root.popupExterne && String(root.applet.popup || "") !== "")
                ? String(root.applet.popup) : ""
        onLoaded: {
            if (!item) return
            item.ancre = Qt.binding(() => root)
            item.ouvert = Qt.binding(() => root.ouvert)
        }
    }

    // L'attrapeur n'est armé qu'une fois la fenêtre réellement affichée : armé
    // trop tôt, Hyprland le libère aussitôt (il vise une surface pas encore
    // mappée) et le popup se refermait dans la même seconde.
    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) delaiGrab.restart()
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    HyprlandFocusGrab {
        // Rien à saisir ici : le popup externe a déjà son propre attrapeur.
        active: root.ouvert && !root.popupExterne && root.pretGrab && !root.estQml
        // La barre fait partie du grab (voir `Theme.fenetresGrab`).
        windows: Theme.fenetresGrab(fenetre, root)
        onCleared: {
            if (Theme.activePopup === "applet:" + root.appletId) Theme.activePopup = ""
        }
    }
}
