import QtQuick
import Quickshell
import Quickshell.Io

// POPUP HERMES — l'état de l'agent, ce qu'il fait, ce qui l'attend.
//
// Le shell lit un fichier d'état écrit par Hermes (voir core/hermes_applet.py).
// Aucun appel réseau, aucune socket : le popup ne fait que rendre ce que
// l'agent publie, et dit « aucun état » quand il ne publie rien.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    // Un panneau se lit à 60 cm : même corps que le popup homelab.
    readonly property real corps: Theme.textXs * 1.15

    property var etat: ({})
    property bool charge: false

    // Répondre à une demande : le démon tient la socket, le CLI envoie le
    // verdict, puis on relit l'état pour que la ligne disparaisse tout de suite.
    function repondre(id, verdict) {
        action.verdict = verdict
        action.identifiant = id
        action.running = false
        action.running = true
    }

    function charger() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    // Une demande d'approbation peut arriver alors que le popup est déjà ouvert :
    // sans cette relecture, elle n'apparaîtrait qu'après l'avoir fermé et rouvert.
    // Cinq secondes, et seulement pendant l'ouverture — le reste du temps, rien.
    Timer {
        interval: 5000
        running: root.ouvert
        repeat: true
        onTriggered: root.charger()
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
        id: action
        property string identifiant: ""
        property string verdict: "oui"
        command: ["python3", Quickshell.shellPath("core/hermes_approbations.py"),
                  "repondre", action.identifiant, action.verdict]
        onExited: root.charger()
    }

    implicitWidth: Math.round(324 * echelle)
    implicitHeight: colonne.implicitHeight

    // Couleur d'état : l'erreur et l'attente se voient, le repos s'efface.
    readonly property color teinte: root.etat.etat === "erreur" ? Theme.error
                                     : root.etat.etat === "attente" ? Theme.warn
                                     : root.etat.etat === "en_cours" ? Theme.accent
                                     : Qt.alpha(Theme.fg, 0.55)

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(6 * echelle)

        Text {
            text: "Hermes"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
        }

        // ── état et tâche en cours ───────────────────────────────────────────
        Row {
            width: parent.width
            spacing: Math.round(6 * echelle)

            Rectangle {
                width: Math.round(6 * echelle)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.teinte
            }

            Text {
                width: parent.width - Math.round(10 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: root.etat.etat === undefined ? "aucun état"
                      : (String(root.etat.libelle || root.etat.etat)
                         + (root.etat.tache ? " — " + String(root.etat.tache) : ""))
                color: root.etat.etat === "erreur" || root.etat.etat === "attente"
                       ? root.teinte : Theme.fg
                font.pixelSize: Math.round(root.corps * echelle)
                elide: Text.ElideRight
            }
        }

        Text {
            width: parent.width
            visible: root.etat.etat === "hors_ligne" || root.etat.etat === undefined
            text: "Hermes ne publie rien (état absent de " + "quickshell/hermes-etat.json" + ")"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(root.corps * 0.85 * echelle)
            wrapMode: Text.WordWrap
        }

        // ── file et jetons ──────────────────────────────────────────────────
        Row {
            width: parent.width
            visible: root.etat.etat !== undefined && root.etat.etat !== "hors_ligne"

            Text {
                width: parent.width - Math.round(90 * echelle)
                text: "En file"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(root.corps * 0.9 * echelle)
            }

            Text {
                width: Math.round(90 * echelle)
                horizontalAlignment: Text.AlignRight
                text: String(root.etat.file || 0)
                      + (root.etat.jetons && root.etat.jetons.jour
                         ? "  ·  " + String(root.etat.jetons.jour) + " j" : "")
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Math.round(root.corps * 0.9 * echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── approbations en attente ─────────────────────────────────────────
        // Le démon publie les demandes ; ce bloc les rend cliquables. Deux
        // Repeater imbriqués : la demande (titre, détail) puis ses deux verdicts.
        Column {
            width: parent.width
            spacing: Math.round(8 * echelle)
            visible: (root.etat.approbations || []).length > 0

            Repeater {
                model: root.etat.approbations || []

                Column {
                    id: blocDemande
                    required property var modelData
                    // L'identifiant vient de la demande, pas du bouton : sans cette
                    // copie, le clic viserait le modelData du Repeater intérieur.
                    readonly property string demandeId: String(modelData.id || "")
                    width: parent.width
                    spacing: Math.round(4 * echelle)

                    Text {
                        width: parent.width
                        text: String(modelData.titre || "")
                        color: Theme.warn
                        font.pixelSize: Math.round(root.corps * echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: Boolean(modelData.detail)
                        text: String(modelData.detail || "")
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: Math.round(6 * echelle)

                        Repeater {
                            model: [{ "texte": "accorder", "verdict": "oui", "teinte": Theme.accent },
                                    { "texte": "refuser", "verdict": "non", "teinte": Qt.alpha(Theme.fg, 0.5) }]

                            Rectangle {
                                required property var modelData
                                width: Math.round(76 * echelle)
                                height: Math.round(22 * echelle)
                                radius: Math.round(6 * echelle)
                                color: Qt.alpha(modelData.teinte, 0.16)
                                border.width: 1
                                border.color: Qt.alpha(modelData.teinte, 0.45)

                                Text {
                                    anchors.centerIn: parent
                                    text: String(modelData.texte)
                                    color: modelData.teinte
                                    font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.repondre(blocDemande.demandeId,
                                                             String(modelData.verdict))
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── dernières exécutions ────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: (root.etat.executions || []).length > 0 ? 1 : 0
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Repeater {
            model: root.etat.executions || []

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(6 * echelle)

                Rectangle {
                    width: Math.round(5 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: String(modelData.resultat) === "ok" ? Theme.accent : Theme.error
                }

                Text {
                    width: parent.width - Math.round(64 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.nom || "")
                    color: Theme.fg
                    font.pixelSize: Math.round(root.corps * 0.9 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(58 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: Number(modelData.duree_s || 0) + " s"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }

        // ── tâches planifiées ───────────────────────────────────────────────
        Repeater {
            model: root.etat.cron || []

            Row {
                required property var modelData
                width: colonne.width

                Text {
                    width: parent.width - Math.round(84 * echelle)
                    text: String(modelData.nom || "")
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(84 * echelle)
                    horizontalAlignment: Text.AlignRight
                    text: String(modelData.prochaine || "").replace("T", " ").slice(5, 16)
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(root.corps * 0.8 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
