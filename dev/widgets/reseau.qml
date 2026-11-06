import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// RÉSEAU — la version « bureau » de l'applet du même nom.
//
// L'applet de la barre tient en une icône et un pourcentage. Ce widget dit le
// reste : bande et canal, débits négociés, adresse et passerelle, trafic réel,
// latence et VPN actif. Toute donnée absente (filaire, pas de VPN, passerelle
// muette) disparaît de sa ligne au lieu d'afficher un tiret.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var reseau: ({})
    property bool charge: false

    readonly property bool connecte: reseau && reseau.connecte === true
    readonly property string ssid: String(reseau.ssid || reseau.connexion || reseau.interface || "")
    readonly property int signalPct: Number(reseau.signal || 0)

    // Débit en octets/s → « 1,2 Mo/s ». Les compteurs du noyau sont en octets ;
    // le service les rend en kio/s pour rester lisible.
    function debit(valeur) {
        const v = Number(valeur || 0)
        if (!isFinite(v) || v <= 0) return "0"
        if (v >= 1024) return (Math.round(v / 102.4) / 10) + " Mo/s"
        return Math.round(v) + " ko/s"
    }

    function bande() {
        const b = String(reseau.bande || "")
        const c = reseau.canal
        if (b === "") return ""
        return c ? (b + " · canal " + c) : b
    }

    function reseauDe() {
        return String(reseau.ssid || reseau.connexion || "")
    }

    function rafraichir() {
        proc.command = ["python3", Quickshell.shellPath("core/reseau_widget.py")]
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.reseau = JSON.parse(text.trim())
                } catch (e) {
                    root.reseau = ({})
                }
                root.charge = true
            }
        }
    }

    // Largeur **fixe** : un ping qui passe de 6 à 1200 ms, ou un débit qui passe de
    // « 1 ko/s » à « 12,3 Mo/s », ne doit pas redimensionner la carte sous le
    // curseur. Les lignes se contentent de tronquer ce qui dépasse.
    implicitWidth: Math.round(252 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: 6

        // ── réseau et signal ────────────────────────────────────────────────
        Row {
            spacing: 8

            Text {
                text: root.connecte ? root.ssid : "hors ligne"
                color: Theme.fg
                font.pixelSize: Math.round(16 * root.echelle)
                font.bold: true
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.round(150 * root.echelle))
            }

            // Quatre barres, comme un indicateur Wi-Fi : plus parlant qu'un
            // pourcentage seul quand on jette un œil. Un Item les porte, une Row
            // n'accepte pas d'enfants ancrés en bas.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(21 * root.echelle)
                height: Math.round(17 * root.echelle)

                Repeater {
                    model: 4

                    Rectangle {
                        required property int index
                        readonly property int seuil: (index + 1) * 25
                        x: index * Math.round(5 * root.echelle)
                        width: Math.round(4 * root.echelle)
                        height: Math.round((4 + index * 3) * root.echelle)
                        anchors.bottom: parent.bottom
                        radius: 1
                        color: root.signalPct >= seuil
                            ? Theme.accent : Qt.alpha(Theme.fg, 0.18)
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.connecte ? root.signalPct + " %" : ""
                color: Qt.alpha(Theme.fg, 0.7)
                font.pixelSize: Math.round(12 * root.echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── radio ───────────────────────────────────────────────────────────
        Text {
            visible: root.bande() !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.bande()
                  + (root.reseau.dbm !== undefined ? " · " + root.reseau.dbm + " dBm" : "")
                  + (root.reseau.rx_mbps ? " · " + Math.round(root.reseau.rx_mbps) + " Mb/s" : "")
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Math.round(11.5 * root.echelle)
        }

        // ── adressage ───────────────────────────────────────────────────────
        Text {
            visible: root.reseau.ip !== undefined
            width: parent.width
            elide: Text.ElideRight
            text: String(root.reseau.ip || "")
                  + (root.reseau.prefixe !== undefined ? "/" + root.reseau.prefixe : "")
                  + (root.reseau.passerelle ? "  →  " + root.reseau.passerelle : "")
            color: Theme.fg
            font.pixelSize: Math.round(13 * root.echelle)
            font.features: { "tnum": 1 }
        }

        // ── latence ─────────────────────────────────────────────────────────
        // Sur sa propre ligne : un ping qui explose (1200 ms) allongeait la ligne
        // d'adressage et donc la carte.
        Text {
            visible: root.reseau.latence_ms !== undefined
            text: "ping " + root.reseau.latence_ms + " ms"
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(11.5 * root.echelle)
            font.features: { "tnum": 1 }
        }

        // ── trafic ──────────────────────────────────────────────────────────
        Row {
            spacing: 10

            Text {
                text: "↓ " + root.debit(root.reseau.rx_ko_s)
                color: Theme.fg
                font.pixelSize: Math.round(13.5 * root.echelle)
                font.features: { "tnum": 1 }
            }

            Text {
                text: "↑ " + root.debit(root.reseau.tx_ko_s)
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Math.round(13.5 * root.echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── VPN ─────────────────────────────────────────────────────────────
        Text {
            visible: root.reseau.vpn !== undefined && String(root.reseau.vpn || "") !== ""
            width: parent.width
            elide: Text.ElideRight
            text: "⛨ " + String(root.reseau.vpn || "")
            color: Theme.accent
            font.pixelSize: Math.round(11.5 * root.echelle)
            font.bold: true
        }

        Text {
            visible: root.charge && !root.connecte
            text: "aucune interface active"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(9.5 * root.echelle)
        }
    }
}
