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
    readonly property int cadenceMin: {
        const v = Number(applet.cadence)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
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
    // Mode jauge : plusieurs mesures, une mini-barre chacune (applet système).
    readonly property var barres: (ok && ligne.barres && ligne.barres.length)
                                  ? ligne.barres : []
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

    // Valeur vide : l'applet s'efface au lieu d'afficher un tiret (cas du
    // morceau : rien ne joue).
    readonly property bool sansValeur: ok && valeur === ""
    visible: !sansValeur

    // Un seul popup ouvert à la fois, et il est identifié par son applet : deux
    // applets ne peuvent donc pas s'ouvrir l'un sur l'autre.
    readonly property bool ouvert: popupExterne
                                   ? (Theme.activePopup === popupCle)
                                   : (Theme.activePopup === "applet:" + appletId)

    implicitWidth: contenu.implicitWidth
    implicitHeight: contenu.implicitHeight

    function rafraichir(force) {
        if (root.service === "" || root.occupe) return
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

    onServiceChanged: if (root.service !== "") root.rafraichir(false)
    Component.onCompleted: if (root.service !== "") root.rafraichir(false)

    Timer {
        interval: root.cadenceMin * 60000
        repeat: true
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
            glyph: String(root.applet.icone || "circle")
            size: Math.max(10, Math.round(Theme.iconSm * root.echelle))
            color: root.alerte ? Theme.warn : Theme.fg
            opacityLevel: root.ok ? 0.92 : 0.45
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.valeur
            visible: root.barres.length === 0 && text !== ""
            color: root.alerte ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const cle = root.popupExterne ? root.popupCle : ("applet:" + root.appletId)
            Theme.activePopup = root.ouvert ? "" : cle
            // Une ouverture est aussi une occasion de rafraîchir le détail.
            if (!root.ouvert) root.rafraichir(true)
        }
    }

    // ── popup ────────────────────────────────────────────────────────────────
    // Le contenu vient du catalogue (`popup`) : l'applet « comptes » charge le
    // composant des widgets de compte, donc le détail n'est pas réécrit ici.
    PopupWindow {
        id: fenetre
        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
        implicitWidth: Math.ceil(chargeur.implicitWidth + Theme.space4 * 2)
        implicitHeight: Math.ceil(chargeur.implicitHeight + Theme.space4 * 2)
        color: "transparent"
        // Un popup externe est dessiné par son îlot : cette fenêtre reste fermée.
        visible: root.ouvert && !root.popupExterne

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Loader {
                id: chargeur
                anchors.centerIn: parent
                source: String(root.applet.popup || "") === ""
                        ? "" : "file://" + Quickshell.shellPath(root.applet.popup)
                onLoaded: {
                    if (!item) return
                    item.options = {
                        text_scale: root.applet.text_scale,
                        entete: true,
                        services: (root.applet.options || {}).services
                    }
                    item.widgetId = ""
                }
            }
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
        active: root.ouvert && !root.popupExterne && root.pretGrab
        windows: [fenetre]
        onCleared: {
            if (Theme.activePopup === "applet:" + root.appletId) Theme.activePopup = ""
        }
    }
}
