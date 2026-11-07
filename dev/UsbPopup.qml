import QtQuick
import Quickshell
import Quickshell.Io

// POPUP « PÉRIPHÉRIQUES » — ce qui est branché, ce qui est monté, et les gestes
// qu'on peut faire dessus sans ouvrir un terminal.
//
// Source : `core/usb_applet.py`, qui lit sysfs, udev et mountinfo (aucun démon).
// Les actions passent par udisksctl, donc par polkit : ce que l'utilisateur n'a
// pas le droit de faire échoue avec le message du système, jamais en silence.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property real corps: Theme.textXs * 1.15

    property var etat: ({})
    readonly property var disques: root.etat.disques || []
    // Le périphérique dont la phrase de déverrouillage est saisie.
    property string deverrouillage: ""
    property string phrase: ""
    property string dernierMessage: ""

    function charger() {
        proc.running = false
        proc.running = true
    }

    function agir(geste, cible) {
        action.nom = String(geste)
        action.cible = String(cible)
        action.running = false
        action.running = true
    }

    function tailles(o) {
        const go = Number(o || 0) / 1073741824
        if (go >= 1000) return (go / 1000).toFixed(1).replace(".", ",") + " To"
        if (go >= 1) return Math.round(go) + " Go"
        return Math.round(go * 1000) + " Mo"
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    // Un disque peut être branché ou monté pendant que le panneau est ouvert.
    Timer {
        interval: 4000
        running: root.ouvert
        repeat: true
        onTriggered: root.charger()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/usb_applet.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail && d.detail.usb) ? d.detail.usb : d
                } catch (e) {
                    root.etat = ({})
                }
            }
        }
    }

    Process {
        id: action
        property string nom: ""
        property string cible: ""
        // « deverrouiller » a besoin de la phrase : un tableau de commande ne
        // peut pas varier en longueur, donc deux Process et un choix à l'appel.
        command: nom === "deverrouiller"
                 ? ["python3", Quickshell.shellPath("core/usb_applet.py"), nom, cible,
                    "--phrase", root.phrase]
                 : ["python3", Quickshell.shellPath("core/usb_applet.py"), nom, cible]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.dernierMessage = d.ok ? "" : String(d.message || "échec")
                } catch (e) {
                    root.dernierMessage = ""
                }
            }
        }
        onExited: {
            root.phrase = ""
            root.deverrouillage = ""
            root.charger()
        }
    }

    implicitWidth: Math.round(324 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(7 * echelle)

        Row {
            width: parent.width

            Text {
                width: parent.width - Math.round(80 * echelle)
                text: "Périphériques"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
            }

            Text {
                width: Math.round(80 * echelle)
                horizontalAlignment: Text.AlignRight
                text: root.disques.length > 0
                      ? root.disques.length + (root.disques.length > 1 ? " branchés" : " branché")
                      : ""
                color: Qt.alpha(Theme.accent, 0.85)
                font.pixelSize: Math.round(root.corps * 0.8 * echelle)
            }
        }

        Text {
            width: parent.width
            visible: root.disques.length === 0
            text: "Aucun périphérique amovible branché."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(root.corps * 0.9 * echelle)
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.disques

            Column {
                id: blocDisque
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                // ── le disque ────────────────────────────────────────────────
                Row {
                    width: parent.width
                    spacing: Math.round(6 * echelle)

                    Icon {
                        glyph: blocDisque.modelData.optique ? "disc"
                              : blocDisque.modelData.bus === "usb" ? "usb" : "harddisk"
                        size: root.corps * 1.1
                        color: blocDisque.modelData.monte ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        // La somme des largeurs doit tenir : icône (13) + trois
                        // espacements (18) + la colonne de droite (90). Oublier
                        // l'icône poussait la taille hors de la carte, où elle
                        // était rognée à « 14 G ».
                        width: parent.width - Math.round(122 * echelle)
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(blocDisque.modelData.modele || blocDisque.modelData.nom)
                        color: Theme.fg
                        font.pixelSize: Math.round(root.corps * 0.92 * echelle)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: Math.round(90 * echelle)
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.tailles(blocDisque.modelData.taille_o)
                              + (blocDisque.modelData.bus !== "usb" && blocDisque.modelData.bus !== "?"
                                 ? "  " + String(blocDisque.modelData.bus).toUpperCase() : "")
                        color: Qt.alpha(Theme.fg, 0.45)
                        font.pixelSize: Math.round(root.corps * 0.78 * echelle)
                        font.features: { "tnum": 1 }
                    }
                }

                // ── les volumes ──────────────────────────────────────────────
                Repeater {
                    model: blocDisque.modelData.volumes || []

                    Column {
                        id: blocVolume
                        required property var modelData
                        // `index` n'est pas garanti dans un délégué imbriqué : sans
                        // cette déclaration, « retirer » (réservé au premier
                        // volume) ne s'affichait jamais.
                        required property int index
                        readonly property string dev: String(modelData.dev || "")
                        width: blocDisque.width
                        spacing: Math.round(3 * echelle)

                        Row {
                            width: parent.width
                            spacing: Math.round(6 * echelle)

                            Text {
                                width: Math.round(10 * echelle)
                                text: "·"
                                color: Qt.alpha(Theme.fg, 0.35)
                                font.pixelSize: Math.round(root.corps * echelle)
                            }

                            Text {
                                width: parent.width - Math.round(163 * echelle)
                                text: String(blocVolume.modelData.etiquette
                                             || blocVolume.modelData.fs || blocVolume.modelData.nom)
                                      + (blocVolume.modelData.chiffre ? "  (chiffré)" : "")
                                color: blocVolume.modelData.montage ? Theme.fg
                                                                    : Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: Math.round(root.corps * 0.85 * echelle)
                                elide: Text.ElideRight
                            }

                            Text {
                                width: Math.round(140 * echelle)
                                horizontalAlignment: Text.AlignRight
                                text: blocVolume.modelData.montage
                                      ? String(blocVolume.modelData.montage).replace(/^\/run\/media\/[^/]+\//, "")
                                      : (blocVolume.modelData.chiffre ? "verrouillé" : "non monté")
                                color: Qt.alpha(Theme.fg, 0.4)
                                font.pixelSize: Math.round(root.corps * 0.75 * echelle)
                                elide: Text.ElideRight
                            }
                        }

                        // ── gestes ──────────────────────────────────────────
                        Row {
                            spacing: Math.round(5 * echelle)
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(16 * echelle)

                            Repeater {
                                model: {
                                    const v = blocVolume.modelData
                                    if (v.echange) return []
                                    if (v.chiffre) {
                                        return v.montage
                                            ? [{ t: "verrouiller", a: "verrouiller" }]
                                            : [{ t: "déverrouiller", a: "deverrouiller" }]
                                    }
                                    const l = []
                                    if (!v.montage) l.push({ t: "monter", a: "monter" })
                                    else {
                                        l.push({ t: "ouvrir", a: "ouvrir" })
                                        l.push({ t: "démonter", a: "demonter" })
                                    }
                                    return l
                                }

                                Rectangle {
                                    required property var modelData
                                    width: Math.round(76 * echelle)
                                    height: Math.round(20 * echelle)
                                    radius: Math.round(5 * echelle)
                                    color: Qt.alpha(Theme.fg, 0.08)
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.fg, 0.18)

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(modelData.t)
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Math.round(root.corps * 0.75 * echelle)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.a === "ouvrir") {
                                                root.agir("ouvrir", String(blocVolume.modelData.montage))
                                            } else if (modelData.a === "deverrouiller") {
                                                root.deverrouillage =
                                                    root.deverrouillage === blocVolume.dev ? "" : blocVolume.dev
                                            } else {
                                                root.agir(modelData.a, blocVolume.dev)
                                            }
                                        }
                                    }
                                }
                            }

                            // « retirer » se joue sur le disque, pas sur le volume.
                            Rectangle {
                                width: Math.round(64 * echelle)
                                height: Math.round(20 * echelle)
                                radius: Math.round(5 * echelle)
                                visible: blocVolume.index === 0 && !blocDisque.modelData.systeme
                                color: Qt.alpha(Theme.warn, 0.14)
                                border.width: 1
                                border.color: Qt.alpha(Theme.warn, 0.4)

                                Text {
                                    anchors.centerIn: parent
                                    text: "retirer"
                                    color: Theme.warn
                                    font.pixelSize: Math.round(root.corps * 0.75 * echelle)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.agir("retirer", String(blocDisque.modelData.nom))
                                }
                            }
                        }

                        // Phrase de déverrouillage, demandée au clic sur le geste.
                        Row {
                            width: parent.width
                            spacing: Math.round(5 * echelle)
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(16 * echelle)
                            visible: root.deverrouillage === blocVolume.dev
                                     && Boolean(blocVolume.modelData.chiffre)
                                     && !Boolean(blocVolume.modelData.montage)

                            Rectangle {
                                width: parent.width - Math.round(86 * echelle)
                                height: Math.round(22 * echelle)
                                radius: Math.round(5 * echelle)
                                color: Qt.alpha(Theme.fg, 0.06)
                                border.width: 1
                                border.color: Qt.alpha(Theme.accent, 0.4)

                                TextInput {
                                    id: champPhrase
                                    anchors.fill: parent
                                    anchors.leftMargin: Math.round(6 * echelle)
                                    anchors.rightMargin: Math.round(6 * echelle)
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.fg
                                    echoMode: TextInput.Password
                                    font.pixelSize: Math.round(root.corps * 0.8 * echelle)
                                    onTextChanged: root.phrase = text
                                    onAccepted: root.agir("deverrouiller", blocVolume.dev)
                                }
                            }

                            Rectangle {
                                width: Math.round(80 * echelle)
                                height: Math.round(22 * echelle)
                                radius: Math.round(5 * echelle)
                                color: Qt.alpha(Theme.accent, 0.16)
                                border.width: 1
                                border.color: Qt.alpha(Theme.accent, 0.45)

                                Text {
                                    anchors.centerIn: parent
                                    text: "ouvrir"
                                    color: Theme.accent
                                    font.pixelSize: Math.round(root.corps * 0.75 * echelle)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.phrase.length > 0
                                    onClicked: root.agir("deverrouiller", blocVolume.dev)
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.dernierMessage !== ""
            text: root.dernierMessage
            color: Theme.warn
            wrapMode: Text.WordWrap
            font.pixelSize: Math.round(root.corps * 0.8 * echelle)
        }
    }

}
