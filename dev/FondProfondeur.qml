import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Fond de bureau « en profondeur » : trois calques PNG **avec alpha**, empilés
// sur le fond du démon (awww) et décalés différemment quand on change de bureau
// — parallaxe de quelques pixels, du lointain au proche.
//
// Format décidé le 2026-11-07 : trois PNG découpés avec alpha, 1920×1080, posés
// dans `<dossier de fonds>/profondeur/` sous les noms ci-dessous. Les calques
// sont transparents : ce qui n'est pas peint laisse voir le fond du démon, donc
// l'image de base reste fournie par awww et rien n'est dupliqué. Sans les trois
// fichiers, la surface ne s'affiche pas du tout — un fond à moitié chargé serait
// pire que le fond du démon.
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
    readonly property string dossier: String(Theme.wallpaperDir || "").replace(/\/?$/, "/") + "profondeur/"
    readonly property bool assetsPresents: lointain.status === Image.Ready
                                           && moyen.status === Image.Ready
                                           && proche.status === Image.Ready

    // Une option allumée sans assets ne dessine rien : le dire dans le journal
    // plutôt que de laisser croire à une panne.
    onVisibleChanged: {
        if (!visible && Theme.depthWallpaper && !assetsPresents)
            console.warn("fond en profondeur : les trois PNG sont absents de " + dossier)
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
        source: "file://" + fenetre.dossier + "1-lointain.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: moyen
        width: fenetre.width + 36
        height: fenetre.height + 36
        x: Math.round((fenetre.width - width) / 2) - fenetre.decalage(7)
        y: Math.round((fenetre.height - height) / 2)
        source: "file://" + fenetre.dossier + "2-moyen.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }

    Image {
        id: proche
        width: fenetre.width + 52
        height: fenetre.height + 52
        x: Math.round((fenetre.width - width) / 2) - fenetre.decalage(10)
        y: Math.round((fenetre.height - height) / 2)
        source: "file://" + fenetre.dossier + "3-proche.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }
}
