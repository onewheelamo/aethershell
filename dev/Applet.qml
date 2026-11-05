import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET DE BARRE — une icône, une valeur, un popup.
//
// Ce composant ne sait rien de ce qu'il affiche : il lance le service déclaré
// dans le catalogue (`applets_catalogue.json`), lit le contrat
// (core/applet_contrat.py) et dessine. Un applet de plus = une entrée de
// catalogue + un service ; aucun QML à écrire.
//
// La barre ne montre qu'une valeur (`compact.valeur`) : c'est le service qui
// choisit ce qui compte, parce que lui seul sait ce qui est grave.
Item {
    id: root
    // Entrée résolue par bar_applets.py : id, nom, icone, service, popup,
    // cadence, text_scale, options.
    property var applet: ({})

    readonly property string appletId: String(applet.id || "")
    readonly property string service: String(applet.service || "")
    readonly property real echelle: {
        const v = Number(applet.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property int cadenceMin: {
        const v = Number(applet.cadence)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    property var donnees: ({})
    property bool charge: false
    property bool occupe: false

    readonly property bool ok: charge && donnees && donnees.ok === true
    readonly property var ligne: (ok && donnees.compact) ? donnees.compact : ({})
    readonly property bool alerte: ok && donnees.alerte === true
    // « … » tant que le service n'a pas répondu, « — » s'il a échoué : dans les
    // deux cas on n'invente pas de valeur.
    readonly property string valeur: ok ? String(ligne.valeur || "")
                                       : (charge ? "—" : "…")
    readonly property string infobulle: {
        if (!ok) return String((donnees && donnees.error) || "")
        const libelle = String(ligne.libelle || "")
        const nom = String(applet.nom || "")
        return libelle !== "" ? nom + " · " + libelle : nom
    }
    // Un seul popup ouvert à la fois, et il est identifié par son applet : deux
    // applets ne peuvent donc pas s'ouvrir l'un sur l'autre.
    readonly property bool ouvert: Theme.activePopup === "applet:" + appletId

    implicitWidth: contenu.implicitWidth
    implicitHeight: contenu.implicitHeight

    function rafraichir(force) {
        if (root.service === "" || root.occupe) return
        root.occupe = true
        const args = ["python3", Quickshell.shellPath(root.service)]
        if (force) args.push("--force")
        proc.command = args
        proc.running = true
    }

    onServiceChanged: if (root.service !== "") root.rafraichir(false)
    Component.onCompleted: if (root.service !== "") root.rafraichir(false)

    Timer {
        interval: root.cadenceMin * 60000
        repeat: true
        // La cadence choisie est la cadence réelle : sans --force, le cache du
        // service ignorerait un réglage à 1 ou 2 minutes.
        onTriggered: root.rafraichir(true)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.donnees = JSON.parse(text.trim())
                } catch (e) {
                    root.donnees = { ok: false, error: "réponse illisible" }
                }
                root.charge = true
                root.occupe = false
            }
        }
        onExited: root.occupe = false
    }

    Row {
        id: contenu
        spacing: Math.max(3, Math.round(Theme.space2 * root.echelle))

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: String(root.applet.icone || "circle")
            size: Math.max(10, Math.round(Theme.iconSm * root.echelle))
            color: root.alerte ? Theme.warn : Theme.fg
            opacityLevel: root.ok ? 0.92 : 0.45
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.valeur
            visible: text !== ""
            color: root.alerte ? Theme.warn : Theme.fg
            font.pixelSize: Math.round(Theme.textXs * root.echelle)
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Theme.activePopup = root.ouvert ? "" : ("applet:" + root.appletId)
            // Une ouverture est aussi une occasion de rafraîchir le détail.
            if (!root.ouvert) root.rafraichir(true)
        }
    }

    // ── popup ────────────────────────────────────────────────────────────────
    // Le contenu vient du catalogue (`popup`) : l'applet « comptes » charge le
    // composant des widgets de compte, donc le détail n'est pas réécrit ici.
    PopupWindow {
        id: fenetre
        anchor.item: root
        anchor.rect.x: 0
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
        implicitWidth: Math.ceil(chargeur.implicitWidth + Theme.space4 * 2)
        implicitHeight: Math.ceil(chargeur.implicitHeight + Theme.space4 * 2)
        color: "transparent"
        visible: root.ouvert

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Loader {
                id: chargeur
                anchors.centerIn: parent
                source: String(root.applet.popup || "") === ""
                        ? "" : "file://" + Quickshell.shellPath(root.applet.popup)
                onLoaded: {
                    if (!item) return
                    item.options = {
                        text_scale: root.applet.text_scale,
                        entete: true,
                        services: (root.applet.options || {}).services
                    }
                    item.widgetId = ""
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: root.ouvert
        windows: [fenetre]
        onCleared: {
            if (Theme.activePopup === "applet:" + root.appletId) Theme.activePopup = ""
        }
    }
}
