import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET ALIMENTATION — les cinq gestes de session, et rien d'autre.
//
// Il ne concerne QUE la session : verrouiller, veiller, redémarrer, éteindre,
// fermer. La batterie, la limite de charge à 80 % et la luminosité sont parties
// dans l'applet « gestion-energie » (GestionEnergieApplet.qml) : deux sujets,
// deux panneaux. Sans ce bloc matériel, celui-ci peut se dessiner en une rangée
// de tuiles carrées au lieu d'une colonne de lignes à sous-titre.
//
// Géométrie empruntée à une capture de référence (menu « Session » d'un shell
// niri) : carte large et basse, en-tête sur une ligne — titre à gauche, machine
// à droite — puis cinq tuiles de largeur égale, icône au-dessus du libellé. Les
// couleurs restent celles du thème ; c'est la taille et la disposition qui sont
// reprises.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    property string hote: ""
    readonly property bool ouvert: Theme.activePopup === "applet:alimentation"

    readonly property real cote: Math.max(18, Math.round(Theme.barHeight * 0.70 * echelle))

    implicitWidth: cote
    implicitHeight: cote

    // ── proportions du panneau ──────────────────────────────────────────────
    // Mesurées sur la référence puis arrondies aux tokens du thème : carte à
    // ~43 % de la largeur d'un écran 1080p, tuiles un peu plus larges que
    // hautes, écart d'un huitième de tuile, marge intérieure franche. La hauteur
    // suit le contenu (en-tête + tuiles + marges), jamais une valeur en dur :
    // une carte figée coupait la dernière ligne quand la police grandissait.
    readonly property int largeurCarte: 820
    readonly property int marge: 26
    readonly property int ecartTuile: 16
    readonly property int hauteurTuile: 138
    readonly property int largeurTuile: Math.round((largeurCarte - 2 * marge - 4 * ecartTuile) / 5)

    // Ordre de la référence : verrouiller, veiller, redémarrer, éteindre,
    // fermer la session. Les deux gestes destructifs restent en rouge.
    readonly property var gestes: [
        { icon: "lock",    label: "Verrouiller", cmd: "hyprlock || loginctl lock-session", danger: false },
        { icon: "sleep",   label: "Veille",      cmd: "systemctl suspend", danger: false },
        { icon: "restart", label: "Redémarrer",  cmd: "systemctl reboot", danger: true },
        { icon: "power",   label: "Éteindre",    cmd: "systemctl poweroff", danger: true },
        { icon: "logout",  label: "Déconnexion", cmd: "hyprctl dispatch 'hl.dsp.exit()' || hyprctl dispatch exit", danger: false }
    ]

    // Le nom de l'hôte est lu une fois au chargement : `running: true` est
    // obligatoire, un Process dont on ne remplit que `command` ne démarre pas
    // (l'ancien menu affichait donc « Relancer la machine » sans nom).
    Process {
        running: true
        command: ["sh", "-c", "cat /proc/sys/kernel/hostname"]
        stdout: StdioCollector {
            onStreamFinished: root.hote = text.trim()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.min(Theme.globalRadius, Math.round(root.cote / 2))
        color: root.ouvert
            ? Theme.error
            : (souris.containsMouse ? Qt.alpha(Theme.error, 0.16) : "transparent")
        border.color: root.ouvert ? Theme.error : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: 160 } }

        Icon {
            anchors.centerIn: parent
            glyph: "power"
            size: Math.max(11, Math.round(Theme.iconSm * root.echelle))
            color: root.ouvert ? Theme.bg : (souris.containsMouse ? Theme.error : Theme.fg)
            opacityLevel: root.ouvert ? 1 : 0.85
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("applet:alimentation")
        }
    }

    // ── menu ────────────────────────────────────────────────────────────────
    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "droite"
        id: menu
        implicitWidth: root.largeurCarte
        implicitHeight: carte.implicitHeight
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            id: carte
            anchors.fill: parent
            implicitHeight: contenu.implicitHeight + root.marge * 2
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.error
            border.width: 1

            Column {
                id: contenu
                anchors.fill: parent
                anchors.margins: root.marge
                spacing: 18

                // En-tête : le titre à gauche, la machine à droite (la référence
                // affiche un chemin de dossier à cet endroit ; ici c'est le nom
                // de l'hôte, la seule information équivalente qu'on ait).
                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Session"
                        color: Theme.fg
                        font.pixelSize: Theme.textMd
                        font.bold: true
                        font.letterSpacing: 0.4
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hote
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }
                }

                Row {
                    width: parent.width
                    spacing: root.ecartTuile

                    Repeater {
                        model: root.gestes

                        Rectangle {
                            id: tuile
                            required property var modelData
                            width: root.largeurTuile
                            height: root.hauteurTuile
                            radius: Theme.globalRadius
                            color: tuileMa.containsMouse
                                ? (tuile.modelData.danger
                                    ? Qt.alpha(Theme.error, 0.22)
                                    : Qt.alpha(Theme.accent, 0.16))
                                : Qt.alpha(Theme.surfaceVariant, 0.42)
                            border.color: tuileMa.containsMouse
                                ? (tuile.modelData.danger ? Theme.error : Theme.accent)
                                : Qt.alpha(Theme.fg, 0.07)
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on border.color { ColorAnimation { duration: 140 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 12

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    glyph: tuile.modelData.icon
                                    size: Theme.iconLg
                                    color: tuile.modelData.danger ? Theme.error : Theme.fg
                                    opacityLevel: 1
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tuile.modelData.label
                                    color: tuile.modelData.danger ? Theme.error : Theme.fg
                                    font.pixelSize: Theme.textSm
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: tuileMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.activePopup = ""
                                    Quickshell.execDetached(["sh", "-c", tuile.modelData.cmd])
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) delaiGrab.restart()
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.ouvert && root.pretGrab
        windows: [menu]
        onCleared: if (root.ouvert) Theme.activePopup = ""
    }
}
