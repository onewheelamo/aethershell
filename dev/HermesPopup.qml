import QtQuick
import Quickshell
import Quickshell.Io

// POPUP HERMES — l'agent, ses sessions, ce qui l'attend.
//
// Source : `core/hermes_applet.py`, qui lit la base de Hermes en lecture seule
// (`core/hermes_lecteur.py`). Aucun appel réseau : les sessions viennent de
// `state.db`, les approbations du canal local de `hermes_approbations.py`.
//
// La liste est celle des sessions, pas celle des « exécutions » : une session
// qui tourne, qui vient de finir ou qui tourne dans un autre profil sont la même
// ligne, seul le point de couleur et la valeur de droite changent.
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

    // Nombre de sessions visibles : au-delà, la liste ne dit plus rien.
    readonly property int maxSessions: 6
    readonly property var sessions: (root.etat.sessions || []).slice(0, root.maxSessions)
    readonly property int actives: (root.etat.profils || []).length

    // Jetons en forme courte : un chiffre à sept positions dans une barre ne se
    // lit pas, « 3,4 M » si.
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

        // ── en-tête ─────────────────────────────────────────────────────────
        Row {
            width: parent.width

            Text {
                width: parent.width - Math.round(96 * echelle)
                text: "Hermes"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
            }

            Text {
                width: Math.round(96 * echelle)
                horizontalAlignment: Text.AlignRight
                visible: root.actives > 0
                text: root.actives > 1 ? root.actives + " sessions" : "1 session"
                color: Qt.alpha(Theme.accent, 0.85)
                font.pixelSize: Math.round(root.corps * 0.8 * echelle)
            }
        }

        // ── état et tâche en cours ──────────────────────────────────────────
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
            text: "Base illisible (" + String(root.etat.raison || "state.db") + ")"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(root.corps * 0.85 * echelle)
            wrapMode: Text.WordWrap
        }

        // ── jetons du jour ──────────────────────────────────────────────────
        Row {
            width: parent.width
            visible: root.etat.etat !== undefined && root.etat.etat !== "hors_ligne"

            Text {
                width: parent.width - Math.round(90 * echelle)
                text: "Jetons aujourd'hui"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(root.corps * 0.9 * echelle)
            }

            Text {
                width: Math.round(90 * echelle)
                horizontalAlignment: Text.AlignRight
                text: root.jeton(root.etat.jetons ? root.etat.jetons.jour : 0)
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

        // ── sessions ────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: root.sessions.length > 0 ? 1 : 0
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Repeater {
            model: root.sessions

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(6 * echelle)

                Rectangle {
                    width: Math.round(5 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    // Accent = tourne, gris = finie, atténué = ouverte mais muette.
                    color: modelData.vivante ? Theme.accent
                           : String(modelData.etat) === "inactive"
                             ? Qt.alpha(Theme.fg, 0.22) : Qt.alpha(Theme.fg, 0.45)
                }

                Text {
                    width: Math.round(46 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.profil || "")
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.round(root.corps * 0.78 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width - Math.round(146 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.titre || modelData.tache || "session sans titre")
                    color: modelData.vivante ? Theme.fg : Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Math.round(root.corps * 0.88 * echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: Math.round(52 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    // Une session qui tourne se mesure en jetons, une session finie
                    // en durée : les deux disent ce qu'on veut savoir d'elle.
                    text: modelData.vivante ? root.jeton(modelData.jetons)
                                            : root.duree(modelData.duree_s)
                    color: Qt.alpha(Theme.fg, modelData.vivante ? 0.75 : 0.45)
                    font.pixelSize: Math.round(root.corps * 0.82 * echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
