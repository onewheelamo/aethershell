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
    WlrLayershell.namespace: "shell-fond-profondeur"

    // Le bureau courant donne le pas de parallaxe : chaque changement décale les
    // calques d'un cran. Hors animation continue, le fond ne bouge pas seul.
    readonly property int bureau: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1

    // Fond courant, lu auprès d'awww : c'est lui qui choisit le jeu de calques.
    property string fondCourant: ""
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
    readonly property string dossierSpecifique: fenetre.nomFond === "" ? dossierBase
                                                                     : fenetre.dossierBase + fenetre.nomFond + "/"
    // Vrai quand le jeu propre au fond courant n'existe pas : on retombe alors
    // sur le dossier commun. La bascule se fait à la première image en erreur,
    // et se réarme quand le fond d'écran change.
    property bool repli: false
    readonly property string dossier: repli ? dossierBase : dossierSpecifique

    readonly property bool assetsPresents: lointain.status === Image.Ready
                                           && moyen.status === Image.Ready
                                           && proche.status === Image.Ready

    onNomFondChanged: fenetre.repli = false

    Process {
        id: sondeFond
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) fenetre.fondCourant = m[1]
            }
        }
    }

    // awww ne prévient pas quand le fond change : on le lui redemande, mais
    // seulement quand l'option est active. 30 s de latence, pour deux mille
    // interrogations par jour au lieu de dizaines de milliers.
    Timer {
        interval: 30000
        repeat: true
        running: Theme.depthWallpaper
        onTriggered: if (!sondeFond.running) sondeFond.running = true
    }

    // Une option allumée sans assets ne dessine rien : le dire dans le journal
    // plutôt que de laisser croire à une panne.
    onVisibleChanged: {
        if (!visible && Theme.depthWallpaper && !assetsPresents)
            console.warn("fond en profondeur : aucun jeu de trois PNG dans " + dossier)
    }

    // `facteur` = pixels de décalage par bureau ; la marge d'agrandissement est
    // calculée pour que le décalage maximal ne découvre jamais un bord.
    function decalage(facteur) {
        return (fenetre.bureau - 1) * facteur
    }

    Image {
        id: lointain
        width: fenetre.width + 24
        height: fenetre.height + 24
        x: Math.round((fenetre.width - width) / 2) - fenetre.decalage(4)
        y: Math.round((fenetre.height - height) / 2)
        // Rien n'est demandé tant que le fond courant n'est pas connu :
        // sinon le repli se déclenche sur un chemin incomplet.
        source: fenetre.nomFond === "" ? "" : "file://" + fenetre.dossier + "1-lointain.png"
        onStatusChanged: if (status === Image.Error && !fenetre.repli) fenetre.repli = true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: moyen
        width: fenetre.width + 36
        height: fenetre.height + 36
        x: Math.round((fenetre.width - width) / 2) - fenetre.decalage(7)
        y: Math.round((fenetre.height - height) / 2)
        // Rien n'est demandé tant que le fond courant n'est pas connu :
        // sinon le repli se déclenche sur un chemin incomplet.
        source: fenetre.nomFond === "" ? "" : "file://" + fenetre.dossier + "2-moyen.png"
        onStatusChanged: if (status === Image.Error && !fenetre.repli) fenetre.repli = true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: proche
        width: fenetre.width + 52
        height: fenetre.height + 52
        x: Math.round((fenetre.width - width) / 2) - fenetre.decalage(10)
        y: Math.round((fenetre.height - height) / 2)
        // Rien n'est demandé tant que le fond courant n'est pas connu :
        // sinon le repli se déclenche sur un chemin incomplet.
        source: fenetre.nomFond === "" ? "" : "file://" + fenetre.dossier + "3-proche.png"
        onStatusChanged: if (status === Image.Error && !fenetre.repli) fenetre.repli = true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }
}
