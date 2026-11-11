import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Clavier & Binds » du panneau de configuration, sorti de config_panel.qml.
// Le panneau le charge par URL et ne l'instancie qu'a l'ouverture de
// l'onglet : le corps n'a pas bouge d'un caractere, hors indentation.
//
// `root` et `mainFlickable` viennent du panneau sous les noms qu'ils avaient
// deja dans ce corps, donc les appels a la racine sont restes intacts.
// `sections` et `cibles` sont remplies apres la decoupe (voir decouper.py) :
// le panneau ne peut plus nommer ces ids, il les demande ici.
Column {
    id: bloc
    property var root
    property var mainFlickable

    width: mainFlickable ? mainFlickable.width : 0

    readonly property var sections: ({
        "clavier_disposition": secClavier,
        "clavier_binds": secBinds
    })

    readonly property var cibles: ({
        "kbdRow": kbdRow,
        "bindsCol": bindsCol
    })
spacing: 10

// Top bar: Current Keyboard Layout + Button to reopen First-Run Keyboard Selector
// Tiroir : disposition active et changement de clavier.
CollapsibleSection {
    id: secClavier
    objectName: "secClavier"
    title: "Disposition du clavier"
    summary: root.kbLayout
    icon: "keyboard"
    expanded: root.sectionOpen("clavier_disposition", false)
    onToggled: expanded => {
        root.setPanelSection("clavier_disposition", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("clavier_disposition")
    }

Rectangle {
    id: kbdRow   // ancre de recherche
    objectName: "kbdRow"
    width: parent.width
    height: 42
    radius: Theme.globalRadius
    color: Theme.surfaceVariant
    border.color: Theme.accentMuted
    border.width: 1

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 156
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: "Disposition active : " + root.kbLayout.toUpperCase()
            color: Theme.accent
            font.pixelSize: Theme.textMd
            font.bold: true
            elide: Text.ElideRight
        }
    }

    Rectangle {
        width: 140
        height: 28
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.globalRadius
        color: reopenKbMa.containsMouse ? Theme.accent : Theme.bg
        border.color: Theme.accent
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "Assistant clavier"
            color: reopenKbMa.containsMouse ? Theme.bg : Theme.accent
            font.pixelSize: Theme.textXs
            font.bold: true
        }

        MouseArea {
            id: reopenKbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Theme.configPanelVisible = false
                Theme.showKeyboardOnboarding = true
            }
        }
    }
}
}

// Tiroir : raccourcis Hyprland — liste, ajout, suppression.
CollapsibleSection {
    id: secBinds
    objectName: "secBinds"
    title: "Raccourcis Hyprland"
    summary: root.bindsList.length + " raccourcis"
    icon: "cog"
    expanded: root.sectionOpen("clavier_binds", false)
    onToggled: expanded => {
        root.setPanelSection("clavier_binds", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("clavier_binds")
    }

Text {
    width: parent.width
    text: "Raccourcis Hyprland — cliquer une ligne pour l'éditer"
    color: Theme.accent
    font.pixelSize: Theme.textMd
    font.bold: true
    elide: Text.ElideRight
}
Flickable {
    width: parent.width
    height: 245
    contentWidth: width
    contentHeight: bindsCol.implicitHeight
    clip: true

    Column {
        id: bindsCol
        objectName: "bindsCol"
        width: parent.width
        spacing: 6

        Repeater {
            model: root.bindsList

            Rectangle {
                required property var modelData
                width: bindsCol.width
                height: 30
                radius: Theme.globalRadius
                color: bindRowMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.5)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 36
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Rectangle {
                        width: 118
                        height: 22
                        radius: Theme.globalRadius
                        color: Theme.bg
                        border.color: Theme.accentMuted
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.mod + " + " + modelData.key
                            color: Theme.accent
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 118 - 24
                        text: "→  " + modelData.target
                        color: Theme.fg
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: bindRowMa
                    anchors.fill: parent
                    anchors.rightMargin: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        bindKeyInput.text = modelData.key
                        bindCmdInput.text = modelData.target
                    }
                }

                // Delete bind button
                Rectangle {
                    width: 24
                    height: 24
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: "transparent"
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.textXs
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["bind_del", modelData.key])
                    }
                }
            }
        }
    }
}
Column {
    width: parent.width
    spacing: 8

    Row {
        width: parent.width
        spacing: 8

        Rectangle {
            width: 66
            height: 32
            radius: Theme.globalRadius
            color: Theme.surfaceVariant

            Text {
                anchors.centerIn: parent
                text: "SUPER +"
                color: Theme.accent
                font.pixelSize: Theme.textSm
                font.bold: true
            }
        }

        Rectangle {
            width: parent.width - 66 - 84 - 2 * 8
            height: 32
            radius: Theme.globalRadius
            color: Theme.bg
            border.color: bindKeyInput.activeFocus ? Theme.accent : Theme.surfaceVariant
            border.width: 1

            Text {
                visible: bindKeyInput.text.length === 0
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                text: "Touche (ex: Return, M)"
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: Theme.textXs
            }

            TextInput {
                id: bindKeyInput
                anchors.fill: parent
                anchors.margins: 6
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.textSm
            }
        }

        Rectangle {
            width: 84
            height: 32
            radius: Theme.globalRadius
            color: Theme.accent

            Text {
                anchors.centerIn: parent
                text: "Ajouter"
                color: Theme.bg
                font.pixelSize: Theme.textSm
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (bindKeyInput.text !== "" && bindCmdInput.text !== "") {
                        root.runConfigCmd(["bind_set", bindKeyInput.text, bindCmdInput.text])
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 32
        radius: Theme.globalRadius
        color: Theme.bg
        border.color: bindCmdInput.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Text {
            visible: bindCmdInput.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            text: "Commande ou variable (ex: terminal)"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        TextInput {
            id: bindCmdInput
            anchors.fill: parent
            anchors.margins: 6
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.info
            font.pixelSize: Theme.textSm
            onAccepted: {
                if (bindKeyInput.text !== "" && bindCmdInput.text !== "") {
                    root.runConfigCmd(["bind_set", bindKeyInput.text, bindCmdInput.text])
                }
            }
        }
    }
}
}
}
