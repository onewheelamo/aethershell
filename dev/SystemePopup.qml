import QtQuick
import "."
import Quickshell
import Quickshell.Io

// POPUP DE L'APPLET SYSTÈME — le détail derrière les quatre jauges.
//
// Deux choses y vivent : les valeurs complètes (RAM en Go, VRAM, température du
// GPU) et le choix des mesures affichées dans la barre. Ce choix s'écrit dans le
// registre (`bar_applets.py option systeme mesures [...]`), donc il survit au
// redémarrage et vaut aussi pour la barre — pas de réglage en double.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property var toutes: ["cpu", "ram", "gpu", "temp"]
    readonly property var noms: ({ cpu: "CPU", ram: "RAM", gpu: "GPU", temp: "Temp" })

    property var mesures: ["cpu", "ram", "gpu", "temp"]
    property var barres: []
    property var detail: ({})

    implicitWidth: Math.round(272 * echelle)
    implicitHeight: colonne.implicitHeight

    function charger() {
        etat.running = false
        etat.running = true
        valeurs.running = false
        valeurs.running = true
    }

    Component.onCompleted: charger()

    // Le choix courant vient du registre, pas d'une copie locale : c'est lui qui
    // fait foi, y compris quand il a été changé depuis le panneau.
    Process {
        id: etat
        command: ["python3", Quickshell.shellPath("core/bar_applets.py"), "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text.trim()) || []
                    for (let i = 0; i < liste.length; i++) {
                        if (liste[i].id !== "systeme") continue
                        const m = (liste[i].options || {}).mesures
                        root.mesures = (m && m.length) ? m : root.toutes
                        return
                    }
                } catch (e) { /* registre illisible : on garde les quatre */ }
            }
        }
    }

    Process {
        id: valeurs
        command: ["python3", Quickshell.shellPath("core/systeme_applet.py"), "--force"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.barres = (d.compact && d.compact.barres) || []
                    root.detail = d.detail || ({})
                } catch (e) {
                    root.barres = []
                }
            }
        }
    }

    Process {
        id: ecriture
        stdout: StdioCollector {
            onStreamFinished: root.charger()
        }
    }

    function basculer(cle) {
        const liste = []
        const actives = root.mesures || []
        for (let i = 0; i < actives.length; i++) if (actives[i] !== cle) liste.push(actives[i])
        // Une mesure éteinte s'ajoute à la fin ; l'ordre de la barre reste
        // celui de la liste, donc CPU, RAM, GPU, Temp.
        if (actives.indexOf(cle) < 0) {
            for (let i = 0; i < root.toutes.length; i++) {
                if (cle === root.toutes[i] || liste.indexOf(root.toutes[i]) >= 0) {
                    if (liste.indexOf(cle) < 0) liste.push(cle)
                }
            }
        }
        if (liste.length === 0) return
        ecriture.command = ["python3", Quickshell.shellPath("core/bar_applets.py"),
                            "option", "systeme", "mesures", JSON.stringify(liste)]
        ecriture.running = true
    }

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(8 * root.echelle)

        Text {
            text: "Système"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * root.echelle)
        }

        // ── choix des mesures ────────────────────────────────────────────────
        Row {
            spacing: 5

            Repeater {
                model: root.toutes

                delegate: Rectangle {
                    id: puce
                    required property string modelData
                    readonly property bool actif: (root.mesures || []).indexOf(modelData) >= 0
                    width: 46
                    height: 20
                    radius: 5
                    color: actif ? Qt.alpha(Theme.accent, 0.18) : "transparent"
                    border.width: 1
                    border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.25)

                    Text {
                        anchors.centerIn: parent
                        text: root.noms[puce.modelData] || puce.modelData
                        color: puce.actif ? Theme.fg : Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Math.round(Theme.textXs * 0.9 * root.echelle)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.basculer(puce.modelData)
                    }
                }
            }
        }

        // ── valeurs détaillées ───────────────────────────────────────────────
        Repeater {
            model: root.barres

            delegate: Row {
                spacing: Math.round(8 * root.echelle)

                IconSvg {
                    anchors.verticalCenter: parent.verticalCenter
                    nom: String(modelData.icone || "")
                    size: Math.round(Theme.iconSm * root.echelle)
                    couleur: modelData.niveau === "critique" ? Theme.error
                             : (modelData.niveau === "attention" ? Theme.warn : Theme.fg)
                    opacite: 0.75
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(34 * root.echelle)
                    text: String(modelData.nom || "")
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.texte || "")
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
                    font.features: { "tnum": 1 }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Ce qui ne tient pas dans une barre : les Go, la VRAM, la
                    // température du GPU.
                    text: {
                        const d = root.detail || ({})
                        if (modelData.cle === "ram" && d.ram)
                            return d.ram.utilisee_go + " / " + d.ram.totale_go + " Go"
                        if (modelData.cle === "gpu" && d.gpu)
                            return d.gpu.temperature + " °C · " + d.gpu.vram_go + " / "
                                   + d.gpu.vram_totale_go + " Go"
                        return ""
                    }
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(Theme.textXs * 0.86 * root.echelle)
                }
            }
        }
    }
}
