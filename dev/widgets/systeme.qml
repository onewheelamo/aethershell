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

    readonly property var donnees: Theme.systemeData
    readonly property bool charge: Theme.systemeCharge

    readonly property var barres: {
        if (donnees && donnees.compact && donnees.compact.barres)
            return donnees.compact.barres
        return []
    }
    readonly property var detail: (donnees && donnees.detail) ? donnees.detail : ({})

    // Jauges : option d'applet (case « jauge », vrai par défaut). Éteinte, le
    // widget garde l'icône et la valeur — utile quand on préfère un chiffre net
    // sur un fond chargé.
    readonly property bool jauge: options.jauge === undefined ? true : options.jauge === true

    // Les lignes affichées : les mesures du contrat, plus deux jauges dérivées
    // que le service ne renvoie pas sous forme de barres — VRAM utilisée et
    // température du GPU. Une température ou une VRAM absente (pas de NVIDIA)
    // n'ajoute simplement pas sa ligne.
    readonly property var lignes: {
        const d = detail || ({})
        const out = []
        for (let i = 0; i < barres.length; ++i) {
            const b = barres[i]
            const ligne = {
                cle: String(b.cle || ""),
                nom: String(b.nom || b.cle || ""),
                icone: String(b.icone || b.cle || ""),
                texte: String(b.texte || ""),
                remplissage: Number(b.remplissage) || 0,
                niveau: String(b.niveau || "ok"),
                precision: ""
            }
            if (ligne.cle === "cpu" && d.temp && d.temp.cpu)
                ligne.precision = Math.round(d.temp.cpu) + "°"
            else if (ligne.cle === "ram" && d.ram && d.ram.totale_go)
                ligne.precision = formatGo(d.ram.utilisee_go) + " / " + formatGo(d.ram.totale_go) + " Go"
            // « temp » garde sa jauge, sans la ligne « paquet » : la température
            // du CPU est déjà annoncée sous la ligne CPU.
            out.push(ligne)
        }

        if (d.gpu && Number(d.gpu.vram_totale_go) > 0) {
            const part = 100 * (Number(d.gpu.vram_go) || 0) / Number(d.gpu.vram_totale_go)
            // Le ratio plutôt que le pourcentage : sur une VRAM, « 1,5/12 Go »
            // dit plus que « 12 % », et la jauge donne déjà la proportion.
            out.push({
                cle: "vram", nom: "VRAM", icone: "ram",
                texte: formatGo(d.gpu.vram_go) + "/" + formatGo(d.gpu.vram_totale_go) + " Go",
                remplissage: part,
                niveau: part >= 92 ? "critique" : (part >= 80 ? "attention" : "ok"),
                precision: ""
            })
        }

        if (d.gpu && Number(d.gpu.temperature) > 0) {
            const chaleur = Number(d.gpu.temperature)
            out.push({
                cle: "gputemp", nom: "GPU", icone: "temp",
                texte: Math.round(chaleur) + "°",
                // Même échelle que la température CPU : 85 °C = jauge pleine.
                remplissage: Math.min(100, 100 * chaleur / 85),
                niveau: chaleur >= 85 ? "critique" : (chaleur >= 70 ? "attention" : "ok"),
                precision: ""
            })
        }

        return out
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

    function rafraichir(force) {
        Theme.metriquesActif = true
    }

    Component.onCompleted: Theme.metriquesActif = true

    implicitWidth: colonne.implicitWidth
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        spacing: 7

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.rafraichir(true)
        }

        Repeater {
            model: root.lignes

            Column {
                required property var modelData
                readonly property string precisionTexte: String(modelData.precision || "")
                // Pas de `width: colonne.width` : la colonne se dimensionne sur
                // ses enfants, la lier à eux referme la boucle et l'écrase à 0.
                spacing: 1

                Row {
                    spacing: 6

                    IconSvg {
                        anchors.verticalCenter: parent.verticalCenter
                        nom: String(modelData.icone || modelData.cle)
                        size: Math.round(18 * root.echelle)
                        couleur: root.couleurNiveau(modelData.niveau)
                        opacite: 0.9
                    }

                    // Piste : elle garde une largeur fixe pour que les jauges
                    // restent alignées d'une ligne à l'autre, même si la valeur
                    // texte passe de 3 % à 100 %.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.jauge
                        width: Math.round(112 * root.echelle)
                        height: Math.round(6 * root.echelle)
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
                        font.pixelSize: Math.round(16 * root.echelle)
                        font.features: { "tnum": 1 }
                        style: Text.Raised
                        styleColor: Qt.alpha(Theme.bg, 0.55)
                    }
                }

                Text {
                    visible: precisionTexte !== ""
                    text: precisionTexte
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(12 * root.echelle)
                    leftPadding: Math.round(26 * root.echelle)
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
