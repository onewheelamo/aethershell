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
    // Le popup est monté par l'applet ; il connaît son état d'ouverture.
    property bool ouvert: false

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property var toutes: ["cpu", "ram", "gpu", "temp"]
    readonly property var noms: ({ cpu: "CPU", ram: "RAM", gpu: "GPU", temp: "Temp" })

    property var mesures: ["cpu", "ram", "gpu", "temp"]
    // Processus : lus seulement pendant que le panneau est ouvert (l'inspiration
    // nvtop garde cette discipline — rien ne tourne en fond pour ça).
    property var processus: []
    property string tri: "cpu"
    property string message: ""

    function rafraichirProcessus() {
        if (!root.ouvert) return
        procProcessus.running = false
        procProcessus.running = true
    }

    function arreter(pid) {
        geste.pid = pid
        geste.running = false
        geste.running = true
    }

    readonly property var processusTries: {
        const l = (root.processus || []).slice()
        const cle = root.tri
        l.sort(function (a, b) { return (Number(b[cle]) || 0) - (Number(a[cle]) || 0) })
        return l.slice(0, 9)
    }
    property var barres: []
    property var detail: ({})

    // Le service publie la VRAM et la température du GPU dans `detail`, pas sous
    // forme de mesures : on leur ajoute deux lignes ici, avec les mêmes valeurs
    // que le widget de bureau — même source, même présentation.
    readonly property var lignes: {
        const d = detail || ({})
        const actives = (mesures && mesures.length) ? mesures : toutes
        // Les puces de mesure filtrent cette liste, comme elles filtrent la barre :
        // sans ce test, elles ne changeaient que l'applet et paraissaient inertes.
        const out = []
        for (let i = 0; i < barres.length; ++i) {
            if (actives.indexOf(String(barres[i].cle)) >= 0) out.push(barres[i])
        }
        // La VRAM appartient au GPU, la température GPU à la mesure « temp » :
        // éteindre la mesure correspondante éteint aussi sa ligne dérivée.
        if (d.gpu && Number(d.gpu.vram_totale_go) > 0 && actives.indexOf("gpu") >= 0) {
            out.push({
                cle: "vram", nom: "VRAM", icone: "ram", niveau: "ok",
                texte: arrondi(d.gpu.vram_go) + "/" + arrondi(d.gpu.vram_totale_go) + " Go"
            })
        }
        if (d.gpu && Number(d.gpu.temperature) > 0 && actives.indexOf("temp") >= 0) {
            const t = Number(d.gpu.temperature)
            out.push({
                cle: "gputemp", nom: "GPU", icone: "temp",
                niveau: t >= 85 ? "critique" : (t >= 70 ? "attention" : "ok"),
                texte: Math.round(t) + " °C"
            })
        }
        return out
    }

    function arrondi(v) {
        const n = Number(v)
        if (!isFinite(n)) return "—"
        return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + ""
    }

    implicitWidth: Math.round(272 * echelle)
    implicitHeight: colonne.implicitHeight

    function charger() {
        etat.running = false
        etat.running = true
        valeurs.running = false
        valeurs.running = true
    }

    // Un seul gestionnaire de démarrage par objet : deux `Component.onCompleted`
    // dans le même Item lèvent « Property value set multiple times » et le
    // composant ne se crée pas — le panneau s'ouvre alors sur une carte vide.
    Component.onCompleted: { charger(); rafraichirProcessus() }

    // Le choix courant vient du registre, pas d'une copie locale : c'est lui qui
    // fait foi, y compris quand il a été changé depuis le panneau.
    Process {
        id: procProcessus
        command: ["python3", Quickshell.shellPath("core/systeme_applet.py"), "processus"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.processus = d.processus || []
                } catch (e) {
                    root.processus = []
                }
            }
        }
    }

    Timer {
        interval: 3000
        running: root.ouvert
        repeat: true
        onTriggered: root.rafraichirProcessus()
    }

    Process {
        id: geste
        property int pid: 0
        command: ["python3", Quickshell.shellPath("core/systeme_applet.py"), "tuer", String(geste.pid)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.message = d.ok ? "" : String(d.message || "")
                } catch (e) { root.message = "" }
            }
        }
        onExited: root.rafraichirProcessus()
    }

    onOuvertChanged: if (ouvert) rafraichirProcessus()

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
        // Tout filtrer est permis : l'applet reste alors visible (marque `garde`
        // au catalogue) et ce popup reste le chemin pour rallumer une mesure.
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

        // Aucun filtre actif : le popup serait vide, on dit quoi faire.
        Text {
            visible: root.lignes.length === 0
            text: "aucune mesure — cliquez une puce pour en rallumer une"
            color: Qt.alpha(Theme.fg, 0.55)
            font.pixelSize: Math.round(Theme.textXs * 0.9 * root.echelle)
        }

        // ── valeurs détaillées ───────────────────────────────────────────────
        Repeater {
            model: root.lignes

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
                    // Ce que la barre ne dit pas : les Go utilisés / totaux.
                    text: {
                        const d = root.detail || ({})
                        if (modelData.cle === "ram" && d.ram)
                            return d.ram.utilisee_go + " / " + d.ram.totale_go + " Go"
                        // VRAM et température du GPU ont leurs propres lignes :
                        // seule la RAM garde son complément ici.
                        return ""
                    }
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(Theme.textXs * 0.86 * root.echelle)
                }
            }
        }

        // ── processus ───────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Row {
            width: parent.width
            spacing: Math.round(6 * root.echelle)

            Text {
                width: parent.width - Math.round(150 * root.echelle)
                text: "Processus"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(Theme.textXs * 0.86 * root.echelle)
            }

            // Le tri est un geste local : la liste est déjà en mémoire.
            Repeater {
                model: [{ cle: "cpu", nom: "CPU" }, { cle: "ram_mo", nom: "RAM" },
                        { cle: "gpu_mo", nom: "GPU" }]

                Rectangle {
                    required property var modelData
                    width: Math.round(40 * root.echelle)
                    height: Math.round(16 * root.echelle)
                    radius: Math.round(4 * root.echelle)
                    color: root.tri === modelData.cle
                           ? Qt.alpha(Theme.accent, 0.18) : Qt.alpha(Theme.fg, 0.06)

                    Text {
                        anchors.centerIn: parent
                        text: String(modelData.nom)
                        color: root.tri === modelData.cle
                               ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Math.round(Theme.textXs * 0.72 * root.echelle)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tri = String(modelData.cle)
                    }
                }
            }
        }

        Repeater {
            model: root.processusTries

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(5 * root.echelle)

                Text {
                    width: Math.round(34 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: String(modelData.pid)
                    color: Qt.alpha(Theme.fg, 0.35)
                    font.pixelSize: Math.round(Theme.textXs * 0.72 * root.echelle)
                    font.features: { "tnum": 1 }
                }

                Text {
                    width: parent.width - Math.round(150 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.nom)
                    color: Qt.alpha(Theme.fg, 0.85)
                    font.pixelSize: Math.round(Theme.textXs * 0.82 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(44 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: Number(modelData.cpu).toFixed(1) + " %"
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Math.round(Theme.textXs * 0.72 * root.echelle)
                    font.features: { "tnum": 1 }
                }

                // « arrêter » demande un SIGTERM ; forcer reste possible en
                // recliquant sur la même ligne, en connaissance de cause.
                Rectangle {
                    width: Math.round(46 * root.echelle)
                    height: Math.round(16 * root.echelle)
                    radius: Math.round(4 * root.echelle)
                    color: Qt.alpha(Theme.warn, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(Theme.warn, 0.3)

                    Text {
                        anchors.centerIn: parent
                        text: "arrêter"
                        color: Qt.alpha(Theme.warn, 0.9)
                        font.pixelSize: Math.round(Theme.textXs * 0.66 * root.echelle)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.arreter(Number(modelData.pid))
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.message !== ""
            text: root.message
            color: Theme.warn
            font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
            wrapMode: Text.WordWrap
        }
    }
}
