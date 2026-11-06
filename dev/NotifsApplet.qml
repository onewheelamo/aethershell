import QtQuick
import Quickshell
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

    readonly property bool ouvert: Theme.activePopup === "notifications"

    // Le panneau est déclaré plus bas dans ce fichier : il s'ouvre donc collé à
    // la cloche, quel que soit l'endroit où elle est placée dans la barre.
    readonly property var liste: Theme.notifList
    readonly property var archive: Theme.notifArchive
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
                size: Math.max(11, Math.round(Theme.iconSm * echelle))
                color: root.ouvert ? Theme.bg : (root.compte > 0 ? Theme.warn : Theme.fg)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.compte > 0
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
        anchor.rect.x: (root.width - implicitWidth) / 2
        anchor.rect.y: Theme.barHeight + 6
        anchor.adjustment: PopupAdjustment.All
        implicitWidth: 320
        implicitHeight: 340
        color: "transparent"
        visible: Theme.activePopup === "notifications"

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

                    // Historique : petite icône à gauche de « Tout effacer », qui
                    // ouvre le tiroir indépendant (tout ce qui est arrivé, y
                    // compris ce qui a été effacé ici ou fermé par l'application).
                    Item {
                        id: historyBtn
                        anchors.right: clearBtn.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
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
                            onClicked: {
                                Theme.activePopup = ""
                                Theme.notifHistoryVisible = true
                            }
                        }
                    }

                    // « Tout effacer » : discret au repos, rouge seulement au survol.
                    // Le rouge reste un signal, pas une décoration.
                    Item {
                        id: clearBtn
                        visible: Theme.notifList.length > 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
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
                            onClicked: Theme.notifOps.clear()
                        }
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
                            model: Theme.notifList.length > 0
                                   ? Theme.notifList
                                   : Theme.notifArchive

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
                                                onClicked: Theme.notifOps.forget(modelData)
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
                                            enabled: Theme.notifOps.hasTarget(modelData)
                                            hoverEnabled: true
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: Theme.notifOps.open(modelData, true)
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
                                        visible: Theme.notifOps.actions(notifCard.modelData).length > 0
                                        spacing: Theme.space1

                                        Repeater {
                                            model: Theme.notifOps.actions(notifCard.modelData)

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
                                                    onClicked: Theme.notifOps.invoke(notifCard.modelData, modelData.identifier)
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
                                            onClicked: Theme.notifOps.setQuiet(modelData, false)
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
