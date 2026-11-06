import QtQuick
import Quickshell
import Quickshell.Io

// POPUP HOMELAB — invités Proxmox (CT et VM), unités en échec, hôtes.
//
// Même source que l'applet (core/homelab_applet.py). Les hôtes surveillés et
// l'instance Proxmox viennent de core/homelab.json ; sans ce fichier, seules les
// unités en échec sont montrées — l'applet ne prétend rien savoir d'un parc qu'on
// ne lui a pas décrit.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }

    // Un panneau se lit à 60 cm, pas à trois mètres comme la barre : le corps de
    // texte est un cran au-dessus, et les multiplicateurs existants (0,9 / 0,85)
    // continuent de hiérarchiser l'information.
    readonly property real corps: root.corps * 1.15

    property var unites: ({})
    property var hotes: []
    property var proxmox: ({})
    property bool charge: false

    // Redémarrage en deux temps : le premier clic arme, le second exécute, et
    // l'armement retombe au bout de 3 s. Un clic sec sur un conteneur qui tourne
    // serait une coupure de service offerte à un clic mal placé.
    property string confirmation: ""      // "lxc:100:hoth"
    property string messageAction: ""

    function cleInvite(g) {
        return String(g.type) + ":" + String(g.id) + ":" + String(g.noeud)
    }

    function demanderRedemarrage(g) {
        if (!g) return
        const cle = root.cleInvite(g)
        if (root.confirmation === cle) {
            root.appliquerRedemarrage(g)
            return
        }
        root.confirmation = cle
        gardeFou.restart()
    }

    function appliquerRedemarrage(g) {
        root.confirmation = ""
        root.messageAction = "redémarrage de " + String(g.nom || g.id) + "…"
        actionProc.command = ["python3", Quickshell.shellPath("core/homelab_applet.py"),
                              "--action", "reboot", "--type", String(g.type),
                              "--node", String(g.noeud), "--vmid", String(g.id)]
        actionProc.running = true
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
                // Proxmox met un instant à changer l'état : on relit après coup.
                rechargerApres.restart()
            }
        }
    }

    Timer {
        id: rechargerApres
        interval: 1500
        repeat: false
        onTriggered: root.charger()
    }

    function charger() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

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

    // Élargi d'autant que le corps de texte a grandi, sinon les noms d'invités
    // s'élident alors qu'il reste de la place au centre.
    implicitWidth: Math.round(324 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(6 * echelle)

        Text {
            text: "Homelab"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
        }

        // ── Proxmox ──────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 1
            visible: root.proxmox && root.proxmox.configure === true

            Text {
                width: parent.width
                visible: root.proxmox.erreur !== null && root.proxmox.erreur !== undefined
                text: "Proxmox : " + String(root.proxmox.erreur || "")
                color: Theme.error
                font.pixelSize: Math.round(root.corps * 0.9 * root.echelle)
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.proxmox.noeuds || []

                Column {
                    required property var modelData
                    width: colonne.width
                    spacing: 1

                    Row {
                        // La colonne de droite des invités finit 29 px avant le bord
                        // (icône 12 + deux espacements de 5) : sans ce décalage, les
                        // uptimes tombaient 29 px plus à droite que les cpu·ram, et
                        // les nombres n'étaient pas sur la même verticale.
                        width: parent.width - Math.round(29 * root.echelle)

                        Text {
                            width: parent.width - Math.round(70 * root.echelle)
                            text: "Nœud " + String(modelData.nom || "")
                            color: modelData.en_ligne ? Theme.fg : Theme.error
                            font.pixelSize: Math.round(root.corps * root.echelle)
                        }

                        Text {
                            width: Math.round(70 * root.echelle)
                            horizontalAlignment: Text.AlignRight
                            text: modelData.uptime_j + " j"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Math.round(root.corps * 0.9 * root.echelle)
                            font.features: { "tnum": 1 }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "CPU " + modelData.cpu + " % · RAM "
                              + (modelData.ram_go !== null ? modelData.ram_go + "/" + modelData.ram_max_go + " Go" : "—")
                              + (modelData.ram !== null ? " (" + modelData.ram + " %)" : "")
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(root.corps * 0.85 * root.echelle)
                    }
                }
            }

            Row {
                // Même verticale que les invités (voir la ligne du nœud).
                width: parent.width - Math.round(29 * root.echelle)
                visible: root.proxmox.total !== undefined

                Text {
                    width: parent.width - Math.round(70 * root.echelle)
                    text: "Machines"
                    color: Theme.fg
                    font.pixelSize: Math.round(root.corps * root.echelle)
                }

                Text {
                    width: Math.round(70 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(root.proxmox.en_cours || 0) + " / " + String(root.proxmox.total || 0)
                    color: Qt.alpha(Theme.fg, 0.75)
                    font.pixelSize: Math.round(root.corps * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            // ── invités : CT et VM, avec leurs mesures et le redémarrage ────
            Repeater {
                model: root.proxmox.vms || []

                Row {
                    required property var modelData
                    width: colonne.width
                    height: Math.round(18 * root.echelle)
                    spacing: Math.round(5 * root.echelle)

                    // État : un point plein quand l'invité tourne.
                    Rectangle {
                        width: Math.round(5 * root.echelle)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.etat === "running" ? Theme.accent
                                                            : Qt.alpha(Theme.fg, 0.3)
                    }

                    Text {
                        // Somme de la ligne : point 5 + icône 12 + trois
                        // espacements 5 + mesures 96 = 128, plus 12 px de respiration
                        // avant le bord. Oublier le point et les espacements faisait
                        // déborder la ligne de 18 px, et l'icône ↻ était rognée.
                        width: parent.width - Math.round(140 * root.echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.type === "lxc" ? "CT " : "VM ")
                              + String(modelData.id) + "  " + String(modelData.nom || "")
                        color: modelData.etat === "running" ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(root.corps * 0.9 * root.echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: Math.round(96 * root.echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.confirmation === root.cleInvite(modelData)
                              ? "confirmer ?"
                              : (modelData.etat === "running"
                                 ? String(modelData.cpu) + "% · " + String(modelData.ram) + "%"
                                 : String(modelData.etat || ""))
                        color: root.confirmation === root.cleInvite(modelData)
                               ? Theme.error : Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Math.round(root.corps * 0.85 * root.echelle)
                        font.bold: root.confirmation === root.cleInvite(modelData)
                        font.features: { "tnum": 1 }
                    }

                    Icon {
                        id: boutonRedemarrer
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "restart"
                        size: Math.round(12 * root.echelle)
                        color: survol.containsMouse
                               ? (root.confirmation === root.cleInvite(modelData) ? Theme.error : Theme.accent)
                               : Qt.alpha(Theme.fg, 0.45)
                        opacityLevel: 1

                        MouseArea {
                            id: survol
                            anchors.fill: parent
                            anchors.margins: Math.round(-4 * root.echelle)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.demanderRedemarrage(modelData)
                        }
                    }
                }
            }

            // Aucun invité alors que les nœuds répondent : le jeton s'authentifie
            // mais n'a pas les droits. Le dire vaut mieux qu'afficher « 0 ».
            Text {
                width: parent.width
                visible: root.proxmox.droits === "aucun"
                text: "jeton sans droits — " + String(root.proxmox.aide || "pveum acl modify / …")
                color: Theme.warn
                font.pixelSize: Math.round(root.corps * 0.8 * root.echelle)
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                visible: root.messageAction !== ""
                text: root.messageAction
                color: Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: Math.round(root.corps * 0.8 * root.echelle)
                elide: Text.ElideRight
            }
        }

        // ── unités en échec ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 1

            Row {
                width: parent.width

                Text {
                    width: parent.width - Math.round(70 * root.echelle)
                    text: "Services en échec"
                    color: root.unites.nombre > 0 ? Theme.error : Theme.fg
                    font.pixelSize: Math.round(root.corps * root.echelle)
                }

                Text {
                    width: Math.round(70 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(root.unites.nombre || 0)
                    color: root.unites.nombre > 0 ? Theme.error : Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Math.round(root.corps * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            Repeater {
                model: root.unites.noms || []
                Text {
                    required property var modelData
                    width: colonne.width
                    text: "· " + String(modelData || "")
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.pixelSize: Math.round(root.corps * 0.8 * root.echelle)
                    elide: Text.ElideRight
                }
            }
        }

        // ── hôtes ────────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: parent.width > 0 && root.hotes.length > 0 ? 1 : 0
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Repeater {
            model: root.hotes

            Row {
                required property var modelData
                width: colonne.width

                Text {
                    width: parent.width - Math.round(86 * root.echelle)
                    text: String(modelData.nom || modelData.url || "")
                    color: modelData.joignable ? Theme.fg : Theme.error
                    font.pixelSize: Math.round(root.corps * 0.95 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(86 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.joignable
                          ? (modelData.latence_ms + " ms") : "injoignable"
                    color: modelData.joignable ? Qt.alpha(Theme.fg, 0.6) : Theme.error
                    font.pixelSize: Math.round(root.corps * 0.9 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            visible: root.charge && root.hotes.length === 0
            text: "aucun hôte déclaré (core/homelab.json)"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(root.corps * 0.85 * echelle)
        }
    }
}
