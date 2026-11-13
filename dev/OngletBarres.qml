import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Barres & Applets » du panneau de configuration, sorti de config_panel.qml.
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
    visible: root ? root.currentTab === 1 : false
    width: mainFlickable ? mainFlickable.width : 0
    property var disquesListeProc

    readonly property var sections: ({
        "quickshell_barres": secBarres,
        "quickshell_applets": secApplets,
        "quickshell_visualiseur": secVisualiseur
    })

    readonly property var cibles: ({
        "roundingIslandRow": roundingIslandRow,
        "barHeightRow": barHeightRow,
        "barGapsOutHRow": barGapsOutHRow,
        "barGapsOutVRow": barGapsOutVRow,
        "barGapsRow": barGapsRow,
        "secVisualiseur": secVisualiseur,
        "secApplets": secApplets,
        "secBarres": secBarres
    })

    // Sections qui naissent dans un délégué de `Repeater` : leur `id` n'est pas
    // dans la portée du fichier, donc les tables `sections`/`cibles` ne peuvent
    // pas les nommer (un id absent lève « ReferenceError »). Elles se retrouvent
    // par `objectName`, et `tiroirDe` / `cibleDe` du panneau passent par ici.
    readonly property var sectionsTardives: ({ "quickshell_disques": "secDisques" })

    function objetParObjectName(nom) {
        function chercher(objet) {
            if (!objet || !objet.children)
                return null
            for (let k = 0; k < objet.children.length; ++k) {
                const enfant = objet.children[k]
                if (enfant.objectName === nom)
                    return enfant
                const trouve = chercher(enfant)
                if (trouve)
                    return trouve
            }
            return null
        }
        return chercher(bloc)
    }
spacing: 11



// Tiroir 3 : les barres optionnelles. Une barre allumée mais sans
// applet reste invisible : on le dit, sinon le réglage semble cassé.
CollapsibleSection {
    id: secBarres
    objectName: "secBarres"
    title: "Barres du shell"
    summary: "Hauteur " + Theme.barHeight + " · gaps " + Theme.gutterH + "/" + Theme.gutterV + " · " + (root.barGapsTransparent ? "îlots transparents" : "capsule continue")
    icon: "monitor"
    expanded: root.sectionOpen("quickshell_barres", false)
    onToggled: expanded => {
        root.setPanelSection("quickshell_barres", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_barres")
    }

    Column {
        // Barre principale : géométrie, bordure, espaces entre les
        // îlots et bouton central. Ces réglages dessinaient autrefois une
        // section « Barre & surfaces » dans l'onglet Apparence.
    Grid {
        width: parent.width
        columns: 1
        columnSpacing: 14
        rowSpacing: 12

        // 4b. Disposition de la barre (Classique vs Îlot dynamique)
        Row {
            id: barStyleRow
            objectName: "barStyleRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Disposition :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: [
                        { key: "classic", label: "Classique (3 îlots)" },
                        { key: "island",  label: "Îlot dynamique" }
                    ]

                    Rectangle {
                        width: 140
                        height: 28
                        radius: 6
                        color: Theme.barStyle === modelData.key ? Theme.accent : Qt.alpha(Theme.surfaceVariant, 0.4)
                        border.color: Theme.barStyle === modelData.key ? Theme.accent : Qt.alpha(Theme.fg, 0.2)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 11
                            font.weight: Theme.barStyle === modelData.key ? Font.DemiBold : Font.Normal
                            color: Theme.barStyle === modelData.key ? (Theme.activeTheme === "light" ? "#ffffff" : "#101010") : Theme.fg
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runConfigCmd(["style", "bar_style", modelData.key])
                        }
                    }
                }
            }
        }

        // 5. Arrondis îlots (Quickshell)
        Row {
            id: roundingIslandRow   // ancre de recherche
            objectName: "roundingIslandRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
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
                stepSize: 1
                suffix: " px"
                onValueModified: newVal => {
                    root.runConfigCmd(["style", "global_radius", String(newVal)])
                }
            }
        }

        // 5b. Arrondis des fenêtres de sélecteurs (fichiers/dossiers) : 0 = suit la règle générale
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Arrondis sélecteurs :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.selecteurRadius
                minimumValue: 0
                maximumValue: 30
                stepSize: 1
                suffix: value === 0 ? " (auto)" : " px"
                onValueModified: newVal => {
                    root.runConfigCmd(["style", "selecteur_radius", String(newVal)])
                }
            }
        }

        // 6. Hauteur de barre
        Row {
            id: barHeightRow   // ancre de recherche
            objectName: "barHeightRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Hauteur de barre :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.barHeight
                minimumValue: 28
                maximumValue: 60
                stepSize: 2
                suffix: " px"
                onValueModified: newVal => {
                    root.runConfigCmd(["style", "bar_height", String(newVal)])
                }
            }
        }

    }
        // 7. Marges extérieures : deux axes indépendants — les côtés et le
        // haut/bas ne se règlent pas ensemble.
        Row {
            id: barGapsOutHRow   // ancre de recherche
            objectName: "barGapsOutHRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Gaps latéraux :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.gutterH
                minimumValue: 0
                maximumValue: 32
                stepSize: 1
                suffix: " px"
                onValueModified: newVal => {
                    root.runConfigCmd(["style", "bar_gaps_out_h", String(newVal)])
                }
            }
        }
        Row {
            id: barGapsOutVRow   // ancre de recherche
            objectName: "barGapsOutVRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Gaps haut/bas :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                value: Theme.gutterV
                minimumValue: 0
                maximumValue: 32
                stepSize: 1
                suffix: " px"
                onValueModified: newVal => {
                    root.runConfigCmd(["style", "bar_gaps_out_v", String(newVal)])
                }
            }
        }
        Row {
            id: barBorderRow   // ancre de recherche
            objectName: "barBorderRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Bordure de la barre :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: 26
                radius: Theme.globalRadius
                color: root.barBorder ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: root.barBorder ? "✓ Bordure" : "✕ Sans bordure"
                    color: root.barBorder ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.barBorder = !root.barBorder
                        root.runConfigCmd(["style", "bar_border", root.barBorder ? "true" : "false"])
                    }
                }
            }
        }
        Row {
            id: panelAnimDurationRow
            objectName: "panelAnimDurationRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Vitesse d'animation :"
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
                    Theme.panelAnimDuration = newVal
                    root.runConfigCmd(["style", "panel_anim_duration", String(newVal)])
                }
            }
        }
        Row {
            id: barGapsRow   // ancre de recherche
            objectName: "barGapsRow"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Espaces entre les îlots :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: 26
                radius: Theme.globalRadius
                color: root.barGapsTransparent ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: root.barGapsTransparent ? "✓ Transparents" : "✕ Peints"
                    color: root.barGapsTransparent ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.barGapsTransparent = !root.barGapsTransparent
                        root.runConfigCmd(["style", "bar_gaps_transparent", root.barGapsTransparent ? "true" : "false"])
                    }
                }
            }
        }
    Grid {
        width: parent.width
        columns: 1
        columnSpacing: 14
        rowSpacing: 12
        topPadding: 12

        // 16. Bouton central (engrenage) — bascule d'affichage
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Bouton central :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: 26
                radius: Theme.globalRadius
                color: Theme.showConfigButton ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.showConfigButton ? "✓ Affiché" : "Masqué (SUPER+SHIFT+H)"
                    color: Theme.showConfigButton ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["style", "show_config_button", String(!Theme.showConfigButton)])
                }
            }
        }
    }   // end Grid
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "Une barre allumée apparaît aussitôt, même vide : elle affiche "
                  + "alors un rappel. Pour la remplir, choisissez l'emplacement "
                  + "↓ ← → dans la liste des applets."
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Math.max(9, Theme.textXs - 1)
            wrapMode: Text.WordWrap
        }
        Item {
            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Barre du bas"
                color: Theme.fg
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 110
                height: 20
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.barBottomVisible ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.barBottomVisible ? "✓ Affichée" : "Masquée"
                    color: Theme.barBottomVisible ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["style", "bar_bottom",
                        String(!Theme.barBottomVisible)])
                }
            }
        }
        Item {
            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Barre de gauche"
                color: Theme.fg
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 110
                height: 20
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.barLeftVisible ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.barLeftVisible ? "✓ Affichée" : "Masquée"
                    color: Theme.barLeftVisible ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["style", "bar_left",
                        String(!Theme.barLeftVisible)])
                }
            }
        }
        Item {
            width: parent.width
            height: 22

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Barre de droite"
                color: Theme.fg
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 110
                height: 20
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.globalRadius
                color: Theme.barRightVisible ? Theme.accent : Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: Theme.barRightVisible ? "✓ Affichée" : "Masquée"
                    color: Theme.barRightVisible ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["style", "bar_right",
                        String(!Theme.barRightVisible)])
                }
            }
        }
    }
}

// Tiroir 2 : les applets. Un applet n'a qu'un emplacement ; l'ordre
// se règle aux flèches, l'échelle par applet.
CollapsibleSection {
    id: secApplets
    objectName: "secApplets"
    title: "Applets de la barre"
    summary: root.appletRows.length + " applets"
    icon: "widgets"
    expanded: root.sectionOpen("quickshell_applets", false)
    onToggled: expanded => {
        root.setPanelSection("quickshell_applets", expanded)
        if (expanded) disquesListeProc.running = true
    }
    Component.onCompleted: disquesListeProc.running = true

    Column {
        width: parent.width
        spacing: 8


        Text {
            width: parent.width
            text: "Éteints par défaut. Un applet n'a qu'un emplacement : "
                  + "le choisir ailleurs le déplace, il ne se duplique pas. "
                  + "Le visualiseur audio fait exception : il n'a pas d'emplacement, "
                  + "il occupe les espaces entre les îlots (un de chaque côté du centre)."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.max(9, Theme.textXs - 1)
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width
            spacing: 4

            Repeater {
                model: root.appletEntries

                delegate: Column {
                    id: appletRow
                    // Les propriétés `required` doivent vivre sur la
                    // racine du délégué, pas sur son enfant.
                    required property var modelData

                    readonly property bool estTitre: modelData.genre === "titre"
                    // Une tête de catégorie n'a pas de données
                    // d'applet : un objet neutre évite les
                    // « Unable to assign [undefined] » que lèvent
                    // les liaisons de la ligne, même invisible.
                    readonly property var donnee: estTitre
                        ? ({ id: "", nom: "", ile: "", actif: false,
                             text_scale: 100, options: ({}) })
                        : modelData.applet
                    width: parent.width
                    spacing: 3

                    // ── tête de catégorie ────────────────────────────
                    // Un petit titre et un trait : le panneau devient
                    // lisible par groupes au lieu d'une liste de
                    // dix-neuf lignes au même niveau. Le trait est
                    // sous le titre, pas entre deux catégories : il
                    // sépare le titre de ses lignes.
                    Column {
                        width: parent.width
                        visible: appletRow.estTitre
                        spacing: 5

                        Item { width: 1; height: 6 }

                        Text {
                            width: parent.width
                            text: appletRow.estTitre ? String(modelData.texte) : ""
                            color: Qt.alpha(Theme.fg, 0.6)
                            font.pixelSize: Math.max(9, Theme.textXs - 1)
                            font.bold: true
                            font.letterSpacing: 0.7
                            font.capitalization: Font.AllUppercase
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.alpha(Theme.fg, 0.14)
                        }
                    }

                    Rectangle {
                    visible: !appletRow.estTitre
                    width: parent.width
                    height: 30
                    radius: Theme.globalRadius
                    color: appletRow.donnee.actif
                        ? Qt.alpha(Theme.accent, 0.10) : Theme.surfaceVariant
                    border.width: 1
                    border.color: appletRow.donnee.actif
                        ? Qt.alpha(Theme.accent, 0.5) : "transparent"

                    // Toute la ligne bascule l'applet : la seule case
                    // de 12 px obligeait à viser, et les contrôles de
                    // droite (flèches, pastilles, échelle) la recouvrent
                    // puisqu'ils sont déclarés après celle-ci.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.appletBasculer(appletRow.donnee.id,
                                                       appletRow.donnee.actif)
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 3
                            color: appletRow.donnee.actif ? Theme.accent : "transparent"
                            border.width: 1
                            border.color: appletRow.donnee.actif
                                ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                            Text {
                                anchors.centerIn: parent
                                visible: appletRow.donnee.actif
                                text: "✓"
                                color: Theme.bg
                                font.pixelSize: 9
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appletBasculer(appletRow.donnee.id,
                                                               appletRow.donnee.actif)
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: appletRow.donnee.nom
                            color: Theme.fg
                            font.pixelSize: Theme.textXs
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // Ordre d'affichage : échange avec le voisin
                        // du même îlot. Deux flèches plutôt qu'un
                        // numéro à saisir — l'ordre n'a de sens que
                        // relativement aux autres.
                        Row {
                            spacing: 3
                            opacity: appletRow.donnee.actif ? 1 : 0.35

                            Rectangle {
                                width: 14
                                height: 16
                                radius: 4
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "‹"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (appletRow.donnee.actif)
                                        root.appletCommande(["monter", appletRow.donnee.id])
                                }
                            }

                            Rectangle {
                                width: 14
                                height: 16
                                radius: 4
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "›"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (appletRow.donnee.actif)
                                        root.appletCommande(["descendre", appletRow.donnee.id])
                                }
                            }
                        }

                        // Échelle de texte de cet applet : la même
                        // règle que les widgets, appliquée par applet.
                        // Boutons dans des Rectangles : un MouseArea
                        // avec `anchors.fill` ne peut pas être enfant
                        // direct d'un Row (le positionneur refuse les
                        // ancres horizontales), d'où l'enveloppe.
                        Row {
                            spacing: 3
                            opacity: appletRow.donnee.actif ? 1 : 0.35

                            Rectangle {
                                width: 14
                                height: 16
                                radius: 4
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.appletEchelle(appletRow.donnee.id,
                                                                  appletRow.donnee.text_scale - 5)
                                }
                            }

                            Text {
                                text: appletRow.donnee.text_scale + " %"
                                color: Qt.alpha(Theme.fg, 0.75)
                                font.pixelSize: Math.max(9, Theme.textXs - 1)
                                font.features: { "tnum": 1 }
                            }

                            Rectangle {
                                width: 14
                                height: 16
                                radius: 4
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: Theme.fg
                                    font.pixelSize: Theme.textXs
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.appletEchelle(appletRow.donnee.id,
                                                                  appletRow.donnee.text_scale + 5)
                                }
                            }
                        }

                        // Groupe 1 : la barre. Reste réglable même
                        // pour un applet à emplacement fixe : le
                        // visualiseur n'a pas de place *dans* une
                        // barre, mais il choisit *quelle* barre le
                        // porte — une seule à la fois, et la
                        // pastille active est en couleur d'accent.
                        Row {
                            spacing: 2

                            Repeater {
                                model: root.appletBarres

                                Rectangle {
                                    required property var modelData
                                    readonly property bool choisi:
                                        root.barreDe(appletRow.donnee) === modelData.code
                                    width: 17
                                    height: 16
                                    radius: 4
                                    color: choisi ? Theme.accent : "transparent"
                                    border.width: 1
                                    border.color: choisi
                                        ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                    opacity: appletRow.donnee.actif ? 1 : 0.35

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                        font.pixelSize: Math.max(8, Theme.textXs - 2)
                                        font.bold: parent.choisi
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.placerApplet(appletRow.donnee.id,
                                            modelData.code + ":" + root.zoneDe(appletRow.donnee))
                                    }
                                }
                            }
                        }

                        // Groupe 2 : la place dans la barre (début,
                        // milieu, fin). Sur la barre du haut, ce sont
                        // les trois îlots historiques G / C / D.
                        Row {
                            spacing: 2
                            visible: !appletRow.donnee.fixe

                            Repeater {
                                model: root.appletZones

                                Rectangle {
                                    required property var modelData
                                    readonly property bool choisi:
                                        root.zoneDe(appletRow.donnee) === modelData.code
                                    readonly property bool enHaut:
                                        root.barreDe(appletRow.donnee) === "haut"
                                    width: 17
                                    height: 16
                                    radius: 4
                                    color: choisi ? Theme.accent : "transparent"
                                    border.width: 1
                                    border.color: choisi
                                        ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                    opacity: appletRow.donnee.actif ? 1 : 0.35

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.enHaut ? modelData.labelA : modelData.labelB
                                        color: parent.choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                                        font.pixelSize: Math.max(8, Theme.textXs - 2)
                                        font.bold: parent.choisi
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.placerApplet(appletRow.donnee.id,
                                            root.barreDe(appletRow.donnee) + ":" + modelData.code)
                                    }
                                }
                            }
                        }
                    }
                    }

                    // Choix déclaré au catalogue : ici, le service que
                    // l'applet des comptes affiche dans la barre.
                    Row {
                        visible: appletRow.donnee.choix !== undefined
                        width: parent.width
                        height: visible ? 18 : 0
                        spacing: 4

                        Item { width: 26; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(appletRow.donnee.choix && appletRow.donnee.choix.libelle
                                         ? appletRow.donnee.choix.libelle : "")
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: Math.max(9, Theme.textXs - 1)
                        }

                        Repeater {
                            model: (appletRow.donnee.choix && appletRow.donnee.choix.valeurs) || []

                            Rectangle {
                                required property var modelData
                                readonly property bool choisi: {
                                    const o = appletRow.donnee.options || ({})
                                    const cle = appletRow.donnee.choix
                                        ? appletRow.donnee.choix.cle : ""
                                    return String(o[cle] || "") === String(modelData.code)
                                }
                                width: 62
                                height: 16
                                radius: 4
                                color: choisi ? Theme.accent : "transparent"
                                border.width: 1
                                border.color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                opacity: appletRow.donnee.actif ? 1 : 0.35

                                Text {
                                    anchors.centerIn: parent
                                    text: String(modelData.nom || modelData.code)
                                    color: choisi ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                    font.pixelSize: Math.max(8, Theme.textXs - 2)
                                    font.bold: choisi
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (appletRow.donnee.actif)
                                        root.appletCommande(["option", appletRow.donnee.id,
                                                             appletRow.donnee.choix.cle,
                                                             String(modelData.code)])
                                }
                            }
                        }
                    }

                    // Petit tiroir : la sélection des systèmes de
                    // fichiers, sur deux colonnes. Replié par défaut,
                    // il ne mange pas la place des autres applets.
                    CollapsibleSection {
                        id: secDisques
                        // Son id est hors de portée du fichier (délégué de Repeater) :
                        // le panneau le retrouve par ce nom, voir sectionsTardives.
                        objectName: "secDisques"
                        visible: appletRow.donnee.liste !== undefined
                        title: String((appletRow.donnee.liste || ({})).libelle
                                      || "Disques affichés")
                        icon: "disque"
                        expanded: root.sectionOpen("quickshell_disques", false)
                        onToggled: expanded => {
        root.setPanelSection("quickshell_disques", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_disques")
    }

                        Grid {
                            id: grilleDisques
                            width: parent.width
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 3
                            topPadding: 4

                            Repeater {
                                model: root.disquesListe

                                // Item et non Row : un MouseArea en
                                // `anchors.fill` ne peut pas être
                                // enfant direct d'un positionneur, et
                                // c'est ce qui rendait les cases inertes.
                                Item {
                                    required property var modelData
                                    readonly property string montage: String(modelData.montage || "")
                                    readonly property bool coche: {
                                        // Deux précautions : lire la
                                        // signature (dépendance réactive)
                                        // et relire l'entrée courante par
                                        // id — le `modelData` du délégué
                                        // reste figé sur l'ancienne copie
                                        // quand la liste est réaffectée.
                                        const _ = root.appletSignature
                                        const vive = root.entreeApplet(appletRow.donnee.id)
                                                     || appletRow.donnee
                                        return root.montageCoche(vive, montage)
                                    }

                                    width: (grilleDisques.width - grilleDisques.columnSpacing) / 2
                                    height: 18

                                    Rectangle {
                                        id: boite
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 12
                                        height: 12
                                        radius: 3
                                        color: parent.coche ? Theme.accent : "transparent"
                                        border.width: 1
                                        border.color: parent.coche ? Theme.accent
                                                                   : Qt.alpha(Theme.fg, 0.4)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: parent.parent.coche
                                            text: "✓"
                                            color: Theme.bg
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.left: boite.right
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 20 - pourcentage.implicitWidth
                                        text: parent.montage
                                        color: Theme.fg
                                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: pourcentage
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.pourcent) + " %"
                                        color: Qt.alpha(Theme.fg, 0.45)
                                        font.pixelSize: Math.max(8, Theme.textXs - 2)
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.basculerMontage(appletRow.donnee,
                                                                        parent.montage)
                                    }
                                }
                            }
                        }
                    }

                    // Cases déclarées au catalogue : un réglage
                    // vrai/faux par applet, écrit comme une option
                    // (absent = activé, valeur par défaut du catalogue).
                    Row {
                        visible: (appletRow.donnee.cases || []).length > 0
                        width: parent.width
                        height: visible ? 18 : 0
                        spacing: 4

                        Item { width: 26; height: 1 }

                        Repeater {
                            model: appletRow.donnee.cases || []

                            Rectangle {
                                required property var modelData
                                readonly property bool coche: {
                                    const _ = root.appletSignature
                                    const vive = root.entreeApplet(appletRow.donnee.id)
                                                 || appletRow.donnee
                                    const o = vive.options || ({})
                                    const v = o[modelData.cle]
                                    if (v === undefined || v === null || v === "") return true
                                    return !(v === false || v === "false"
                                             || v === 0 || v === "0")
                                }
                                width: caseTexte.implicitWidth + 16
                                height: 16
                                radius: 4
                                color: coche ? Theme.accent : "transparent"
                                border.width: 1
                                border.color: coche ? Theme.accent : Qt.alpha(Theme.fg, 0.3)
                                opacity: appletRow.donnee.actif ? 1 : 0.35

                                Text {
                                    id: caseTexte
                                    anchors.centerIn: parent
                                    text: (coche ? "\u2713 " : "\u2715 ")
                                          + String(modelData.libelle || modelData.cle)
                                    color: coche ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                                    font.pixelSize: Math.max(8, Theme.textXs - 2)
                                    font.bold: coche
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (appletRow.donnee.actif)
                                        root.appletCommande(["option", appletRow.donnee.id,
                                                             modelData.cle,
                                                             coche ? "false" : "true"])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
    // ═══════════════════════════════════════════════════════════════
    // Visualiseur audio — capture et dessin
    // ═══════════════════════════════════════════════════════════════
    CollapsibleSection {
        id: secVisualiseur
        objectName: "secVisualiseur"
        title: "Visualiseur audio"
        summary: (root.vizActif ? "actif" : "coupé") + " · " + (root.vizStyle === "barres" ? "barres" : "onde")
        icon: "music"
        expanded: root.sectionOpen("quickshell_visualiseur", false)
        onToggled: expanded => {
        root.setPanelSection("quickshell_visualiseur", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_visualiseur")
    }

        Column {
            width: parent.width
            spacing: 8

            // Activation : elle vivait dans la liste des applets, où
            // elle n'avait rien à faire (aucun emplacement à choisir).
            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: 160
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Visualiseur :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 160
                    height: 26
                    radius: Theme.globalRadius
                    color: root.vizActif ? Theme.accent : Theme.surfaceVariant
                    border.color: Theme.accent
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.vizActif ? "✓ Actif" : "✕ Éteint"
                        color: root.vizActif ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.basculerVisualiseur()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 340
                    text: "Occupe les espaces entre les îlots, un de chaque côté du centre."
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.text2xs
                    wrapMode: Text.WordWrap
                }
            }

            // Rendu : une ligne qui ne défile pas (onde) ou des bandes
            // qui montent avec la musique (barres). Option d'applet du
            // registre, exposée ici parce que c'est elle qui décide de
            // l'allure du visualiseur.
            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: 160
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mode :"
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [{ code: "onde", nom: "Onde" },
                            { code: "barres", nom: "Barres" }]

                    Rectangle {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 92
                        height: 26
                        radius: Theme.globalRadius
                        color: root.vizStyle === modelData.code ? Theme.accent
                                                                : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.vizStyle === modelData.code
                                  ? ("✓ " + modelData.nom) : modelData.nom
                            color: root.vizStyle === modelData.code ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.changerModeVisualiseur(modelData.code)
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 380
                    text: "L'onde suit le signal, les barres suivent le spectre. "
                          + "Les barres s'alignent sur les colonnes : une bande pour quatre."
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.text2xs
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                width: parent.width
                spacing: 8
                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Images par seconde :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.vizFps
                    minimumValue: 10; maximumValue: 60; stepSize: 5; decimals: 0
                    onValueModified: newVal => {
                        root.vizFps = newVal
                        root.runConfigCmd(["style", "viz_fps", String(newVal)])
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8
                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Colonnes :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.vizCols
                    minimumValue: 16; maximumValue: 256; stepSize: 8; decimals: 0
                    onValueModified: newVal => {
                        root.vizCols = newVal
                        root.runConfigCmd(["style", "viz_cols", String(newVal)])
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "bandes en mode barres : colonnes / 4"; color: Qt.alpha(Theme.fg, 0.45); font.pixelSize: Math.max(9, Theme.textXs - 1) }
            }

            Row {
                width: parent.width
                spacing: 8
                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Sensibilité :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.vizSensibilite
                    minimumValue: 0.05; maximumValue: 4.0; stepSize: 0.05; decimals: 2
                    onValueModified: newVal => {
                        root.vizSensibilite = newVal
                        root.runConfigCmd(["style", "viz_sensibilite", String(newVal)])
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8
                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Lissage :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.vizLissage
                    minimumValue: 0.0; maximumValue: 0.99; stepSize: 0.05; decimals: 2
                    onValueModified: newVal => {
                        root.vizLissage = newVal
                        root.runConfigCmd(["style", "viz_lissage", String(newVal)])
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8
                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Épaisseur du trait :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }
                Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.vizEpaisseur
                    minimumValue: 0.5; maximumValue: 4.0; stepSize: 0.5; decimals: 1
                    onValueModified: newVal => {
                        root.vizEpaisseur = newVal
                        root.runConfigCmd(["style", "viz_epaisseur", String(newVal)])
                    }
                }
            }

            // Couleur : des jetons du thème, pas une valeur libre — une
            // couleur en dur ne suivrait pas un changement de palette.
            Row {
                width: parent.width
                spacing: 8

                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Couleur :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }

                // Flow plutôt que Row : à cinq jetons et 540 px de
                // contenu, la dernière pastille sortait du panneau.
                // Flow passe à la ligne tout seul.
                Flow {
                    spacing: 6
                    width: parent.width - 168
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.vizCouleurs

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: root.vizCouleur === modelData.code
                            width: 74; height: 22; radius: Theme.globalRadius
                            color: choisi ? root.couleurViz(modelData.code) : "transparent"
                            border.color: root.couleurViz(modelData.code)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.nom
                                color: parent.choisi ? Theme.bg : root.couleurViz(modelData.code)
                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                font.bold: parent.choisi
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.vizCouleur = modelData.code
                                    root.runConfigCmd(["style", "viz_couleur", modelData.code])
                                }
                            }
                        }
                    }
                }
            }
        }
    }


}
