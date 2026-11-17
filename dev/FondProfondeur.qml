import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Fond de bureau « en profondeur » : trois calques PNG **avec alpha**, empilés
// sur le fond du démon (awww) et décalés différemment quand on change de bureau
// — parallaxe de quelques pixels, du lointain au proche.
//
// Format décidé le 2026-11-07 : trois PNG découpés avec alpha, 1920×1080. Les
// calques sont transparents : ce qui n'est pas peint laisse voir le fond du
// démon, donc l'image de base reste fournie par awww et rien n'est dupliqué.
// Sans les trois fichiers, la surface ne s'affiche pas — un fond à moitié chargé
// serait pire que le fond du démon.
//
// Les calques suivent le fond d'écran courant : le dossier est
// `<dossier de fonds>/profondeur/<nom du fond>/`, avec repli sur
// `<dossier de fonds>/profondeur/` pour un jeu commun à tous les fonds. Changer
// de fond d'écran ne *recalcule* donc rien (QML ne découpe pas une image) ; le
// shell relit le jeu correspondant, et s'il n'existe pas il n'affiche rien.
//
// Limite de plateforme, à ne pas oublier : « les îlots entre les calques » n'est
// pas réalisable. layer-shell n'offre que background < bottom < fenêtres < top <
// overlay ; un calque ne peut pas passer entre la barre et les fenêtres. Le fond
// est en `background`, la barre au-dessus de tout.
PanelWindow {
    id: fenetre

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    aboveWindows: false
    visible: Theme.depthWallpaper && assetsPresents
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Zone exclusive neutre : sans ça, la barre réserve le haut de l'écran et
    // la surface est rétrécie à 1080-46 px. Les images, taillées à la hauteur
    // de la fenêtre, ne couvraient donc pas le fond véritable — d'où la couture
    // visible pile sous la barre.
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "shell-fond-profondeur"

    // Le bureau courant donne le pas de parallaxe : chaque changement décale les
    // calques d'un cran. Hors animation continue, le fond ne bouge pas seul.
    readonly property int bureau: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1

    // Fond courant, partagé par Theme (`awww query`).
    readonly property string fondCourant: Theme.wallpaperCourant
    // Le dossier de fonds vient de style_vars sous forme « $HOME/Images/… » :
    // QML ne développe pas les variables, on les résout ici.
    readonly property string racineFonds: {
        let d = String(Theme.wallpaperDir || "")
        const home = Quickshell.env("HOME") || ""
        if (d.startsWith("$HOME")) d = home + d.slice(5)
        else if (d.startsWith("~")) d = home + d.slice(1)
        return d.replace(/\/?$/, "/")
    }
    readonly property string dossierBase: racineFonds + "profondeur/"
    readonly property string nomFond: {
        const p = String(fenetre.fondCourant)
        if (p === "") return ""
        const base = p.split("/").pop()
        return base.replace(/\.[^.]+$/, "")
    }
    readonly property string dossierSpecifique: fenetre.nomFond === "" ? ""
                                                                      : fenetre.dossierBase + fenetre.nomFond + "/"
    property bool rechargeEnCours: false
    readonly property bool sourcesActives: Theme.depthWallpaper
                                           && fenetre.dossierSpecifique !== ""
                                           && !fenetre.generationEnCours
                                           && !fenetre.rechargeEnCours

    readonly property bool assetsPresents: sourcesActives
                                           && lointain.status === Image.Ready
                                           && moyen.status === Image.Ready
                                           && proche.status === Image.Ready

    onNomFondChanged: {
        fenetre.derniereTentative = ""
        fenetre.rechargerCalques()
    }

    // ── Génération automatique des calques ────────────────────────────────
    // Le jeu manquant est produit par le shell lui-même, depuis le fichier du
    // fond, recadré à la taille de l'écran. Mesuré contre une capture du
    // compositeur : 0,7 d'écart moyen sur 255 — le recadrage LANCZOS du script
    // reproduit le rendu d'awww de très près, ce qui rend la capture inutile.
    property bool generationEnCours: false
    // Un fond dont la génération a échoué n'est pas retenté en boucle.
    property string derniereTentative: ""
    property string generateurFond: ""

    Timer {
        id: veilleCalques
        interval: 1500
        repeat: true
        running: Theme.depthWallpaper && !assetsPresents && !generationEnCours
        onTriggered: {
            // `Error` = les trois PNG n'existent pas ; `Loading` = patience.
            if (lointain.status !== Image.Error) return
            if (fenetre.fondCourant === "" || fenetre.derniereTentative === fenetre.fondCourant) return
            fenetre.derniereTentative = fenetre.fondCourant
            fenetre.generateurFond = fenetre.fondCourant
            fenetre.generationEnCours = true
            generateur.command = ["python3", Quickshell.shellPath("core/parallaxe_layers.py"),
                                  "generate", "--wallpaper", fenetre.fondCourant,
                                  "--out", fenetre.dossierSpecifique,
                                  // Taille de l'**écran**, pas de la fenêtre : la surface
                                  // n'est pas encore créée (elle attend ses calques), donc
                                  // `width` vaut 100 et la génération sortait en 100×100.
                                  "--ecran", (fenetre.screen ? fenetre.screen.width : Screen.width)
                                             + "x" + (fenetre.screen ? fenetre.screen.height : Screen.height),
                                  // Le masque peint à la main, s'il existe, fait foi ;
                                  // le script retombe sur le modèle quand il est absent.
                                  "--masque-de", fenetre.dossierSpecifique + "masque.png"]
            generateur.running = true
            console.log("fond en profondeur : génération des calques pour " + fenetre.fondCourant)
        }
    }

    Process {
        id: generateur
        onRunningChanged: {
            if (running) return
            fenetre.generationEnCours = false
            if (fenetre.generateurFond === fenetre.fondCourant) {
                fenetre.rechargerCalques()
            } else {
                fenetre.derniereTentative = ""
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = String(text).trim()
                if (msg !== "") console.warn("fond en profondeur : " + msg)
            }
        }
    }

    // Le panneau peut régénérer les calques (masque peint) : on relit alors sans
    // attendre, la surface étant déjà à l'écran.
    Connections {
        target: Theme
        function onCalquesVersionChanged() {
            fenetre.derniereTentative = ""
            fenetre.rechargerCalques()
        }
    }

    // Relit les trois fichiers sans casser le binding déclaratif sur `source`.
    function rechargerCalques() {
        fenetre.rechargeEnCours = true
        Qt.callLater(function () {
            fenetre.rechargeEnCours = false
        })
    }

    // Une option allumée sans assets ne dessine rien : le dire dans le journal
    // plutôt que de laisser croire à une panne.
    onVisibleChanged: {
        if (!visible && Theme.depthWallpaper && !assetsPresents && fenetre.dossierSpecifique !== "")
            console.warn("fond en profondeur : aucun jeu de trois PNG dans " + fenetre.dossierSpecifique)
    }

    // `facteur` = pixels de décalage par bureau ; la marge d'agrandissement est
    // calculée pour que le décalage maximal ne découvre jamais un bord.
    function decalage(facteur) {
        // Les calques font exactement la taille de l'écran : un décalage qui
        // grandirait sans fin découvrirait un bord nu au dixième bureau. On
        // boucle donc sur quatre bureaux — retour à l'identique tous les quatre.
        return ((fenetre.bureau - 1) % 4) * facteur
    }

    Image {
        id: lointain
        width: fenetre.width
        height: fenetre.height
        x: fenetre.decalage(0)
        y: 0
        source: fenetre.sourcesActives ? ("file://" + fenetre.dossierSpecifique + "1-lointain.png") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: moyen
        width: fenetre.width
        height: fenetre.height
        x: fenetre.decalage(7)
        y: 0
        source: fenetre.sourcesActives ? ("file://" + fenetre.dossierSpecifique + "2-moyen.png") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: proche
        width: fenetre.width
        height: fenetre.height
        x: fenetre.decalage(10)
        y: 0
        source: fenetre.sourcesActives ? ("file://" + fenetre.dossierSpecifique + "3-proche.png") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }
}
