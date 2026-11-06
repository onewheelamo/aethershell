import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// DISQUES — la version « bureau » de l'applet du même nom.
//
// Même source (core/disques_applet.py), même sélection : le service lit le
// registre de l'applet quand on ne lui passe pas d'options, donc cocher un
// système de fichiers dans le panneau change la barre **et** cette carte.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var donnees: ({})
    property bool charge: false

    readonly property var montages: (donnees.detail && donnees.detail.montages) || []
    readonly property var disques: (donnees.detail && donnees.detail.disques) || []
    readonly property int pourcent: {
        const c = donnees.compact
        if (!c) return 0
        if (c.barres && c.barres.length > 0) return Number(c.barres[0].valeur) || 0
        return Number(String(c.valeur || "0").replace("%", "").trim()) || 0
    }

    function couleurNiveau(niveau) {
        if (niveau === "critique") return Theme.error
        if (niveau === "attention") return Theme.accentMuted
        return Theme.accent
    }

    function niveauDe(pct) {
        return pct >= 92 ? "critique" : (pct >= 80 ? "attention" : "ok")
    }

    // Go → « 1,1 To » au-delà de 1000, sinon « 384 Go ».
    function taille(v) {
        const n = Number(v)
        if (!isFinite(n)) return "—"
        if (n >= 1000) return (Math.round(n / 100) / 10) + " To"
        return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + " Go"
    }

    function rafraichir() {
        proc.command = ["python3", Quickshell.shellPath("core/disques_applet.py"), "--force"]
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.donnees = JSON.parse(text.trim())
                } catch (e) {
                    root.donnees = ({})
                }
                root.charge = true
            }
        }
    }

    implicitWidth: Math.round(268 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(7 * echelle)

        // ── jauge globale de la sélection ───────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Math.round(46 * root.echelle)
                height: Math.round(7 * root.echelle)
                radius: height / 2
                color: Qt.alpha(Theme.fg, 0.13)

                Rectangle {
                    width: Math.max(3, parent.width * Math.min(100, root.pourcent) / 100)
                    height: parent.height
                    radius: parent.radius
                    color: root.couleurNiveau(root.niveauDe(root.pourcent))
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.pourcent + " %"
                color: Theme.fg
                font.pixelSize: Math.round(15 * root.echelle)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        // ── systèmes de fichiers de la sélection ────────────────────────────
        Repeater {
            model: root.montages

            Column {
                required property var modelData
                width: colonne.width
                spacing: 1

                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        width: parent.width - Math.round(96 * root.echelle)
                        text: String(modelData.montage || "")
                        color: Theme.fg
                        font.pixelSize: Math.round(11.5 * root.echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: Math.round(96 * root.echelle)
                        horizontalAlignment: Text.AlignRight
                        text: root.taille(modelData.utilise_go) + " / "
                              + root.taille(modelData.taille_go)
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Math.round(10 * root.echelle)
                        font.features: { "tnum": 1 }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.round(3 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.10)

                    Rectangle {
                        width: Math.max(2, parent.width * Math.min(100, Number(modelData.pourcent) || 0) / 100)
                        height: parent.height
                        radius: parent.radius
                        color: root.couleurNiveau(modelData.niveau)
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

        // ── disques physiques ───────────────────────────────────────────────
        Repeater {
            model: root.disques

            Row {
                required property var modelData
                width: colonne.width
                spacing: 6

                Text {
                    width: parent.width - Math.round(108 * root.echelle)
                    text: String(modelData.modele || modelData.nom || "")
                    color: Qt.alpha(Theme.fg, 0.85)
                    font.pixelSize: Math.round(10.5 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(108 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(modelData.type || "") + " · " + root.taille(modelData.taille_go)
                          + (modelData.temperature !== undefined
                             ? " · " + modelData.temperature + "°" : "")
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(9.5 * root.echelle)
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            visible: root.charge && root.montages.length === 0
            text: "aucun système de fichiers sélectionné"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(10 * root.echelle)
        }

        // ── utilitaire ──────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: Math.round(26 * echelle)
            radius: Theme.globalRadius
            color: survol.containsMouse ? Theme.accentMuted : Qt.alpha(Theme.accent, 0.14)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.45)

            Text {
                anchors.centerIn: parent
                text: "Gérer les disques"
                color: Theme.fg
                font.pixelSize: Math.round(10.5 * echelle)
                font.bold: true
            }

            MouseArea {
                id: survol
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["gparted"])
            }
        }
    }
}
