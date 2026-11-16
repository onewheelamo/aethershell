import QtQuick
import "."

// Onglet « Îlot dynamique » du panneau de configuration.
Column {
    id: bloc
    property var root
    property var mainFlickable

    visible: root ? root.currentTab === 2 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: ({
        "ilot_config": secIlotConfig,
        "ilot_indicateurs": secIlotIndicateurs,
        "ilot_applets": secIlotApplets
    })

    readonly property var cibles: ({
        "secIlotConfig": secIlotConfig,
        "secIlotIndicateurs": secIlotIndicateurs,
        "secIlotApplets": secIlotApplets
    })

    readonly property var modeChoices: [
        { code: "off",      label: "Masqué" },
        { code: "compact",  label: "Repos" },
        { code: "expanded", label: "Étendu" },
        { code: "both",     label: "Les deux" }
    ]

    CollapsibleSection {
        id: secIlotConfig
        width: parent.width
        title: "Îlot dynamique — Apparence & comportement"
        summary: (Theme.barStyle === "island" ? "Mode actif" : "Mode barre classique")
            + " · hauteur " + Theme.barHeight + " px · anim " + Theme.panelAnimDuration + " ms"
        expanded: root ? root.sectionOpen("ilot_config", true) : true
        onToggled: {
            if (!root) return
            root.setPanelSection("ilot_config", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_config")
        }

        // Mode Îlot dynamique vs Barre classique
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Mode de barre :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Row {
                spacing: 6
                Repeater {
                    model: [
                        { key: "island",  label: "Îlot dynamique" },
                        { key: "classic", label: "Barre classique" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: Theme.barStyle === modelData.key
                        width: 118
                        height: 28
                        radius: Theme.globalRadius
                        color: active ? Theme.accent : (bmMa.containsMouse ? Theme.surfaceVariant : Theme.bg)
                        border.color: active ? Theme.accent : Theme.surfaceVariant
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: active
                        }

                        MouseArea {
                            id: bmMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root) root.runConfigCmd(["style", "bar_style", modelData.key])
                        }
                    }
                }
            }
        }

        // Onglet Projets (Kanban Planka)
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Onglet Projets (Kanban) :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                width: 96
                height: 28
                radius: Theme.globalRadius
                color: Theme.ilotProjetsActif ? Theme.accent : Theme.bg
                border.color: Theme.ilotProjetsActif ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.ilotProjetsActif ? "Activé" : "Masqué"
                    color: Theme.ilotProjetsActif ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: Theme.ilotProjetsActif
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root) root.runConfigCmd(["style", "ilot_projets_actif", Theme.ilotProjetsActif ? "false" : "true"])
                }
            }
        }

        // Bordure de pilule
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Bordure de la pilule :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                width: 96
                height: 28
                radius: Theme.globalRadius
                color: Theme.barBorder ? Theme.accent : Theme.bg
                border.color: Theme.barBorder ? Theme.accent : Theme.surfaceVariant
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.barBorder ? "Activée" : "Désactivée"
                    color: Theme.barBorder ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: Theme.barBorder
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root) root.runConfigCmd(["style", "bar_border", Theme.barBorder ? "false" : "true"])
                }
            }
        }

        // Hauteur de la pilule
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Hauteur de pilule :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.barHeight
                minimumValue: 14
                maximumValue: 60
                stepSize: 2
                suffix: " px"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "bar_height", String(newVal)])
                }
            }
        }

        // Arrondis îlots (Quickshell)
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Arrondis îlots (QS) :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.globalRadius
                minimumValue: 0
                maximumValue: 30
                stepSize: 2
                suffix: " px"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "global_radius", String(newVal)])
                }
            }
        }

        // Vitesse d'animation du panneau
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 170
                anchors.verticalCenter: parent.verticalCenter
                text: "Durée d'animation :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.panelAnimDuration
                minimumValue: 80
                maximumValue: 500
                stepSize: 20
                suffix: " ms"
                onValueModified: newVal => {
                    if (root) root.runConfigCmd(["style", "panel_anim_duration", String(newVal)])
                }
            }
        }
    }

    CollapsibleSection {
        id: secIlotIndicateurs
        width: parent.width
        title: "Indicateurs de la pilule"
        summary: "Masqué · Repos · Étendu · Les deux"
        expanded: root ? root.sectionOpen("ilot_indicateurs", true) : true
        onToggled: {
            if (!root) return
            root.setPanelSection("ilot_indicateurs", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_indicateurs")
        }

        Repeater {
            model: [
                { key: "ilot_show_vpn",        label: "Voyant VPN",             desc: "Point d'état VPN",                    mode: Theme.ilotShowVpn },
                { key: "ilot_show_capture",    label: "Voyant Capture",         desc: "Capture vidéo / audio active",        mode: Theme.ilotShowCapture },
                { key: "ilot_show_planka",     label: "Échéance Kanban Planka", desc: "Icône si une carte approche",         mode: Theme.ilotShowPlanka },
                { key: "ilot_show_workspaces", label: "Workspaces",             desc: "Points des bureaux virtuels",         mode: Theme.ilotShowWorkspaces },
                { key: "ilot_show_clock",      label: "Horloge",                desc: "Heure (et date en mode étendu)",      mode: Theme.ilotShowClock }
            ]

            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 0
                height: 46
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.color: Qt.alpha(Theme.fg, 0.08)
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10

                    Column {
                        width: Math.max(90, parent.width - segTrack.width - 10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: modelData.label
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.desc
                            color: Qt.alpha(Theme.fg, 0.65)
                            font.pixelSize: Theme.text2xs
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Rectangle {
                        id: segTrack
                        width: segRow.implicitWidth + 6
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                        color: Theme.bg
                        border.color: Theme.surfaceVariant
                        border.width: 1

                        Row {
                            id: segRow
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: bloc.modeChoices
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var rowItem: parent.parent.parent.parent.modelData
                                    readonly property bool active: rowItem.mode === modelData.code
                                    width: segLbl.implicitWidth + 12
                                    height: 22
                                    radius: Math.max(4, Math.round(Theme.globalRadius * 0.4))
                                    color: active ? Theme.accent : (segMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.6) : "transparent")

                                    Text {
                                        id: segLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: active ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.text2xs
                                        font.bold: active
                                    }

                                    MouseArea {
                                        id: segMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root) root.runConfigCmd(["style", rowItem.key, modelData.code])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    CollapsibleSection {
        id: secIlotApplets
        width: parent.width
        title: "Applets de l'îlot"
        summary: "Systray · Titre média · Luminosité/Nuit · Batterie · etc."
        expanded: root ? root.sectionOpen("ilot_applets", false) : false
        onToggled: {
            if (!root) return
            root.setPanelSection("ilot_applets", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ilot_applets")
        }

        Repeater {
            model: [
                { id: "systray",         label: "Systray",             desc: "Icônes d'applications en arrière-plan" },
                { id: "ilot_media",      styleKey: "ilot_show_media", label: "Titre média en cours", desc: "Morceau joué dans l'îlot dynamique" },
                { id: "luminosite",      label: "Luminosité & Nuit",   desc: "Réglage écran et filtre lumière bleue" },
                { id: "batterie",        label: "Batterie",            desc: "Niveau et charge (laptop)" },
                { id: "minimise",        label: "Fenêtres minimisées", desc: "Icônes des fenêtres réduites" },
                { id: "volume",          label: "Volume",              desc: "Sortie audio et muet" },
                { id: "reseau",          label: "Réseau",              desc: "Wi-Fi et connexion" },
                { id: "notifications",   label: "Notifications",       desc: "Cloche et compteur d'alertes" },
                { id: "maj",             label: "Mises à jour",        desc: "Paquets en attente" },
                { id: "todo",            label: "Tâches Todo",         desc: "Compteur de tâches ouvertes" },
                { id: "meteo",           label: "Météo",               desc: "Température actuelle" },
                { id: "presse-papiers",  label: "Presse-papiers",      desc: "Historique du presse-papiers" }
            ]

            delegate: Rectangle {
                required property var modelData
                readonly property string curMode: modelData.styleKey ? Theme.ilotShowMedia : Theme.ilotAppletModeFor(modelData.id)
                readonly property bool isMaj: modelData.id === "maj"
                width: parent ? parent.width : 0
                height: isMaj ? 78 : 46
                radius: Math.max(8, Math.round(Theme.globalRadius * 0.6))
                color: Qt.alpha(Theme.surfaceVariant, 0.35)
                border.color: Qt.alpha(Theme.fg, 0.08)
                border.width: 1

                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 46
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10

                    Column {
                        width: Math.max(90, parent.width - appSegTrack.width - 10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: modelData.label
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.desc
                            color: Qt.alpha(Theme.fg, 0.65)
                            font.pixelSize: Theme.text2xs
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Rectangle {
                        id: appSegTrack
                        width: appSegRow.implicitWidth + 6
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Math.max(6, Math.round(Theme.globalRadius * 0.5))
                        color: Theme.bg
                        border.color: Theme.surfaceVariant
                        border.width: 1

                        Row {
                            id: appSegRow
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: bloc.modeChoices
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var appRow: parent.parent.parent.parent
                                    readonly property bool active: appRow.curMode === modelData.code
                                    width: appSegLbl.implicitWidth + 12
                                    height: 22
                                    radius: Math.max(4, Math.round(Theme.globalRadius * 0.4))
                                    color: active ? Theme.accent : (appSegMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.6) : "transparent")

                                    Text {
                                        id: appSegLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: active ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
                                        font.pixelSize: Theme.text2xs
                                        font.bold: active
                                    }

                                    MouseArea {
                                        id: appSegMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!root) return
                                            if (appRow.modelData.styleKey) {
                                                root.runConfigCmd(["style", appRow.modelData.styleKey, modelData.code])
                                            } else {
                                                root.runConfigCmd(["ilot_applet_mode", appRow.modelData.id, modelData.code])
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Option spécifique à « Mises à jour » : masquer s'il n'y a aucune MAJ
                Item {
                    visible: isMaj
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    height: 32

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.06)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: majCondSwitch.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Uniquement s'il y a des mises à jour"
                        color: Qt.alpha(Theme.fg, 0.8)
                        font.pixelSize: Theme.text2xs
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: majCondSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 18
                        radius: 9
                        color: Theme.majSeulementSiDispo ? Theme.accent : Qt.alpha(Theme.fg, 0.22)
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            y: 2
                            x: Theme.majSeulementSiDispo ? (parent.width - width - 2) : 2
                            color: Theme.majSeulementSiDispo ? Theme.bg : Theme.fg
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root) root.runConfigCmd(["style", "maj_seulement_si_dispo", String(!Theme.majSeulementSiDispo)])
                    }
                }
            }
        }
    }
}
