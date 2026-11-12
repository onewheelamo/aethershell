import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET VOLUME — le son du haut-parleur par défaut, et son curseur.
//
// Composant QML (`genre: "qml"` au catalogue) : il n'y a rien à interroger à
// distance, juste un état vivant et un aller-retour avec WirePlumber. Il porte
// donc sa propre fenêtre, son propre attrapeur de clic et sa propre lecture —
// contrairement aux applets « service », qui reçoivent un contrat JSON.
//
// La valeur est relue toutes les 1,5 s : le volume change aussi par les touches
// du clavier, et une barre qui ment sur le volume est pire qu'une barre absente.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    // Barre de côté : une seule icône, agrandie, et pas de texte — une valeur
    // coupée au milieu se lit mal. Le nom de l'applet est au survol, le détail
    // dans le popup. `Applet.qml` pose la propriété si elle existe.
    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    property int pourcent: 0
    property bool muet: false
    property bool pret: false

    readonly property bool ouvert: Theme.activePopup === "applet:volume"
    readonly property real lissage: echelle

    implicitWidth: barre.implicitWidth
    implicitHeight: barre.implicitHeight

    function icone() {
        if (muet || pourcent === 0) return "volume-off"
        if (pourcent < 34) return "volume-low"
        if (pourcent < 67) return "volume-medium"
        return "volume-high"
    }

    function lire() {
        lecture.running = false
        lecture.running = true
    }

    function regler(pct) {
        pourcent = Math.max(0, Math.min(100, Math.round(pct)))
        reglage.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                           (pourcent / 100).toFixed(2)]
        reglage.running = true
    }

    function basculerMuet() {
        reglage.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        reglage.running = true
        muet = !muet
    }

    Component.onCompleted: root.lire()

    // Synchronisation événementielle lors des modifications de volume clavier (OSD)
    Connections {
        target: Theme
        function onVolumeUpdated() {
            root.lire()
        }
    }

    // Timer au repos : 10 s suffisent en filet de sécurité si un programme
    // change le volume sans passer par les touches matérielles ou la molette
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.lire()
    }

    // « Volume: 0.50 » ou « Volume: 0.50 [MUTED] ».
    Process {
        id: lecture
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                const m = t.match(/Volume:\s*([0-9.]+)/)
                if (!m) return
                root.pourcent = Math.round(parseFloat(m[1]) * 100)
                root.muet = t.indexOf("MUTED") >= 0
                root.pret = true
            }
        }
    }

    Process {
        id: reglage
        onExited: root.lire()
    }

    Row {
        id: barre
        spacing: Math.max(4, Math.round(Theme.space2 * root.echelle))

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.icone()
            size: root.tailleIcone
            color: root.muet ? Theme.warn : Theme.fg
            opacityLevel: root.pret ? 0.92 : 0.4
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.verticale
            text: root.pret ? root.pourcent + " %" : ""
            color: root.muet ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    // Même grammaire que l'ancien bloc de droite : clic gauche = panneau,
    // clic droit = muet, molette = pas de 5 % avec l'OSD. L'applet remplace
    // l'ancien indicateur, il ne doit pas appauvrir le geste.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.basculerMuet()
                Theme.showOsd("volume", root.muet ? 0 : root.pourcent)
            } else {
                Theme.togglePopup("applet:volume")
            }
        }
        onWheel: wheel => {
            const pas = wheel.angleDelta.y > 0 ? 5 : -5
            root.regler(root.pourcent + pas)
            Theme.showOsd("volume", root.pourcent)
        }
    }

    // ── popup ────────────────────────────────────────────────────────────────
    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) { root.lire(); delaiGrab.restart() }
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "centre"
        id: fenetre
        implicitWidth: Math.round(240 * root.echelle)
        implicitHeight: colonne.implicitHeight + 28
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: colonne
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 10

                Row {
                    width: colonne.width
                    spacing: 8

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.icone()
                        size: Theme.iconSm
                        color: root.muet ? Theme.warn : Theme.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Volume"
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pret ? (root.muet ? "muet" : root.pourcent + " %") : "—"
                        color: root.muet ? Theme.warn : Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.textXs
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    id: piste
                    width: colonne.width
                    height: 12
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: Math.max(0, Math.min(1, root.pourcent / 100)) * parent.width
                        height: parent.height
                        radius: Theme.globalRadius
                        color: root.muet ? Theme.warn : Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function appliquer(mx) {
                            root.regler(Math.max(0, Math.min(1, mx / piste.width)) * 100)
                        }
                        onPressed: mouse => appliquer(mouse.x)
                        onPositionChanged: mouse => { if (pressed) appliquer(mouse.x) }
                    }
                }

                Row {
                    width: colonne.width
                    spacing: 6

                    Rectangle {
                        width: 64
                        height: 22
                        radius: 5
                        color: muetBouton.containsMouse ? Qt.alpha(Theme.accent, 0.22) : "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.25)

                        Text {
                            anchors.centerIn: parent
                            text: root.muet ? "Rétablir" : "Muet"
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            id: muetBouton
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.basculerMuet()
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: root.ouvert && root.pretGrab
        windows: Theme.fenetresGrab(fenetre, root)
        onCleared: if (Theme.activePopup === "applet:volume") Theme.activePopup = ""
    }
}
