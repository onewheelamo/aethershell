import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Apps & Alertes » du panneau de configuration, sorti de config_panel.qml.
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

    // Plusieurs onglets restent montés depuis qu'on ne les décharge plus en
    // quittant : sans ce masque, ils s'empilaient les uns sur les autres
    // (le `visible:` du panneau avait été retiré à la découpe).
    visible: root ? root.currentTab === 5 : false
    width: mainFlickable ? mainFlickable.width : 0

    readonly property var sections: ({
        "apps_programs": secApps,
        "quickshell_notifications": secNotifs,
        "apps_autostart": secAutostart
    })

    readonly property var cibles: ({
        "secApps": secApps,
        "secAutostart": secAutostart
    })
spacing: 12

// Programs par défaut des raccourcis (app_vars.json <-> programs.lua)
CollapsibleSection {
    id: secApps
    objectName: "secApps"
    title: "Applications par défaut"
    summary: root.appVarsModel.length + " programmes"
    icon: "rocket"
    expanded: root.sectionOpen("apps_programs", false)
    onToggled: expanded => {
        root.setPanelSection("apps_programs", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("apps_programs")
    }

Text {
    text: "Les alias ci-dessous sont aussi proposés par la pilule ; « > » y lance une commande shell."
    color: Qt.alpha(Theme.fg, 0.55)
    font.pixelSize: Theme.textSm
    width: parent.width
    wrapMode: Text.WordWrap
}

Text {
    text: "Variables d'Applications par défaut (Synchronisées à la volée avec Hyprland)"
    color: Theme.accent
    font.pixelSize: Theme.textLg
    font.bold: true
    width: parent.width
}

Flickable {
    width: parent.width
    // Hauteur calée sur le contenu (plafonnée) : une liste courte ne
    // laisse pas de vide, une liste longue défile sans couper la
    // dernière ligne.
    height: Math.min(appList.implicitHeight, 300)
    contentWidth: width
    contentHeight: appList.implicitHeight
    clip: true

    Column {
        id: appList
        width: parent.width
        spacing: 8

        Repeater {
            model: root.appVarsModel

            Row {
                id: appRow
                required property var modelData
                spacing: 10
                width: appList.width

                // Variable Name (Alias)
                Rectangle {
                    width: 84
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        width: parent.width - 16
                        text: appRow.modelData.alias
                        color: Theme.fg
                        font.bold: true
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }
                }

                // Editable Command Field
                Rectangle {
                    width: appRow.width - 84 - 32 - 32 - 3 * 10 - 4
                    height: 32
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: editCmdInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    TextInput {
                        id: editCmdInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: appRow.modelData.cmd
                        color: Theme.info
                        font.pixelSize: Theme.textSm
                        onAccepted: root.runConfigCmd(["app_set", appRow.modelData.alias, editCmdInput.text])
                    }
                }

                // Save Button
                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.success
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.success
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["app_set", appRow.modelData.alias, editCmdInput.text])
                    }
                }

                // Delete Button
                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["app_del", appRow.modelData.alias])
                    }
                }
            }
        }
    }
}

// Respiration entre la dernière ligne et la barre d'ajout : un peu
// plus que l'écart entre deux lignes (8 px) pour séparer le groupe.
Item { width: 1; height: 10 }

// Add New Application Variable Row
Row {
    spacing: 10
    width: parent.width

    Rectangle {
        width: 110
        height: 34
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: newAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Text {
            visible: newAlias.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: "Nom"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        TextInput {
            id: newAlias
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.textSm
        }
    }

    Rectangle {
        width: parent.width - 110 - 84 - 2 * 10
        height: 34
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: newCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Text {
            visible: newCmd.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: "Programme"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        TextInput {
            id: newCmd
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.info
            font.pixelSize: Theme.textSm
            onAccepted: {
                if (newAlias.text !== "" && newCmd.text !== "") {
                    root.runConfigCmd(["app_set", newAlias.text, newCmd.text])
                    newAlias.text = ""
                    newCmd.text = ""
                }
            }
        }
    }

    Rectangle {
        width: 84
        height: 34
        radius: Theme.globalRadius
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "+ Ajouter"
            color: Theme.bg
            font.pixelSize: Theme.textSm
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (newAlias.text !== "" && newCmd.text !== "") {
                    root.runConfigCmd(["app_set", newAlias.text, newCmd.text])
                    newAlias.text = ""
                    newCmd.text = ""
                }
            }
        }
    }
}
}   // end CollapsibleSection secApps

// Notifications : un seul réglage global ici, la bascule « ne pas
// déranger ». Elle coupe les toasts ; l'historique continue de se
// remplir, et la cloche de la barre se barre.
CollapsibleSection {
    id: secNotifs
    objectName: "secNotifs"
    title: "Notifications & Actions au clic"
    summary: root.dndActif ? "ne pas déranger" : "alertes actives"
    icon: "bell"
    expanded: root.sectionOpen("quickshell_notifications", false)
    onToggled: expanded => {
        root.setPanelSection("quickshell_notifications", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_notifications")
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "« Ne pas déranger » n'affiche plus aucun toast : les notifications "
                + "arrivent quand même dans le centre et dans l'historique."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        Item {
            width: parent.width
            height: 30

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Ne pas déranger"
                color: root.dndActif ? Theme.accent : Theme.fg
                font.pixelSize: Theme.textSm
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 22
                radius: 11
                color: root.dndActif ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    y: 2
                    x: root.dndActif ? parent.width - width - 2 : 2
                    color: root.dndActif ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                    Behavior on x { NumberAnimation { duration: 130 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reglerDnd(!root.dndActif)
                }
            }
        }

        Text {
            width: parent.width
            text: root.dndActif ? "Actif : aucun toast ne s'affiche." : "Inactif : les toasts s'affichent normalement."
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Theme.textXs
        }
    }

    // Au clic : quoi faire quand on clique une notification.
    Text {
        width: parent.width
        text: "Au clic sur une notification"
        color: Theme.accent
        font.pixelSize: Theme.textSm
        font.bold: true
    }

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            text: "Cliquer le titre d'une notification ouvre ce qu'elle annonce. "
                + "Les fichiers et les liens passent par les alias de « Programmes par défaut » ; "
                + "une application peut avoir sa propre commande."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        // ── par nature de fichier ────────────────────────────
        Text {
            text: "Fichiers détectés dans le texte"
            color: Theme.accent
            font.pixelSize: Theme.textMd
            font.bold: true
        }

        Repeater {
            model: root.notifTypeRows

            Row {
                id: typeRow
                required property var modelData
                width: parent.width
                spacing: 10

                Rectangle {
                    width: 84
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: typeRow.modelData.label
                        color: Theme.fg
                        font.bold: true
                        font.pixelSize: Theme.textSm
                    }
                }

                Rectangle {
                    width: typeRow.width - 84 - 32 - 2 * 10
                    height: 32
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: typeAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    TextInput {
                        id: typeAlias
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: typeRow.modelData.alias
                        color: Theme.info
                        font.pixelSize: Theme.textSm
                        onAccepted: root.runConfigCmd(["notif_type_set", typeRow.modelData.nature, text])
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.success
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.success
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["notif_type_set", typeRow.modelData.nature, typeAlias.text])
                    }
                }
            }
        }

        // ── liens ───────────────────────────────────────────
        Row {
            id: urlRow
            width: parent.width
            spacing: 10

            Rectangle {
                width: 84
                height: 32
                color: Theme.surfaceVariant
                radius: Theme.globalRadius
                border.color: Theme.accentMuted
                border.width: 1

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Liens"
                    color: Theme.fg
                    font.bold: true
                    font.pixelSize: Theme.textSm
                }
            }

            Rectangle {
                width: urlRow.width - 84 - 32 - 2 * 10
                height: 32
                color: Theme.bg
                radius: Theme.globalRadius
                border.color: urlAlias.activeFocus ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                TextInput {
                    id: urlAlias
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.notifTargets.url || ""
                    color: Theme.info
                    font.pixelSize: Theme.textSm
                    onAccepted: root.runConfigCmd(["notif_url_set", text])
                }
            }

            Rectangle {
                width: 32
                height: 32
                color: Theme.surfaceVariant
                radius: Theme.globalRadius
                border.color: Theme.success
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: Theme.success
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["notif_url_set", urlAlias.text])
                }
            }
        }

        // ── par application ─────────────────────────────────
        Text {
            text: "Par application"
            color: Theme.accent
            font.pixelSize: Theme.textMd
            font.bold: true
        }

        Text {
            visible: root.notifAppRows.length === 0
            width: parent.width
            text: "Aucune règle par application."
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Theme.textXs
        }

        Repeater {
            model: root.notifAppRows

            Row {
                id: appRuleRow
                required property var modelData
                width: parent.width
                spacing: 10

                Rectangle {
                    width: 116
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        width: parent.width - 16
                        text: appRuleRow.modelData.key + (appRuleRow.modelData.terminal ? " · terminal" : "")
                        color: Theme.fg
                        font.bold: true
                        font.pixelSize: Theme.text2xs
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: appRuleRow.width - 116 - 32 - 32 - 3 * 10 - 4
                    height: 32
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: appRuleCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                    border.width: 1

                    TextInput {
                        id: appRuleCmd
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: appRuleRow.modelData.command
                        color: Theme.info
                        font.pixelSize: Theme.textSm
                        onAccepted: root.runConfigCmd(["notif_app_set", appRuleRow.modelData.key, text])
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.success
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: Theme.success
                        font.pixelSize: Theme.textMd
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["notif_app_set", appRuleRow.modelData.key, appRuleCmd.text])
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["notif_app_del", appRuleRow.modelData.key])
                    }
                }
            }
        }

        Item { width: 1; height: 4 }

        // Ajout d'une règle : le nom de l'application tel qu'il apparaît
        // dans ses notifications, et la commande à lancer.
        Row {
            id: newNotifAppRow
            width: parent.width
            spacing: 10

            function ajouter() {
                const cle = newNotifAppKey.text.trim()
                const cmd = newNotifAppCmd.text.trim()
                if (cle === "" || cmd === "") return
                root.runConfigCmd(["notif_app_set", cle, cmd])
                newNotifAppKey.text = ""
                newNotifAppCmd.text = ""
            }

            Rectangle {
                width: 116
                height: 34
                color: Theme.bg
                radius: Theme.globalRadius
                border.color: newNotifAppKey.activeFocus ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    visible: newNotifAppKey.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Application"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }

                TextInput {
                    id: newNotifAppKey
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                }
            }

            Rectangle {
                width: parent.width - 116 - 84 - 2 * 10
                height: 34
                color: Theme.bg
                radius: Theme.globalRadius
                border.color: newNotifAppCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    visible: newNotifAppCmd.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Commande"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }

                TextInput {
                    id: newNotifAppCmd
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.info
                    font.pixelSize: Theme.textSm
                    onAccepted: newNotifAppRow.ajouter()
                }
            }

            Rectangle {
                width: 84
                height: 34
                radius: Theme.globalRadius
                color: Theme.accent

                Text {
                    anchors.centerIn: parent
                    text: "+ Ajouter"
                    color: Theme.bg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: newNotifAppRow.ajouter()
                }
            }
        }

        Text {
            width: parent.width
            text: "Commande telle qu'on la taperait dans un terminal : les guillemets "
                + "protègent les espaces (« gwenview \"mon dossier/image.png\" »)."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.text2xs
            wrapMode: Text.WordWrap
        }
    }
}

// Cible du clic sur le titre d'une notification (core/notif_targets.json).
// Aucun programme n'est écrit ici : les alias renvoient au tiroir
// « Programmes par défaut » ci-dessus. Le résolveur relit le fichier à
// chaque notification, donc une modification est effective tout de suite.

// Autostart géré par le panneau (autostart.json -> autostart_managed.lua)
CollapsibleSection {
    id: secAutostart
    objectName: "secAutostart"
    title: "Programmes lancés au démarrage"
    summary: root.autostartModel.length + " programmes"
    icon: "power"
    expanded: root.sectionOpen("apps_autostart", false)
    onToggled: expanded => {
        root.setPanelSection("apps_autostart", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("apps_autostart")
    }

Text {
    text: "Autostart Hyprland (effectif au prochain démarrage de session)"
    color: Theme.accent
    font.pixelSize: Theme.textMd
    font.bold: true
    width: parent.width
}

Flickable {
    width: parent.width
    height: Math.min(autostartList.implicitHeight, 260)
    contentWidth: width
    contentHeight: autostartList.implicitHeight
    clip: true

    Column {
        id: autostartList
        width: parent.width
        spacing: 8

        Repeater {
            model: root.autostartModel

            Row {
                id: asRow
                required property var modelData
                spacing: 10
                width: autostartList.width

                Rectangle {
                    width: 32
                    height: 32
                    radius: Theme.globalRadius
                    color: asRow.modelData.enabled ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.4)
                    border.color: asRow.modelData.enabled ? Theme.success : Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: asRow.modelData.enabled ? "✓" : "✕"
                        color: asRow.modelData.enabled ? Theme.success : Theme.error
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["autostart_set", asRow.modelData.name, String(!asRow.modelData.enabled)])
                    }
                }

                Rectangle {
                    width: 140
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        width: parent.width - 16
                        text: asRow.modelData.name
                        color: Theme.fg
                        font.bold: true
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: asRow.width - 32 - 140 - 32 - 3 * 10 - 4
                    height: 32
                    color: Theme.bg
                    radius: Theme.globalRadius
                    border.color: Theme.surfaceVariant
                    border.width: 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: asRow.modelData.cmd
                        elide: Text.ElideRight
                        color: Theme.info
                        font.pixelSize: Theme.textXs
                    }
                }

                Rectangle {
                    width: 32
                    height: 32
                    color: Theme.surfaceVariant
                    radius: Theme.globalRadius
                    border.color: Theme.error
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["autostart_del", asRow.modelData.name])
                    }
                }
            }
        }
    }
}

Item { width: 1; height: 10 }

Row {
    spacing: 10
    width: parent.width

    Rectangle {
        width: 110
        height: 34
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: newAsName.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Text {
            visible: newAsName.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: "Nom"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        TextInput {
            id: newAsName
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.textSm
        }
    }

    Rectangle {
        width: parent.width - 110 - 84 - 2 * 10
        height: 34
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: newAsCmd.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Text {
            visible: newAsCmd.text.length === 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: "Commande"
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        TextInput {
            id: newAsCmd
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.info
            font.pixelSize: Theme.textSm
            onAccepted: {
                if (newAsName.text !== "" && newAsCmd.text !== "") {
                    root.runConfigCmd(["autostart_add", newAsName.text, newAsCmd.text])
                    newAsName.text = ""
                    newAsCmd.text = ""
                }
            }
        }
    }

    Rectangle {
        width: 84
        height: 34
        radius: Theme.globalRadius
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "+ Ajouter"
            color: Theme.bg
            font.pixelSize: Theme.textSm
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (newAsName.text !== "" && newAsCmd.text !== "") {
                    root.runConfigCmd(["autostart_add", newAsName.text, newAsCmd.text])
                    newAsName.text = ""
                    newAsCmd.text = ""
                }
            }
        }
    }
}
}   // end CollapsibleSection secAutostart

// Hors tiroir : c'est une action, pas un réglage. Elle installe ce que
// dependencies.txt réclame et qui manque sur cette machine.
Item { width: 1; height: 12 }

Row {
    width: parent.width
    spacing: 10

    Rectangle {
        id: depsBtn
        width: depsBtnText.implicitWidth + 26
        height: 28
        radius: Theme.globalRadius
        color: depsBtnMa.containsMouse ? Theme.accentMuted : Theme.accent

        Text {
            id: depsBtnText
            anchors.centerIn: parent
            text: "Installer les paquets manquants"
            color: Theme.bg
            font.pixelSize: Theme.text2xs
            font.bold: true
        }

        MouseArea {
            id: depsBtnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.installerDependances()
        }
    }

    // Rien à côté du bouton quand tout va bien : une coche, et c'est
    // tout. Un échec, lui, se dit — c'est la seule information utile.
    Icon {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.depsEtat === "à jour"
        glyph: "check"
        size: Theme.iconSm
        color: Theme.success
        opacityLevel: 1
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.depsEtat !== "" && root.depsEtat !== "à jour"
        width: parent.width - depsBtn.width - Theme.iconSm - 20
        text: root.depsEtat
        color: Theme.error
        font.pixelSize: Theme.textXs
        elide: Text.ElideRight
    }
}
}
