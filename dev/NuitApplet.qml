import QtQuick
import "."
import Quickshell
import Quickshell.Io

// APPLET MODE NUIT — filtre chaud d'écran (séparé de la luminosité).
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    property bool nuitAllumee: false
    property int nuitTemperature: 4000
    property bool nuitPlage: false

    implicitWidth: iconeNuit.implicitWidth
    implicitHeight: iconeNuit.implicitHeight

    Component.onCompleted: root.majNuitObj(SystemServices.nuitEtat)

    Connections {
        target: SystemServices
        function onNuitEtatChanged() {
            root.majNuitObj(SystemServices.nuitEtat)
        }
    }

    function majNuitObj(d) {
        if (!d || typeof d !== "object" || Object.keys(d).length === 0) return
        root.nuitAllumee = d.allume === true
        if (typeof d.temperature === "number") root.nuitTemperature = d.temperature
        root.nuitPlage = d.plage === true
    }

    function majNuit(txt) {
        try {
            const d = JSON.parse(txt.trim())
            if (d && typeof d === "object") {
                SystemServices.nuitEtat = d
                root.majNuitObj(d)
            }
        } catch (e) { /* réponse partielle : on garde l'état précédent */ }
    }

    function basculerNuit() {
        nuitAction.command = [Quickshell.shellPath("core/as-core"), "nuit", "basculer"]
        nuitAction.running = true
    }

    Process {
        id: nuitAction
        stdout: StdioCollector {
            onStreamFinished: root.majNuit(text)
        }
    }

    Icon {
        id: iconeNuit
        anchors.centerIn: parent
        glyph: "weather-night"
        size: root.tailleIcone
        color: root.nuitAllumee ? Theme.accent : Theme.fg
        opacityLevel: root.nuitAllumee ? 1 : (root.nuitPlage ? 0.75 : 0.5)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.basculerNuit()
    }
}
