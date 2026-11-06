import QtQuick
import Quickshell
import Quickshell.Io

// POPUP DISQUES — le détail que la barre ne peut pas dire.
//
// Une ligne par système de fichiers monté hors racine (taille, occupé, libre,
// pourcentage), puis une ligne par disque physique (modèle, type, capacité,
// température quand un capteur existe), et un bouton pour ouvrir l'utilitaire de
// partitionnement. Les données viennent de core/disques_applet.py, la même source
// que la barre et le widget.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    // Renseigné par Applet.qml quand le popup est chargé dans la barre.
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }

    property var montages: []
    property var disques: []
    property string statut: ""
    // Gestionnaire de disques : lu dans core/app_vars.json (« Disk »), la même
    // table que les autres programmes par défaut — un seul endroit à changer.
    property string gestionnaire: "gparted"

    FileView {
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                const p = String(d.Disk || "").trim()
                if (p !== "") root.gestionnaire = p
            } catch (e) { /* fichier en cours d'écriture */ }
        }
    }

    Timer {
        id: lanceurDisques
        interval: 250
        onTriggered: Quickshell.execDetached([root.gestionnaire])
    }


    function charger() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/disques_applet.py"), "--force"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.montages = (d.detail && d.detail.montages) || []
                    root.disques = (d.detail && d.detail.disques) || []
                    root.statut = ""
                } catch (e) {
                    root.montages = []
                    root.disques = []
                    root.statut = "lecture impossible"
                }
            }
        }
    }

    function couleurNiveau(niveau) {
        if (niveau === "critique") return Theme.error
        if (niveau === "attention") return Theme.accentMuted
        return Theme.accent
    }

    function go(valeur) {
        const n = Number(valeur)
        if (!isFinite(n)) return "—"
        if (n >= 1000) return (Math.round(n / 100) / 10) + " To"
        return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + " Go"
    }

    implicitWidth: Math.round(300 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(8 * echelle)

        Text {
            text: "Disques"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
        }

        // ── montages ─────────────────────────────────────────────────────────
        Repeater {
            model: root.montages

            Column {
                required property var modelData
                width: colonne.width
                spacing: 2

                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        width: Math.round(112 * root.echelle)
                        text: String(modelData.montage || "")
                        color: Theme.fg
                        font.pixelSize: Math.round(Theme.textXs * root.echelle)
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(70 * root.echelle)
                        height: Math.round(4 * root.echelle)
                        radius: height / 2
                        color: Qt.alpha(Theme.fg, 0.13)

                        Rectangle {
                            width: Math.max(2, parent.width * Math.min(100, Number(modelData.pourcent) || 0) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: root.couleurNiveau(modelData.niveau)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.pourcent) + " %"
                        color: Theme.fg
                        font.pixelSize: Math.round(Theme.textXs * root.echelle)
                        font.features: { "tnum": 1 }
                    }
                }

                Text {
                    text: root.go(modelData.utilise_go) + " / " + root.go(modelData.taille_go)
                          + "  ·  " + root.go(modelData.libre_go) + " libres  ·  "
                          + String(modelData.fstype || "")
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(Theme.textXs * 0.85 * root.echelle)
                    leftPadding: Math.round(4 * root.echelle)
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

        // ── disques physiques ────────────────────────────────────────────────
        Repeater {
            model: root.disques

            Row {
                required property var modelData
                width: colonne.width
                spacing: 6

                Text {
                    width: colonne.width - Math.round(96 * root.echelle)
                    text: String(modelData.modele || modelData.nom || "")
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.textXs * 0.95 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(96 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(modelData.type || "")
                          + " · " + root.go(modelData.taille_go)
                          + (modelData.temperature !== undefined
                             ? " · " + modelData.temperature + "°" : "")
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(Theme.textXs * 0.85 * root.echelle)
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            visible: root.statut !== ""
            text: root.statut
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Math.round(Theme.textXs * 0.85 * echelle)
        }

        // ── utilitaire ───────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: Math.round(26 * echelle)
            radius: Theme.globalRadius
            color: survol.containsMouse ? Theme.accentMuted : Qt.alpha(Theme.accent, 0.16)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.5)

            Text {
                anchors.centerIn: parent
                text: "Gérer les disques"
                color: Theme.fg
                font.pixelSize: Math.round(Theme.textXs * echelle)
                font.bold: true
            }

            MouseArea {
                id: survol
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // gparted demande ses droits lui-même par polkit : rien à élever ici.
                onClicked: {
                    // Refermer avant de lancer : tant que le panneau garde son
                    // attrapeur de clavier, la fenêtre de gparted (et la demande
                    // polkit qui l'accompagne) s'ouvre sans prendre le focus.
                    Theme.activePopup = ""
                    lanceurDisques.restart()
                }
            }
        }
    }
}
