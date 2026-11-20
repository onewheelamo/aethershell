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
    property var notifier: null
    // Le popup est monté par l'applet ; il connaît son état d'ouverture.
    property bool ouvert: false

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property var toutes: ["cpu", "ram", "gpu", "temp", "load", "swap", "disk", "net"]
    readonly property var noms: ({
        cpu: "CPU",
        ram: "RAM",
        gpu: "GPU",
        temp: "Temp",
        load: "Load",
        swap: "Swap",
        disk: "Disque",
        net: "Réseau"
    })

    property var mesures: ["cpu", "ram", "gpu", "temp"]
    // Jauges : même option d'applet que le widget (case « jauge »).
    property bool jauge: true
    property bool coeursOuverts: false
    property bool alertesOuvertes: false
    // Processus : lus seulement pendant que le panneau est ouvert (l'inspiration
    // nvtop garde cette discipline — rien ne tourne en fond pour ça).
    property var processus: []
    property string tri: "cpu"
    property string message: ""
    property int dernierPidArrete: 0

    function ouvrirOutilTerminal(cmd) {
        lanceurOutil.command = [
            "sh", "-c",
            "for t in kitty foot alacritty ghostty wezterm konsole gnome-terminal xterm; do "
            + "if command -v \"$t\" >/dev/null 2>&1; then exec \"$t\" -e sh -c " + JSON.stringify(cmd) + "; fi; done"
        ]
        lanceurOutil.running = false
        lanceurOutil.running = true
    }

    function rafraichirProcessus() {
        if (!root.ouvert) return
        procProcessus.running = false
        procProcessus.running = true
    }

    function arreter(pid) {
        const forcer = (root.dernierPidArrete === pid)
        root.dernierPidArrete = forcer ? 0 : pid
        geste.pid = pid
        geste.forcer = forcer
        geste.running = false
        geste.running = true
    }

    function valeurProcessus(p) {
        if (root.tri === "ram_mo" || root.tri === "gpu_mo") {
            const mo = Number(p[root.tri]) || 0
            if (mo >= 1024) return (mo / 1024).toFixed(1).replace(".", ",") + " Go"
            return Math.round(mo) + " Mo"
        }
        return Number(p.cpu || 0).toFixed(1) + " %"
    }

    readonly property var processusTries: {
        const l = (root.processus || []).slice()
        const cle = root.tri
        l.sort(function (a, b) { return (Number(b[cle]) || 0) - (Number(a[cle]) || 0) })
        return l.slice(0, 9)
    }
    readonly property var barres: (SystemServices.systemeData.compact && SystemServices.systemeData.compact.barres) || []
    readonly property var detail: SystemServices.systemeData.detail || ({})

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
        if (root.ouvert) SystemServices.metriquesActif = true
    }

    // Un seul gestionnaire de démarrage par objet : deux `Component.onCompleted`
    // dans le même Item lèvent « Property value set multiple times » et le
    // composant ne se crée pas — le panneau s'ouvre alors sur une carte vide.
    Component.onCompleted: { charger(); rafraichirProcessus() }

    // Le choix courant vient du registre, pas d'une copie locale : c'est lui qui
    // fait foi, y compris quand il a été changé depuis le panneau.
    Process {
        id: procProcessus
        command: [Quickshell.shellPath("core/as-core"), "systeme", "processus"]
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
        property bool forcer: false
        command: geste.forcer
                 ? [Quickshell.shellPath("core/as-core"), "systeme", "tuer", String(geste.pid), "--force"]
                 : [Quickshell.shellPath("core/as-core"), "systeme", "tuer", String(geste.pid)]
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

    onOuvertChanged: {
        if (ouvert) {
            SystemServices.metriquesActif = true
            rafraichirProcessus()
        }
        else root.dernierPidArrete = 0
    }

    Process {
        id: etat
        command: [Quickshell.shellPath("core/as-core"), "bar-applets", "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const liste = JSON.parse(text.trim()) || []
                    for (let i = 0; i < liste.length; i++) {
                        if (liste[i].id !== "systeme") continue
                        const m = (liste[i].options || {}).mesures
                        root.mesures = (m && m.length) ? m : root.toutes
                        root.jauge = ((liste[i].options || {}).jauge !== false)
                        return
                    }
                } catch (e) { /* registre illisible : on garde les quatre */ }
            }
        }
    }

    Process {
        id: ecriture
        stdout: StdioCollector {
            onStreamFinished: { root.charger(); if (root.notifier) root.notifier() }
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
        ecriture.command = [Quickshell.shellPath("core/as-core"), "bar-applets",
                            "option", "systeme", "mesures", JSON.stringify(liste)]
        ecriture.running = true
    }

    Process {
        id: lanceurOutil
    }

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(8 * root.echelle)

        Row {
            width: parent.width
            spacing: Math.round(6 * root.echelle)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Système"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * root.echelle)
            }

            Item { width: 1; height: 1 }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Boolean(root.detail.uptime && root.detail.uptime.texte)
                text: root.detail.uptime ? ("⏱ " + root.detail.uptime.texte) : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(Theme.textXs * 0.82 * root.echelle)
                font.features: { "tnum": 1 }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Boolean(root.detail.load && root.detail.load.l1 !== undefined)
                text: root.detail.load ? ("· Load " + root.detail.load.l1) : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(Theme.textXs * 0.82 * root.echelle)
                font.features: { "tnum": 1 }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                readonly property int nbAlertes: (root.detail.alerts && Number(root.detail.alerts.total)) || 0
                visible: nbAlertes > 0
                width: Math.round(texteAlerte.implicitWidth + 12 * root.echelle)
                height: Math.round(18 * root.echelle)
                radius: Math.round(4 * root.echelle)
                color: Qt.alpha(Theme.warn, 0.16)
                border.width: 1
                border.color: Qt.alpha(Theme.warn, 0.45)

                Text {
                    id: texteAlerte
                    anchors.centerIn: parent
                    text: parent.nbAlertes + (parent.nbAlertes > 1 ? " alertes" : " alerte")
                    color: Theme.warn
                    font.pixelSize: Math.round(Theme.textXs * 0.78 * root.echelle)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.alertesOuvertes = !root.alertesOuvertes
                }
            }
        }

        // ── détail des alertes (style YASSM) ─────────────────────────────────
        Rectangle {
            readonly property var al: root.detail.alerts || ({})
            visible: root.alertesOuvertes && Number(al.total || 0) > 0
            width: parent.width
            implicitHeight: colAlertes.implicitHeight + Math.round(10 * root.echelle)
            radius: Math.round(6 * root.echelle)
            color: Qt.alpha(Theme.warn, 0.08)
            border.width: 1
            border.color: Qt.alpha(Theme.warn, 0.25)

            Column {
                id: colAlertes
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Math.round(5 * root.echelle) }
                spacing: 3

                Text {
                    visible: Number(parent.parent.al.zombies || 0) > 0
                    text: "• " + parent.parent.al.zombies + " processus zombie(s)"
                    color: Theme.warn
                    font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
                }

                Repeater {
                    model: parent.parent.al.systemd_failed || []
                    Text {
                        required property string modelData
                        text: "• systemd en échec : " + modelData
                        color: Theme.error
                        font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
                    }
                }

                Repeater {
                    model: parent.parent.al.seuils || []
                    Text {
                        required property var modelData
                        text: "• " + modelData.nom + " : " + modelData.texte
                        color: modelData.niveau === "critique" ? Theme.error : Theme.warn
                        font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
                    }
                }
            }
        }

        // ── choix des mesures ────────────────────────────────────────────────
        Flow {
            width: parent.width
            spacing: 5

            Repeater {
                model: root.toutes

                delegate: Rectangle {
                    id: puce
                    required property string modelData
                    readonly property bool actif: (root.mesures || []).indexOf(modelData) >= 0
                    visible: modelData !== "swap" || Boolean(root.detail.swap && Number(root.detail.swap.totale_go) > 0)
                    width: Math.max(44, Math.round(txtPuce.implicitWidth + 14))
                    height: 20
                    radius: 5
                    color: actif ? Qt.alpha(Theme.accent, 0.18) : "transparent"
                    border.width: 1
                    border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.25)

                    Text {
                        id: txtPuce
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

                // Jauge : la même proportion que dans la barre et le widget,
                // dessinée ici pour ceux qui lisent le popup sans la barre.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.jauge && modelData.remplissage !== undefined
                    width: Math.round(72 * root.echelle)
                    height: Math.round(4 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.13)

                    Rectangle {
                        width: Math.max(2, parent.width * Math.min(100, Math.max(0,
                                   Number(modelData.remplissage) || 0)) / 100)
                        height: parent.height
                        radius: parent.radius
                        color: modelData.niveau === "critique" ? Theme.error
                               : (modelData.niveau === "attention" ? Theme.warn : Theme.accent)
                    }
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
                    text: {
                        const d = root.detail || ({})
                        const c = modelData.cle
                        if (c === "cpu" && d.cpu) {
                            const f = d.cpu.freq_ghz ? (d.cpu.freq_ghz + " GHz") : ""
                            const n = d.cpu.coeurs ? (d.cpu.coeurs.length + " cœurs") : ""
                            const sep = (f && n) ? " · " : ""
                            return f + sep + n + (n ? (root.coeursOuverts ? " ▴" : " ▾") : "")
                        }
                        if (c === "ram" && d.ram)
                            return d.ram.utilisee_go + " / " + d.ram.totale_go + " Go"
                                 + (d.ram.cache_go ? (" (cache " + d.ram.cache_go + ")") : "")
                        if (c === "gpu" && d.gpu && d.gpu.power_w !== null && d.gpu.power_w !== undefined)
                            return d.gpu.power_w + " W"
                        if (c === "load" && d.load)
                            return "1m " + d.load.l1 + " · 5m " + d.load.l5
                        if (c === "swap" && d.swap)
                            return d.swap.utilisee_go + " / " + d.swap.totale_go + " Go"
                        if (c === "disk" && d.disk)
                            return d.disk.utilise_go + " / " + d.disk.total_go + " Go (/)"
                        if (c === "net" && d.net)
                            return "↑ " + d.net.tx_texte
                        return ""
                    }
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(Theme.textXs * 0.84 * root.echelle)

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.cle === "cpu"
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.coeursOuverts = !root.coeursOuverts
                    }
                }
            }
        }

        // ── détail par cœur CPU (style YASSM) ─────────────────────────────────
        Flow {
            readonly property var coeurs: (root.detail.cpu && root.detail.cpu.coeurs) || []
            visible: root.coeursOuverts && coeurs.length > 0
            width: parent.width
            spacing: Math.round(4 * root.echelle)

            Repeater {
                model: parent.coeurs
                delegate: Column {
                    required property real modelData
                    required property int index
                    width: Math.round(28 * root.echelle)
                    spacing: 2

                    Rectangle {
                        width: parent.width
                        height: Math.round(4 * root.echelle)
                        radius: 2
                        color: Qt.alpha(Theme.fg, 0.12)

                        Rectangle {
                            width: Math.max(2, parent.width * Math.min(100, Math.max(0, modelData)) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: modelData >= 85 ? Theme.error : (modelData >= 60 ? Theme.warn : Theme.accent)
                        }
                    }

                    Text {
                        text: "C" + index + " " + Math.round(modelData) + "%"
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(Theme.textXs * 0.64 * root.echelle)
                        font.features: { "tnum": 1 }
                    }
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
                    text: String(modelData.nom) + (modelData.moi === false && modelData.user ? (" (" + modelData.user + ")") : "")
                    color: Qt.alpha(Theme.fg, modelData.moi === false ? 0.65 : 0.85)
                    font.pixelSize: Math.round(Theme.textXs * 0.82 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(44 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.valeurProcessus(modelData)
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Math.round(Theme.textXs * 0.72 * root.echelle)
                    font.features: { "tnum": 1 }
                }

                // « arrêter » demande un SIGTERM ; forcer reste possible en
                // recliquant sur la même ligne, en connaissance de cause.
                Rectangle {
                    readonly property bool enAttenteForce: root.dernierPidArrete === Number(modelData.pid)
                    width: Math.round(46 * root.echelle)
                    height: Math.round(16 * root.echelle)
                    radius: Math.round(4 * root.echelle)
                    color: Qt.alpha(enAttenteForce ? Theme.error : Theme.warn, 0.14)
                    border.width: 1
                    border.color: Qt.alpha(enAttenteForce ? Theme.error : Theme.warn, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: parent.enAttenteForce ? "forcer" : "arrêter"
                        color: Qt.alpha(parent.enAttenteForce ? Theme.error : Theme.warn, 0.9)
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

        // ── raccourcis outils système (style YASSM) ──────────────────────────
        Row {
            width: parent.width
            spacing: Math.round(6 * root.echelle)

            Repeater {
                model: [
                    { label: "Moniteur (btop)", cmd: "command -v btop >/dev/null && btop || htop || top" },
                    { label: "Sondes (sensors)", cmd: "watch -n1 sensors" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: Math.round(txtOutil.implicitWidth + 14 * root.echelle)
                    height: Math.round(20 * root.echelle)
                    radius: Math.round(5 * root.echelle)
                    color: Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.16)

                    Text {
                        id: txtOutil
                        anchors.centerIn: parent
                        text: modelData.label
                        color: Qt.alpha(Theme.fg, 0.78)
                        font.pixelSize: Math.round(Theme.textXs * 0.74 * root.echelle)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.ouvrirOutilTerminal(modelData.cmd)
                    }
                }
            }
        }
    }
}
