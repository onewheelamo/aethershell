import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Fond de bureau glissant : alternatif léger à `FondProfondeur.qml` lorsque
// la parallaxe n'est pas activée. Le fond d'écran courant (`awww`) glisse
// horizontalement au changement de bureau sans jamais découvrir de bord nu.
PanelWindow {
    id: fenetre

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    aboveWindows: false
    visible: actif && fond.status === Image.Ready
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.namespace: "shell-fond-glissement"

    readonly property bool actif: !Theme.depthWallpaper
                                  && Theme.wallpaperSlide
                                  && ShellState.wallpaperCourant !== ""
    readonly property int bureau: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 1
    readonly property int pas: 28

    Image {
        id: fond
        width: fenetre.width + 3 * fenetre.pas
        height: fenetre.height
        x: -((Math.max(1, fenetre.bureau) - 1) % 4) * fenetre.pas
        y: 0
        source: fenetre.actif ? ("file://" + ShellState.wallpaperCourant) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        Behavior on x { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    }
}
