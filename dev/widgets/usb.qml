import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// PÉRIPHÉRIQUES — ce qui est branché en USB, monté ou non.
//
// Même source que l'applet et le popup : `core/usb_applet.py` (sysfs, udev,
// mountinfo — aucun démon). Un disque monté passe en couleur d'accent : c'est
// celui qu'on vient de brancher et qu'on cherche à ouvrir.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var etat: ({})
    readonly property var disques: root.etat.disques || []

    function tailles(o) {
        const go = Number(o || 0) / 1073741824
        if (go >= 1000) return (go / 1000).toFixed(1).replace(".", ",") + " To"
        if (go >= 1) return Math.round(go) + " Go"
        return Math.round(go * 1000) + " Mo"
    }

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    // Le noyau ne prévient pas quand on branche une clé : demi-minute suffit à
    // ce qu'un disque apparaisse sans scruter le disque en continu.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/usb_applet.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail && d.detail.usb) ? d.detail.usb : d
                } catch (e) {
                    root.etat = ({})
                }
            }
        }
    }

    implicitWidth: Math.round(246 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(5 * echelle)

        Row {
            width: parent.width
            spacing: Math.round(5 * echelle)

            Icon {
                glyph: "usb"
                size: Math.round(11 * echelle)
                color: root.disques.length > 0 && root.etat.montes > 0
                       ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                width: parent.width - Math.round(34 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: root.disques.length > 0
                      ? root.disques.length + (root.disques.length > 1 ? " périphériques" : " périphérique")
                      : "aucun périphérique"
                color: root.disques.length > 0 ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(11 * echelle)
                elide: Text.ElideRight
            }

            Text {
                width: Math.round(28 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root.etat.montes > 0 ? String(root.etat.montes) : ""
                color: Qt.alpha(Theme.accent, 0.8)
                font.pixelSize: Math.round(9.5 * echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── jusqu'à trois disques ───────────────────────────────────────────
        Repeater {
            model: root.disques.slice(0, 3)

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                Rectangle {
                    width: Math.round(4 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.monte ? Theme.accent : Qt.alpha(Theme.fg, 0.4)
                }

                Text {
                    width: parent.width - Math.round(74 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const v = (modelData.volumes || [])[0]
                        const nom = v && v.etiquette ? v.etiquette
                                  : String(modelData.modele || modelData.nom)
                        return nom + (v && v.chiffre && !v.montage ? " (chiffré)" : "")
                    }
                    color: Qt.alpha(Theme.fg, modelData.monte ? 0.9 : 0.7)
                    font.pixelSize: Math.round(9.5 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(44 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.tailles(modelData.taille_o)
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(9 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
