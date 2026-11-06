import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// HOMELAB — ce qui tourne et ce qui devrait répondre.
//
// Même service que l'applet. Les hôtes surveillés et l'instance Proxmox sont
// déclarés dans core/homelab.json ; sans ce fichier la carte montre les unités en
// échec, sans rien inventer.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var unites: ({})
    property var hotes: []
    property var proxmox: ({})
    property bool charge: false

    // Même garde-fou que dans le popup : deux clics, trois secondes. Les deux
    // surfaces ont leur propre armement — armer dans l'une ne doit pas exécuter
    // dans l'autre.
    property string confirmation: ""
    property string messageAction: ""

    function cleInvite(g) {
        return String(g.type) + ":" + String(g.id) + ":" + String(g.noeud)
    }

    function demanderRedemarrage(g) {
        if (!g) return
        const cle = root.cleInvite(g)
        if (root.confirmation === cle) {
            root.confirmation = ""
            root.messageAction = "redémarrage de " + String(g.nom || g.id) + "…"
            actionProc.command = ["python3", Quickshell.shellPath("core/homelab_applet.py"),
                                  "--action", "reboot", "--type", String(g.type),
                                  "--node", String(g.noeud), "--vmid", String(g.id)]
            actionProc.running = true
            return
        }
        root.confirmation = cle
        gardeFou.restart()
    }

    Timer {
        id: gardeFou
        interval: 3000
        repeat: false
        onTriggered: root.confirmation = ""
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text.trim())
                    root.messageAction = v.ok ? String(v.message || "demandé")
                                              : "échec — " + String(v.message || "")
                } catch (e) {
                    root.messageAction = "réponse illisible"
                }
                rechargerApres.restart()
            }
        }
    }

    Timer {
        id: rechargerApres
        interval: 1500
        repeat: false
        onTriggered: root.rafraichir()
    }

    function rafraichir() {
        proc.running = false
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
        command: ["python3", Quickshell.shellPath("core/homelab_applet.py"), "--force"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    const det = d.detail || ({})
                    root.unites = det.unites || ({})
                    root.hotes = det.hotes || []
                    root.proxmox = det.proxmox || ({})
                } catch (e) {
                    root.unites = ({})
                    root.hotes = []
                    root.proxmox = ({})
                }
                root.charge = true
            }
        }
    }

    implicitWidth: Math.round(246 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(7 * echelle)

        // ── Proxmox ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 3
            visible: root.proxmox && root.proxmox.configure === true

            Text {
                width: parent.width
                visible: root.proxmox.erreur !== null && root.proxmox.erreur !== undefined
                text: "proxmox : " + String(root.proxmox.erreur || "")
                color: Theme.error
                font.pixelSize: Math.round(10 * root.echelle)
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.proxmox.noeuds || []

                Column {
                    required property var modelData
                    width: colonne.width
                    spacing: 2

                    Row {
                        width: parent.width

                        Text {
                            width: parent.width - Math.round(64 * root.echelle)
                            text: String(modelData.nom || "") + " · CPU " + modelData.cpu + " %"
                            color: Theme.fg
                            font.pixelSize: Math.round(11 * root.echelle)
                        }

                        Text {
                            width: Math.round(64 * root.echelle)
                            horizontalAlignment: Text.AlignRight
                            text: (modelData.ram_go !== null
                                   ? modelData.ram_go + "/" + modelData.ram_max_go + " Go" : "—")
                            color: Qt.alpha(Theme.fg, 0.55)
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
                            width: parent.width * Math.min(1, (Number(modelData.ram) || 0) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: (Number(modelData.ram) || 0) > 85 ? Theme.error : Theme.accent
                        }
                    }
                }
            }

            Row {
                width: parent.width
                visible: root.proxmox.total !== undefined

                Text {
                    width: parent.width - Math.round(64 * root.echelle)
                    text: "machines"
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Math.round(10 * root.echelle)
                }

                Text {
                    width: Math.round(64 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(root.proxmox.en_cours || 0) + " / " + String(root.proxmox.total || 0)
                    color: Theme.fg
                    font.pixelSize: Math.round(11 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            // ── invités : CT et VM ──────────────────────────────────────────
            Repeater {
                model: root.proxmox.vms || []

                Row {
                    required property var modelData
                    width: colonne.width
                    height: Math.round(15 * root.echelle)
                    spacing: Math.round(4 * root.echelle)

                    Rectangle {
                        width: Math.round(4 * root.echelle)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.etat === "running" ? Theme.accent
                                                            : Qt.alpha(Theme.fg, 0.3)
                    }

                    Text {
                        // Même somme que dans le popup : 4 + 10 + 12 + 78, plus
                        // 10 px de respiration (la ligne débordait de 14 px).
                        width: parent.width - Math.round(114 * root.echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.type === "lxc" ? "CT " : "VM ")
                              + String(modelData.id) + "  " + String(modelData.nom || "")
                        color: modelData.etat === "running" ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(10 * root.echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: Math.round(78 * root.echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.confirmation === root.cleInvite(modelData)
                              ? "confirmer ?"
                              : (modelData.etat === "running"
                                 ? String(modelData.cpu) + "% · " + String(modelData.ram) + "%"
                                 : String(modelData.etat || ""))
                        color: root.confirmation === root.cleInvite(modelData)
                               ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(9.5 * root.echelle)
                        font.bold: root.confirmation === root.cleInvite(modelData)
                        font.features: { "tnum": 1 }
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "restart"
                        size: Math.round(10 * root.echelle)
                        color: survolInvite.containsMouse
                               ? (root.confirmation === root.cleInvite(modelData) ? Theme.error : Theme.accent)
                               : Qt.alpha(Theme.fg, 0.42)
                        opacityLevel: 1

                        MouseArea {
                            id: survolInvite
                            anchors.fill: parent
                            anchors.margins: Math.round(-4 * root.echelle)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.demanderRedemarrage(modelData)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.proxmox.droits === "aucun"
                text: "jeton sans droits — pveum acl modify"
                color: Theme.warn
                font.pixelSize: Math.round(9.5 * root.echelle)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.messageAction !== ""
                text: root.messageAction
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(9.5 * root.echelle)
                elide: Text.ElideRight
            }
        }

        // ── unités en échec ──────────────────────────────────────────────────
        Row {
            width: parent.width

            Text {
                width: parent.width - Math.round(64 * root.echelle)
                text: "services en échec"
                color: root.unites.nombre > 0 ? Theme.error : Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(10 * root.echelle)
            }

            Text {
                width: Math.round(64 * root.echelle)
                horizontalAlignment: Text.AlignRight
                text: String(root.unites.nombre || 0)
                color: root.unites.nombre > 0 ? Theme.error : Theme.fg
                font.pixelSize: Math.round(11 * root.echelle)
                font.bold: root.unites.nombre > 0
                font.features: { "tnum": 1 }
            }
        }

        // ── hôtes ────────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: root.hotes.length > 0 ? 1 : 0
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Repeater {
            model: root.hotes

            Row {
                required property var modelData
                width: colonne.width

                Text {
                    width: parent.width - Math.round(74 * root.echelle)
                    text: String(modelData.nom || modelData.url || "")
                    color: modelData.joignable ? Theme.fg : Theme.error
                    font.pixelSize: Math.round(11 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(74 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.joignable ? (modelData.latence_ms + " ms") : "hors ligne"
                    color: modelData.joignable ? Qt.alpha(Theme.fg, 0.55) : Theme.error
                    font.pixelSize: Math.round(10 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            visible: root.charge && root.hotes.length === 0
            text: "aucun hôte déclaré"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(9.5 * root.echelle)
        }
    }
}
