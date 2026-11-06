import QtQuick
import Quickshell
import Quickshell.Io

// POPUP HOMELAB — conteneurs, unités en échec, hôtes.
//
// Même source que l'applet (core/homelab_applet.py). Les hôtes surveillés
// viennent de core/homelab.json ; sans ce fichier, seuls les conteneurs et les
// unités sont montrés — l'applet ne prétend rien savoir d'un parc qu'on ne lui a
// pas décrit.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }

    property var conteneurs: ({})
    property var unites: ({})
    property var hotes: []
    property var proxmox: ({})
    property bool charge: false

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
                    root.conteneurs = det.conteneurs || ({})
                    root.unites = det.unites || ({})
                    root.hotes = det.hotes || []
                    root.proxmox = det.proxmox || ({})
                } catch (e) {
                    root.conteneurs = ({})
                    root.unites = ({})
                    root.hotes = []
                    root.proxmox = ({})
                }
                root.charge = true
            }
        }
    }

    implicitWidth: Math.round(300 * echelle)
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

        // ── conteneurs ───────────────────────────────────────────────────────
        Row {
            width: parent.width
            visible: root.conteneurs.total !== undefined

            Text {
                width: parent.width - Math.round(70 * root.echelle)
                text: "Conteneurs"
                color: Theme.fg
                font.pixelSize: Math.round(Theme.textXs * root.echelle)
            }

            Text {
                width: Math.round(70 * root.echelle)
                horizontalAlignment: Text.AlignRight
                text: String(root.conteneurs.en_cours || 0) + " / "
                      + String(root.conteneurs.total || 0)
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Math.round(Theme.textXs * root.echelle)
                font.features: { "tnum": 1 }
            }
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
                font.pixelSize: Math.round(Theme.textXs * 0.9 * root.echelle)
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.proxmox.noeuds || []

                Column {
                    required property var modelData
                    width: colonne.width
                    spacing: 1

                    Row {
                        width: parent.width

                        Text {
                            width: parent.width - Math.round(70 * root.echelle)
                            text: "Nœud " + String(modelData.nom || "")
                            color: modelData.en_ligne ? Theme.fg : Theme.error
                            font.pixelSize: Math.round(Theme.textXs * root.echelle)
                        }

                        Text {
                            width: Math.round(70 * root.echelle)
                            horizontalAlignment: Text.AlignRight
                            text: modelData.uptime_j + " j"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Math.round(Theme.textXs * 0.9 * root.echelle)
                            font.features: { "tnum": 1 }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "CPU " + modelData.cpu + " % · RAM "
                              + (modelData.ram_go !== null ? modelData.ram_go + "/" + modelData.ram_max_go + " Go" : "—")
                              + (modelData.ram !== null ? " (" + modelData.ram + " %)" : "")
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Math.round(Theme.textXs * 0.85 * root.echelle)
                    }
                }
            }

            Row {
                width: parent.width
                visible: root.proxmox.total !== undefined

                Text {
                    width: parent.width - Math.round(70 * root.echelle)
                    text: "Machines"
                    color: Theme.fg
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
                }

                Text {
                    width: Math.round(70 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(root.proxmox.en_cours || 0) + " / " + String(root.proxmox.total || 0)
                    color: Qt.alpha(Theme.fg, 0.75)
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            Repeater {
                model: (root.proxmox.vms || []).filter(function (v) { return v.etat !== "running" })
                Text {
                    required property var modelData
                    width: colonne.width
                    text: "· " + String(modelData.nom || modelData.id || "") + " ("
                          + String(modelData.etat || "") + ")"
                    color: Theme.warn
                    font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
                    elide: Text.ElideRight
                }
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
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
                }

                Text {
                    width: Math.round(70 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(root.unites.nombre || 0)
                    color: root.unites.nombre > 0 ? Theme.error : Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Math.round(Theme.textXs * root.echelle)
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
                    font.pixelSize: Math.round(Theme.textXs * 0.8 * root.echelle)
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
                    font.pixelSize: Math.round(Theme.textXs * 0.95 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(86 * root.echelle)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.joignable
                          ? (modelData.latence_ms + " ms") : "injoignable"
                    color: modelData.joignable ? Qt.alpha(Theme.fg, 0.6) : Theme.error
                    font.pixelSize: Math.round(Theme.textXs * 0.9 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        Text {
            visible: root.charge && root.hotes.length === 0
            text: "aucun hôte déclaré (core/homelab.json)"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(Theme.textXs * 0.85 * echelle)
        }
    }
}
