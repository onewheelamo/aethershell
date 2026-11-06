import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// SYSTÈME — la version « bureau » de l'applet du même nom.
//
// Même source : `core/systeme_applet.py --force`, qui interroge /proc/stat,
// /proc/meminfo, nvidia-smi et coretemp. L'applet n'en garde qu'une valeur dans
// la barre ; ce widget montre les quatre mesures, leur jauge et le détail que le
// contrat transporte déjà (`detail`) — Go de RAM, VRAM et température du GPU.
//
// Une sonde absente disparaît de `barres` au lieu de casser l'affichage : une
// machine sans NVIDIA n'affiche simplement pas de ligne GPU.
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

    readonly property var barres: {
        if (donnees && donnees.compact && donnees.compact.barres)
            return donnees.compact.barres
        return []
    }
    readonly property var detail: (donnees && donnees.detail) ? donnees.detail : ({})

    // Une ligne de précision sous la jauge. Les deux températures et la VRAM sont
    // demandées explicitement : elles vivent ici en clair, pas seulement dans une
    // couleur de jauge.
    function precision(cle) {
        const d = detail || ({})
        if (cle === "cpu") {
            const t = d.temp && d.temp.cpu ? Math.round(d.temp.cpu) + "°" : ""
            return t
        }
        if (cle === "ram" && d.ram && d.ram.totale_go)
            return formatGo(d.ram.utilisee_go) + " / " + formatGo(d.ram.totale_go) + " Go"
        if (cle === "gpu") {
            let t = ""
            if (d.gpu && d.gpu.vram_totale_go)
                t = formatGo(d.gpu.vram_go) + " / " + formatGo(d.gpu.vram_totale_go) + " Go"
            if (d.gpu && d.gpu.temperature)
                t += (t !== "" ? " · " : "") + Math.round(d.gpu.temperature) + "°"
            return t
        }
        if (cle === "temp" && d.temp && d.temp.cpu)
            return "paquet " + Math.round(d.temp.cpu) + "°"
        return ""
    }

    function formatGo(v) {
        const n = Number(v)
        if (!isFinite(n)) return "—"
        return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + ""
    }

    // Les trois niveaux du contrat : ok / attention / critique (voir _niveau()
    // dans systeme_applet.py).
    function couleurNiveau(niveau) {
        if (niveau === "critique") return Theme.error
        if (niveau === "attention") return Theme.accentMuted
        return Theme.accent
    }

    function rafraichir() {
        proc.command = ["python3", Quickshell.shellPath("core/systeme_applet.py"), "--force"]
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 3000
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

    implicitWidth: colonne.implicitWidth
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        spacing: 7

        Text {
            text: "système"
            color: Qt.alpha(Theme.fg, 0.42)
            font.pixelSize: Math.round(11 * root.echelle)
            font.letterSpacing: 0.4
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

        Repeater {
            model: root.barres

            Column {
                required property var modelData
                readonly property string precisionTexte: root.precision(modelData.cle)
                // Pas de `width: colonne.width` : la colonne se dimensionne sur
                // ses enfants, la lier à eux referme la boucle et l'écrase à 0.
                spacing: 1

                Row {
                    spacing: 6

                    IconSvg {
                        anchors.verticalCenter: parent.verticalCenter
                        nom: String(modelData.icone || modelData.cle)
                        size: Math.round(15 * root.echelle)
                        couleur: root.couleurNiveau(modelData.niveau)
                        opacite: 0.9
                    }

                    // Piste : elle garde une largeur fixe pour que les jauges
                    // restent alignées d'une ligne à l'autre, même si la valeur
                    // texte passe de 3 % à 100 %.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(92 * root.echelle)
                        height: Math.round(5 * root.echelle)
                        radius: height / 2
                        color: Qt.alpha(Theme.fg, 0.13)

                        Rectangle {
                            width: Math.max(2, parent.width * Math.min(100, Math.max(0,
                                       Number(modelData.remplissage) || 0)) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: root.couleurNiveau(modelData.niveau)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.texte || "")
                        color: Theme.fg
                        font.pixelSize: Math.round(13 * root.echelle)
                        font.features: { "tnum": 1 }
                        style: Text.Raised
                        styleColor: Qt.alpha(Theme.bg, 0.55)
                    }
                }

                Text {
                    visible: precisionTexte !== ""
                    text: precisionTexte
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(10 * root.echelle)
                    leftPadding: Math.round(22 * root.echelle)
                }
            }
        }

        Text {
            visible: root.charge && root.barres.length === 0
            text: "aucune sonde"
            color: Qt.alpha(Theme.fg, 0.42)
            font.pixelSize: Math.round(9 * root.echelle)
        }
    }
}
