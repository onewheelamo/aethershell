import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// APPLET NOTIFICATIONS — la cloche et son compteur.
//
// Le centre de notifications (serveur, toasts, historique, actions) reste dans
// l'îlot droit : c'est un service, pas un élément de barre. L'applet n'est que
// le bouton — elle ouvre la même clé `notifications`, que le panneau écoute.
// Le compteur lui est passé par `Theme.notifCount`, pont posé par l'îlot qui
// possède la liste : un applet ne peut pas lire les identifiants d'un autre
// fichier.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    // Barre de côté : une seule icône, agrandie, et pas de texte — une valeur
    // coupée au milieu se lit mal. Le nom de l'applet est au survol, le détail
    // dans le popup. `Applet.qml` pose la propriété si elle existe.
    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    readonly property bool ouvert: Theme.activePopup === "notifications"

    // Le panneau est déclaré plus bas dans ce fichier : il s'ouvre donc collé à
    // la cloche, quel que soit l'endroit où elle est placée dans la barre.
    // Les listes viennent du singleton Theme par des affectations explicites :
    // une liaison sur un `property var` d'un singleton ne se réévalue pas de
    // façon fiable quand l'îlot remplace le tableau (même piège que les options
    // d'applet), et le panneau restait vide.
    property var notifications: []

    // Le pont d'actions est posé par l'ilot droit à son achèvement : tant qu'il
    // ne l'est pas, appeler Theme.notifOps.actions lèverait un TypeError et
    // casserait tout le panneau. Ces enveloppes rendent le pont facultatif.
    function actionsDe(e) { return (Theme.notifOps && Theme.notifOps.actions) ? Theme.notifOps.actions(e) : [] }
    function aCible(e) { return (Theme.notifOps && Theme.notifOps.hasTarget) ? Theme.notifOps.hasTarget(e) : false }
    function oublier(e) { if (Theme.notifOps && Theme.notifOps.forget) Theme.notifOps.forget(e) }
    function ouvrir(e, fermer) { if (Theme.notifOps && Theme.notifOps.open) Theme.notifOps.open(e, fermer) }
    function invoquer(e, ident) { if (Theme.notifOps && Theme.notifOps.invoke) Theme.notifOps.invoke(e, ident) }
    function toutEffacer() { if (Theme.notifOps && Theme.notifOps.clear) Theme.notifOps.clear() }
    function rendreMuet(nom, muet) { if (Theme.notifOps && Theme.notifOps.setQuiet) Theme.notifOps.setQuiet(nom, muet) }

    function majListe() {
        const vive = Theme.notifList || []
        root.notifications = vive.length > 0 ? vive : root.archive
    }

    // Historique lu ici, directement sur le fichier : le passage par une
    // propriété du singleton ne se rafraîchissait pas (tableau remplacé), et le
    // panneau restait vide alors que l'historique contenait bien les entrées.
    property var archive: []

    FileView {
        path: {
            const xdg = Quickshell.env("XDG_CACHE_HOME")
            const base = xdg ? String(xdg)
                             : (Quickshell.env("HOME") ? String(Quickshell.env("HOME")) + "/.cache" : "")
            return base + "/quickshell/notifications-history.jsonl"
        }
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lireHistorique(text())
        onTextChanged: root.lireHistorique(text())
    }

    function lireHistorique(txt) {
        const lignes = String(txt || "").split("\n")
        const out = []
        for (let i = lignes.length - 1; i >= 0 && out.length < 6; i--) {
            const l = lignes[i].trim()
            if (l === "") continue
            try {
                const e = JSON.parse(l)
                if (!e || !e.id) continue
                out.push({
                    id: e.id,
                    appName: e.app || "",
                    summary: e.summary || "",
                    body: e.body || "",
                    time: String(e.ts || "").slice(11, 16),
                    archive: true
                })
            } catch (err) { /* ligne illisible : ignorée */ }
        }
        root.archive = out
        root.majListe()
    }

    Connections {
        target: Theme
        function onNotifListChanged() { root.majListe() }
    }

    // Fermeture au clic à l'extérieur : même mécanique que le panneau réseau —
    // attrapeur armé après l'affichage, sinon Hyprland le relâche aussitôt.
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
        windows: [notificationsPopup]
        onCleared: if (root.ouvert) Theme.activePopup = ""
    }
    readonly property int compte: Theme.notifCount

    implicitWidth: rangee.implicitWidth + Math.round(10 * echelle)
    implicitHeight: Math.max(22, Math.round(26 * echelle))

    Rectangle {
        anchors.fill: parent
        radius: Theme.globalRadius
        color: root.ouvert
            ? Theme.accent
            : (souris.containsMouse ? Theme.surfaceVariant : "transparent")

        Behavior on color { ColorAnimation { duration: 140 } }

        Row {
            id: rangee
            anchors.centerIn: parent
            spacing: Math.round(4 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                // Cloche barrée uniquement en « Ne pas déranger » : avant, elle
                // l'était dès qu'il n'y avait aucune notification, ce qui
                // laissait croire à un mode silencieux permanent.
                glyph: Theme.doNotDisturb ? "bell-off" : "bell"
                size: root.tailleIcone
                color: root.ouvert ? Theme.bg : (root.compte > 0 ? Theme.warn : Theme.fg)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.compte > 0 && !root.verticale
                text: String(root.compte)
                color: root.ouvert ? Theme.bg : Theme.warn
                font.pixelSize: Math.round(Theme.textXs * echelle)
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: souris
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("notifications")
        }
    }

    PopupWindow {
        id: notificationsPopup
        // Le panneau vit dans l'applet : il s'ouvre donc sous la cloche, où
        // qu'elle soit placée dans la barre. `PopupAdjustment.All` le ramène
        // dans l'écran quand la cloche est près du bord.
        anchor.item: root
        anchor.rect.x: Theme.ancrePopupX(root.applet.ile, root, implicitWidth, "centre")
        anchor.rect.y: Theme.ancrePopupY(root.applet.ile, root, implicitHeight)
        anchor.adjustment: PopupAdjustment.All
        // Le panneau prend le clavier quand il est ouvert : sans cela Échap
        // n'atteignait personne.
        grabFocus: visible
        implicitWidth: 320
        implicitHeight: 340
        color: "transparent"
        visible: Theme.activePopup === "notifications"


        // Échap ferme, quel que soit l'élément qui a le focus dans le panneau.
        Shortcut {
            sequence: "Escape"
            enabled: notificationsPopup.visible
            onActivated: Theme.activePopup = ""
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ────────────────────────────────────────────────────────────
                // En-tête : compteur discret, action neutre au repos
                // ────────────────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "bell"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Notifications"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Theme.notifList.length > 0
                            text: Theme.notifList.length
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    // Les trois actions de l'en-tête dans une Row : ancrées une à
                    // une, elles se chevauchaient dès que « Tout effacer »
                    // disparaissait (largeur nulle), et le clic sur l'historique
                    // tombait alors dans le vide.
                    Row {
                        id: headerActions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        // Ne pas déranger : bascule directe, à gauche de l'historique.
                        // Même glyphe que l'applet (cloche barrée) pour que les deux
                        // se lisent comme un seul état.
                        Item {
                            id: dndBtn
                            width: 18
                            height: 20

                            Icon {
                                anchors.centerIn: parent
                                glyph: "bell-off"
                                size: 12
                                color: Theme.doNotDisturb
                                       ? Theme.accent
                                       : (dndMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.5))
                                opacityLevel: Theme.doNotDisturb ? 1 : 0.9

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: dndMa
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.doNotDisturb = !Theme.doNotDisturb
                                    dndBridge.running = true
                                }
                            }
                        }

                        // Historique : petite icône à gauche de « Tout effacer », qui
                        // ouvre le tiroir indépendant (tout ce qui est arrivé, y
                        // compris ce qui a été effacé ici ou fermé par l'application).
                        Item {
                            id: historyBtn
                            width: 18
                            height: 20

                            Icon {
                                anchors.centerIn: parent
                                glyph: "history"
                                size: 12
                                color: historyMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
                                opacityLevel: 1

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: historyMa
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // Une seule affectation : c'est le tiroir lui-même qui
                                // referme le panneau (son handler le fait déjà). Fermer
                                // ici d'abord démaillait la surface du popup pendant le
                                // clic, et le relâchement atterrissait sur le tiroir
                                // plein écran — qui le prenait pour un clic extérieur.
                                onClicked: Theme.notifHistoryVisible = true
                            }
                        }

                        // « Tout effacer » : discret au repos, rouge seulement au survol.
                        // Le rouge reste un signal, pas une décoration.
                        Item {
                            id: clearBtn
                            visible: Theme.notifList.length > 0
                            width: clearText.implicitWidth + 12
                            height: 20

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.globalRadius
                                color: clearMa.containsMouse ? Qt.alpha(Theme.error, 0.12) : "transparent"
                            }

                            Text {
                                id: clearText
                                anchors.centerIn: parent
                                text: "Tout effacer"
                                color: clearMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.55)
                                font.pixelSize: Theme.textXs

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: clearMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toutEffacer()
                            }
                        }
                    }

                    // Écriture de l'état : le panneau a déjà basculé à l'écran,
                    // il ne reste qu'à mémoriser le choix.
                    Process {
                        id: dndBridge
                        command: ["python3", Quickshell.shellPath("core/config_manager.py"),
                                  "style", "do_not_disturb",
                                  Theme.doNotDisturb ? "true" : "false"]
                    }
                }

                // ────────────────────────────────────────────────────────────
                // Cartes empilées, la plus récente en tête
                // ────────────────────────────────────────────────────────────
                Flickable {
                    id: notifFlick
                    width: parent.width
                    // Le pied « sans apparition spontanée » rogne la liste d'autant.
                    height: 268 - (quietFooter.visible ? quietFooter.height + 6 : 0)
                    contentWidth: width
                    contentHeight: notifListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: notifListCol
                        width: parent.width
                        spacing: 8

                        // État vide
                        Item {
                            visible: Theme.notifList.length === 0
                            width: parent.width
                            height: notifFlick.height

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.space2

                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    glyph: "bell-off"
                                    size: Theme.iconLg
                                    color: Qt.alpha(Theme.fg, 0.35)
                                    opacityLevel: 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Aucune notification"
                                    color: Qt.alpha(Theme.fg, 0.55)
                                    font.pixelSize: Theme.textSm
                                }
                            }
                        }

                        Repeater {
                            // Liste vive tant qu'il y en a une, sinon les dernières
                            // entrées de l'historique (fenêtre jamais vide).
                            model: root.notifications

                            Rectangle {
                                id: notifCard
                                required property var modelData
                                required property int index
                                width: notifListCol.width
                                height: notifCardCol.implicitHeight + 20
                                radius: Theme.globalRadius
                                color: cardMa.containsMouse
                                    ? Qt.lighter(Theme.surfaceVariant, 1.15)
                                    : Theme.surfaceVariant
                                clip: true

                                Behavior on color { ColorAnimation { duration: 120 } }

                                // Liseré d'application : 2 px, franc sur la carte la
                                // plus récente, effacé sur les anciennes.
                                Rectangle {
                                    width: 2
                                    height: parent.height
                                    color: Qt.alpha(Theme.accent, index === 0 ? 0.95 : 0.35)
                                }

                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }

                                Column {
                                    id: notifCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Item {
                                        width: parent.width
                                        height: 18

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.space1

                                            Text {
                                                text: modelData.appName
                                                width: Math.min(implicitWidth, notifCardCol.width - 78)
                                                color: Theme.accent
                                                font.pixelSize: Theme.textXs
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: "·"
                                                color: Qt.alpha(Theme.fg, 0.4)
                                                font.pixelSize: Theme.textXs
                                            }
                                            Text {
                                                text: modelData.time
                                                color: Qt.alpha(Theme.fg, 0.5)
                                                font.pixelSize: Theme.textXs
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        Icon {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "close"
                                            size: 10
                                            color: closeMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.5)
                                            opacityLevel: 1

                                            MouseArea {
                                                id: closeMa
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.oublier(modelData)
                                            }
                                        }
                                    }

                                    // Titre = cible : curseur main et teinte accent au
                                    // survol **seulement** si une cible a été résolue.
                                    Item {
                                        width: parent.width
                                        height: notifTitle.implicitHeight

                                        Text {
                                            id: notifTitle
                                            width: parent.width
                                            text: modelData.summary
                                            color: titleMa.containsMouse && titleMa.enabled
                                                ? Theme.accent : Theme.fg
                                            font.pixelSize: Theme.textSm
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }

                                        MouseArea {
                                            id: titleMa
                                            anchors.fill: parent
                                            enabled: root.aCible(modelData)
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.ouvrir(modelData, true)
                                        }
                                    }

                                    Text {
                                        visible: modelData.body !== ""
                                        width: parent.width
                                        text: modelData.body
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.textXs
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }

                                    // Actions proposées par l'application
                                    // (« Ouvrir », « Mettre en pause »…) : petites
                                    // pastilles sous le corps. L'action « default »
                                    // n'y figure pas, c'est le clic sur le titre.
                                    Flow {
                                        width: parent.width
                                        visible: root.actionsDe(notifCard.modelData).length > 0
                                        spacing: Theme.space1

                                        Repeater {
                                            model: root.actionsDe(notifCard.modelData)

                                            Rectangle {
                                                required property var modelData
                                                width: actionLabel.implicitWidth + Theme.space3 * 2
                                                height: 20
                                                radius: Theme.globalRadius
                                                color: actionMa.containsMouse
                                                    ? Qt.alpha(Theme.accent, 0.16)
                                                    : Qt.alpha(Theme.fg, 0.06)

                                                Text {
                                                    id: actionLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.text
                                                    color: actionMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
                                                    font.pixelSize: Theme.textXs
                                                    elide: Text.ElideRight
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }

                                                MouseArea {
                                                    id: actionMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.invoquer(notifCard.modelData, modelData.identifier)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ────────────────────────────────────────────────────
                // Applications écartées des toasts : le choix se fait
                // depuis un toast (cloche barrée) et se défait ici.
                // ────────────────────────────────────────────────────
                Item {
                    id: quietFooter
                    width: parent.width
                    height: visible ? quietCol.implicitHeight + 12 : 0
                    visible: Theme.quietNotifApps.length > 0

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.08)
                    }

                    Column {
                        id: quietCol
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: parent.width
                        spacing: 6

                        Row {
                            spacing: Theme.space1

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "bell-off"
                                size: 10
                                color: Qt.alpha(Theme.fg, 0.45)
                                opacityLevel: 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications silencieuses"
                                color: Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.text2xs
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: Theme.quietNotifApps

                                Rectangle {
                                    required property var modelData
                                    width: quietChipText.implicitWidth + 26
                                    height: 20
                                    radius: Theme.globalRadius
                                    color: Theme.surfaceVariant

                                    Text {
                                        id: quietChipText
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, 130)
                                        text: modelData
                                        color: Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.text2xs
                                        elide: Text.ElideRight
                                    }

                                    Icon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 7
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: "close"
                                        size: 9
                                        color: chipClose.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                                        opacityLevel: 1

                                        MouseArea {
                                            id: chipClose
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.rendreMuet(modelData, false)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
