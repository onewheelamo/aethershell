import QtQuick
import Quickshell
import Quickshell.Wayland

// Fenêtre overlay plein écran partagée (config, spotlight, cheatsheet, overview).
PanelWindow {
    id: win

    property bool open: false
    property string namespaceName: ""
    property int layerLevel: WlrLayer.Overlay
    property int focusMode: WlrKeyboardFocus.Exclusive
    property bool backdropClose: true
    property bool escapeClose: false
    property alias loaderItem: overlayLoader.item
    property alias loaderSource: overlayLoader.source
    property alias loaderActive: overlayLoader.active
    property bool fillLoader: true
    property real loaderWidth: 0
    property real loaderHeight: 0

    signal closeRequested()
    signal contentLoaded(var item)

    visible: win.open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: win.layerLevel
    WlrLayershell.keyboardFocus: win.open ? win.focusMode : WlrKeyboardFocus.None
    WlrLayershell.namespace: win.namespaceName

    Item {
        anchors.fill: parent
        focus: win.escapeClose && win.open
        Keys.onEscapePressed: if (win.escapeClose) win.closeRequested()
    }

    MouseArea {
        anchors.fill: parent
        enabled: win.backdropClose
        onClicked: win.closeRequested()
    }

    Loader {
        id: overlayLoader
        anchors.fill: win.fillLoader ? parent : undefined
        anchors.centerIn: win.fillLoader ? undefined : parent
        width: win.fillLoader ? parent.width : win.loaderWidth
        height: win.fillLoader ? parent.height : win.loaderHeight
        onLoaded: if (item) win.contentLoaded(item)
    }
}
