import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// HERMES — observatoire et lanceur de l'agent.
//
// Source : `core/hermes_applet.py` et `core/hermes_lecteur.py`.
// Vue compacte par défaut (sessions récentes, jetons, état) et volet enrichi
// dépliable/repliable pour ne pas surcharger le bureau :
//   - État et redémarrage du gateway (service systemd)
//   - Tâches cron planifiées et état du ticker
//   - Actions rapides 1-clic (terminal, diagnostic doctor, tick cron)
//   - Journal live en direct (tail sur ~/.hermes/logs/agent.log)
// Le widget est entièrement scrollable (Flickable) si le contenu dépasse la hauteur max.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""
    property bool replie: true
    property string actionStatus: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var etat: ({})
    property bool charge: false

    readonly property var lignes: {
        const l = root.etat.sessions || []
        const vivantes = l.filter(function (s) { return s.vivante })
        const autres = l.filter(function (s) { return !s.vivante })
        return vivantes.concat(autres).slice(0, 3)
    }

    function jeton(n) {
        n = Number(n) || 0
        if (n >= 1e6) return (n / 1e6).toFixed(1).replace(".", ",") + " M"
        if (n >= 1e3) return Math.round(n / 1e3) + " k"
        return String(n)
    }

    function duree(s) {
        s = Number(s) || 0
        if (s >= 3600) return Math.round(s / 3600) + " h"
        if (s >= 60) return Math.round(s / 60) + " min"
        return s + " s"
    }

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    function actionner(cmd, libelle) {
        actionStatus = libelle ? libelle + "…" : "Action en cours…"
        actionProc.actionCmd = cmd
        actionProc.running = false
        actionProc.running = true
    }

    function ouvrirTerminal() {
        Quickshell.execDetached(["ghostty", "-e", "hermes"])
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/hermes_applet.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail || ({})).hermes || ({})
                } catch (e) {
                    root.etat = ({})
                }
                root.charge = true
            }
        }
    }

    Process {
        id: actionProc
        property string actionCmd: ""
        command: ["python3", Quickshell.shellPath("core/hermes_applet.py"), actionProc.actionCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text.trim())
                    root.actionStatus = res.ok ? "✓ " + (res.action || "Succès") : "✕ " + (res.output || "Échec")
                } catch (e) {
                    if (text.trim().length > 0) root.actionStatus = text.trim().slice(0, 40)
                }
            }
        }
        onExited: root.rafraichir()
    }

    readonly property color teinte: root.etat.etat === "erreur" ? Theme.error
                                     : root.etat.etat === "attente" ? Theme.warn
                                     : root.etat.etat === "en_cours" ? Theme.accent
                                     : Qt.alpha(Theme.fg, 0.55)

    readonly property real hauteurMax: Math.round(380 * echelle)
    implicitWidth: Math.round(264 * echelle)
    implicitHeight: replie ? Math.round(colonne.implicitHeight) : Math.min(Math.round(colonne.implicitHeight), hauteurMax)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: colonne.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.replie && contentHeight > height

        Column {
            id: colonne
            width: flick.width - (scrollBar.visible ? 7 : 0)
            spacing: Math.round(5 * echelle)

            // ── En-tête : état & jetons ───────────────────────────────────────
            Row {
                width: parent.width
                spacing: Math.round(5 * echelle)

                Rectangle {
                    width: Math.round(5 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.teinte
                }

                Text {
                    width: parent.width - Math.round(58 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.etat.etat === undefined ? "Hermes : aucun état"
                          : String(root.etat.libelle || root.etat.etat)
                    color: Theme.fg
                    font.pixelSize: Math.round(11 * echelle)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(48 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: root.etat.jetons && root.etat.jetons.jour
                          ? root.jeton(root.etat.jetons.jour) : ""
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(9.5 * echelle)
                    font.features: { "tnum": 1 }
                }
            }

            // ── Tâche en cours ────────────────────────────────────────────────
            Text {
                width: parent.width
                visible: Boolean(root.etat.tache)
                text: String(root.etat.tache || "")
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Math.round(10 * echelle)
                elide: Text.ElideRight
            }

            // ── Trois sessions récentes (vivantes en tête) ─────────────────────
            Repeater {
                model: root.lignes

                Row {
                    required property var modelData
                    width: colonne.width
                    spacing: Math.round(4 * echelle)

                    Rectangle {
                        width: Math.round(4 * echelle)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.vivante ? Theme.accent
                               : String(modelData.etat) === "inactive"
                                 ? Qt.alpha(Theme.fg, 0.22) : Qt.alpha(Theme.fg, 0.45)
                    }

                    Text {
                        width: Math.round(44 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.profil || "")
                        color: Qt.alpha(Theme.fg, 0.4)
                        font.pixelSize: Math.round(8.5 * echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width - Math.round(96 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.titre || modelData.tache || "sans titre")
                        color: modelData.vivante ? Qt.alpha(Theme.fg, 0.9)
                                                 : Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Math.round(9.5 * echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: Math.round(40 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: modelData.vivante ? root.jeton(modelData.jetons)
                                                : root.duree(modelData.duree_s)
                        color: Qt.alpha(Theme.fg, modelData.vivante ? 0.6 : 0.4)
                        font.pixelSize: Math.round(9 * echelle)
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.lignes.length === 0
                text: root.etat.etat === "hors_ligne" ? "base illisible" : "aucune session"
                color: Qt.alpha(Theme.fg, 0.4)
                font.pixelSize: Math.round(9.5 * echelle)
            }

            // ── Bouton Déplier / Replier ──────────────────────────────────────
            Rectangle {
                id: toggleBtn
                width: parent.width
                height: Math.round(20 * echelle)
                radius: Theme.globalRadius
                color: toggleMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.45)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.08)

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.replie ? "Détails & Actions ▾" : "Replier ▴"
                        color: toggleMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.70)
                        font.pixelSize: Math.round(9 * echelle)
                        font.bold: true
                    }
                }

                MouseArea {
                    id: toggleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.replie = !root.replie
                }
            }

            // ══════════════════════════════════════════════════════════════════
            // SECTION ENRICHIE (VISIBLE QUAND DÉPLIÉE)
            // ══════════════════════════════════════════════════════════════════
            Column {
                width: parent.width
                visible: !root.replie
                spacing: Math.round(6 * echelle)

                // Séparateur
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.fg, 0.08)
                }

                // ── 1. Gateway status & contrôle ─────────────────────────────
                Row {
                    width: parent.width
                    spacing: Math.round(5 * echelle)

                    Rectangle {
                        width: Math.round(5 * echelle)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.etat.gateway && root.etat.gateway.actif ? Theme.success : Theme.error
                    }

                    Text {
                        width: parent.width - Math.round(74 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gateway : " + (root.etat.gateway && root.etat.gateway.actif
                            ? "actif (PID " + (root.etat.gateway.pid || "—") + ")"
                            : "arrêté")
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Math.round(9 * echelle)
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        width: Math.round(64 * echelle)
                        height: Math.round(18 * echelle)
                        radius: Theme.globalRadius
                        color: rstGwMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.50)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "↺ Relancer"
                            color: Theme.accent
                            font.pixelSize: Math.round(8.5 * echelle)
                            font.bold: true
                        }

                        MouseArea {
                            id: rstGwMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionner("gateway-restart", "Redémarrage gateway")
                        }
                    }
                }

                // ── 2. Tâches planifiées (Cron) ──────────────────────────────
                Row {
                    width: parent.width

                    Text {
                        width: parent.width - Math.round(56 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cron & Planifications"
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Math.round(8.5 * echelle)
                        font.bold: true
                    }

                    Rectangle {
                        width: Math.round(52 * echelle)
                        height: Math.round(18 * echelle)
                        radius: Theme.globalRadius
                        color: tickMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.40)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "⚡ Tick"
                            color: Qt.alpha(Theme.fg, 0.8)
                            font.pixelSize: Math.round(8 * echelle)
                        }

                        MouseArea {
                            id: tickMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionner("cron-tick", "Exécution cron tick")
                        }
                    }
                }

                Repeater {
                    model: root.etat.cron || []

                    Row {
                        required property var modelData
                        width: parent.width
                        spacing: Math.round(4 * echelle)

                        Rectangle {
                            width: Math.round(3.5 * echelle)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.actif ? Theme.accent : Qt.alpha(Theme.fg, 0.25)
                        }

                        Text {
                            width: parent.width - Math.round(75 * echelle)
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(modelData.nom || "")
                            color: Qt.alpha(Theme.fg, modelData.actif ? 0.8 : 0.4)
                            font.pixelSize: Math.round(8.5 * echelle)
                            elide: Text.ElideRight
                        }

                        Text {
                            width: Math.round(68 * echelle)
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: String(modelData.prochaine || "").slice(5, 16).replace("T", " ")
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.pixelSize: Math.round(8 * echelle)
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: (root.etat.cron || []).length === 0
                    text: root.etat.gateway && root.etat.gateway.ticker_actif
                        ? "Ticker actif (aucun job planifié)"
                        : "Aucune tâche cron active"
                    color: Qt.alpha(Theme.fg, 0.38)
                    font.pixelSize: Math.round(8.5 * echelle)
                }

                // ── 3. Actions rapides ───────────────────────────────────────
                Text {
                    width: parent.width
                    text: "Actions rapides"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(8.5 * echelle)
                    font.bold: true
                }

                Row {
                    width: parent.width
                    spacing: Math.round(5 * echelle)

                    Rectangle {
                        width: Math.round((parent.width - 5 * echelle) / 2)
                        height: Math.round(22 * echelle)
                        radius: Theme.globalRadius
                        color: docMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.50)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "🔍 Doctor"
                            color: Theme.fg
                            font.pixelSize: Math.round(8.5 * echelle)
                        }

                        MouseArea {
                            id: docMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionner("doctor", "Diagnostic cron")
                        }
                    }

                    Rectangle {
                        width: Math.round((parent.width - 5 * echelle) / 2)
                        height: Math.round(22 * echelle)
                        radius: Theme.globalRadius
                        color: termMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.50)
                        border.width: 1
                        border.color: Qt.alpha(Theme.fg, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "💻 Terminal"
                            color: Theme.accent
                            font.pixelSize: Math.round(8.5 * echelle)
                        }

                        MouseArea {
                            id: termMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ouvrirTerminal()
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.actionStatus !== ""
                    text: root.actionStatus
                    color: Theme.accent
                    font.pixelSize: Math.round(8.5 * echelle)
                    elide: Text.ElideRight
                }

                // ── 4. Journal en direct (agent.log tail) ─────────────────────
                Text {
                    width: parent.width
                    text: "Journal en direct (agent.log)"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Math.round(8.5 * echelle)
                    font.bold: true
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(Math.round(90 * echelle), logCol.implicitHeight + 8)
                    radius: Theme.globalRadius
                    color: Qt.alpha(Theme.bg, 0.60)
                    border.width: 1
                    border.color: Qt.alpha(Theme.fg, 0.08)
                    clip: true

                    Column {
                        id: logCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 4
                        }
                        spacing: 2

                        Repeater {
                            model: (root.etat.logs || []).slice(-8)

                            Text {
                                required property var modelData
                                width: logCol.width
                                text: String(modelData)
                                color: modelData.indexOf("ERROR") !== -1 ? Theme.error
                                       : modelData.indexOf("WARNING") !== -1 ? Theme.warn
                                       : Qt.alpha(Theme.fg, 0.65)
                                font.pixelSize: Math.round(8 * echelle)
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            visible: !(root.etat.logs && root.etat.logs.length > 0)
                            width: logCol.width
                            text: "Aucun log récent"
                            color: Qt.alpha(Theme.fg, 0.35)
                            font.pixelSize: Math.round(8 * echelle)
                        }
                    }
                }
            }
        }
    }

    // ── Barre de défilement (scrollbar) ───────────────────────────────────────
    Rectangle {
        id: scrollBar
        visible: !root.replie && flick.interactive
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 2
        width: 3
        radius: 1.5
        color: Qt.alpha(Theme.fg, 0.12)

        Rectangle {
            width: parent.width
            radius: parent.radius
            color: Theme.accent
            y: flick.visibleArea.yPosition * scrollBar.height
            height: Math.max(14, flick.visibleArea.heightRatio * scrollBar.height)
        }
    }
}
