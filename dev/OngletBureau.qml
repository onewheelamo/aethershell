import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Bureau & Lanceur » du panneau de configuration, sorti de config_panel.qml.
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
    visible: root ? root.currentTab === 2 : false
    width: mainFlickable ? mainFlickable.width : 0

    readonly property var sections: ({
        "widgets": secWidgets,
        "widgets_pilule": secPilule
    })

    readonly property var cibles: ({
        "launchHistoryRow": launchHistoryRow,
        "secWidgets": secWidgets
    })
spacing: 11

CollapsibleSection {
    id: secWidgets
    objectName: "secWidgets"
    title: "Widgets du bureau"
    summary: root.widgetsList.length + " widgets"
    icon: "widgets"
    // État persisté comme les autres tiroirs ; ouvert par défaut,
    // c'est le premier de l'onglet « Bureau & Lanceur ».
    expanded: root.sectionOpen("widgets", false)
    onToggled: expanded => {
        root.setPanelSection("widgets", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets")
    }

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            text: root.widgetsList.length === 0
                  ? "Aucun widget. Le bureau affiche le fond d'écran seul."
                  : "Chaque widget vit derrière les fenêtres, sur son workspace. "
                    + "Pour le déplacer : SUPER + SHIFT + clic dessus, puis clic pour le poser."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
            // Sans hauteur explicite, un texte replié sur deux lignes
            // gardait la hauteur d'une seule et la ligne suivante
            // (les pastilles des widgets) passait par-dessus.
            height: contentHeight
        }

        Repeater {
            model: root.widgetsList

            Rectangle {
                required property var modelData
                required property int index

                readonly property string wid: modelData.id || ""
                readonly property string wtype: modelData.type || ""
                readonly property int wWorkspace: Number(modelData.workspace) || 0
                readonly property real wOpacity: modelData.opacity !== undefined
                                                  ? Number(modelData.opacity) : 0.35
                readonly property bool wEnabled: modelData.enabled !== false
                readonly property bool wBlur: modelData.blur !== false
                readonly property bool wBorder: modelData.border !== false
                readonly property var wOptions: modelData.options || ({})
                readonly property bool wSeconds: {
                    const v = widgetCard.wOptions.seconds
                    return v === true || v === "true" || v === 1 || v === "1"
                }
                readonly property string wCity: widgetCard.wOptions.city
                    ? String(widgetCard.wOptions.city) : ""
                // Widgets qui interrogent un service : minutes entre deux
                // requêtes (5 par défaut, comme le service lui-même).
                readonly property int wRefreshMin: {
                    const v = Number(widgetCard.wOptions.refresh_min)
                    return (v >= 1 && v <= 120) ? Math.round(v) : 5
                }
                // Échelle du texte (options.text_scale) : 100 = taille du
                // thème, 85 par défaut pour les widgets de compte LLM, qui
                // empilent deux lignes de texte dense.
                // Ne pas prendre un onglet de navigateur pour de la
                // musique. Absent = on ignore (défaut du widget).
                readonly property bool wIgnorerNavigateurs: {
                    const v = widgetCard.wOptions.ignorer_navigateurs
                    if (v === undefined || v === null || v === "") return true
                    return !(v === false || v === "false" || v === 0 || v === "0")
                }

                // Widget Tâches : fichiers suivis, nombre de lignes et
                // affichage des cochés. Une liste vide veut dire « tous »
                // — c'est le défaut d'un widget sans options.
                readonly property var wFichiers: {
                    const brut = widgetCard.wOptions.fichiers
                    let liste = Array.isArray(brut)
                              ? brut.map(function (s) { return String(s) })
                              : (typeof brut === "string" && brut !== ""
                                 ? brut.split(",").map(function (s) { return s.trim() })
                                 : [])
                    liste = liste.filter(function (s) { return s !== "" })
                    if (liste.length === 0) {
                        const tous = []
                        for (let i = 0; i < root.todoFichiers.length; ++i)
                            tous.push(String(root.todoFichiers[i].nom || ""))
                        return tous
                    }
                    return liste
                }
                readonly property int wLignes: {
                    const v = Number(widgetCard.wOptions.lignes)
                    return (v >= 1 && v <= 6) ? Math.round(v) : 3
                }
                readonly property bool wAfficherFaits: {
                    const v = widgetCard.wOptions.afficher_faits
                    return v === true || v === "true" || v === 1 || v === "1"
                }

                readonly property int wTextScale: {
                    const v = Number(widgetCard.wOptions.text_scale)
                    if (v >= 60 && v <= 160) return Math.round(v)
                    const ia = ["deepseek", "ollama", "antigravity"]
                    return ia.indexOf(widgetCard.wtype) >= 0 ? 85 : 100
                }

                width: parent.width
                height: wcol.implicitHeight + 20
                radius: Theme.globalRadius
                color: Qt.alpha(Theme.surfaceVariant, 0.55)
                border.width: 1
                border.color: Theme.surfaceVariant

                Column {
                    id: wcol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Ligne 1 : type, identifiant, suppression
                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: widgetCard.wtype === "date" ? "calendar"
                                   : (widgetCard.wtype === "meteo" ? "cloud"
                                   : (widgetCard.wtype === "musique" ? "music"
                                   : (widgetCard.wtype === "combo" ? "widgets"
                                   : (widgetCard.wtype === "systeme" ? "monitor"
                                   : "clock"))))
                            size: Theme.iconSm
                            color: Theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 14 - 18 - Theme.space2 * 2
                            text: root.libelleWidget(widgetCard.wtype)
                                  + "  ·  " + widgetCard.wid
                            color: Theme.fg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        // Suppression : la croix seule. Le libellé « Retirer » et
                        // son ancre à droite dans la Row cassaient la mise en page.
                        Text {
                            id: removeIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            horizontalAlignment: Text.AlignRight
                            text: "✕"
                            color: removeMa.containsMouse ? Theme.error
                                                         : Qt.alpha(Theme.error, 0.80)
                            font.pixelSize: Theme.textSm

                            MouseArea {
                                id: removeMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd(["widget_remove", widgetCard.wid])
                            }
                        }
                    }

                    // Ligne 2 : workspace et position
                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 76
                            text: "Workspace"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }
                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 120
                            value: widgetCard.wWorkspace
                            minimumValue: 0
                            maximumValue: 5
                            stepSize: 1
                            textFormatter: v => v === 0 ? "Tous" : String(v)
                            onValueModified: newVal =>
                                root.runConfigCmd(["widget_set", widgetCard.wid, "workspace", String(newVal)])
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "x"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs
                        }
                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 104
                            value: Number(widgetCard.modelData.x) || 0
                            minimumValue: 0
                            maximumValue: 1800
                            stepSize: 10
                            onValueModified: newVal =>
                                root.runConfigCmd(["widget_move", widgetCard.wid, String(newVal), String(Number(widgetCard.modelData.y) || 0)])
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "y"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs
                        }
                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 104
                            value: Number(widgetCard.modelData.y) || 0
                            minimumValue: 0
                            maximumValue: 1000
                            stepSize: 10
                            onValueModified: newVal =>
                                root.runConfigCmd(["widget_move", widgetCard.wid, String(Number(widgetCard.modelData.x) || 0), String(newVal)])
                        }
                    }

                    // Ligne 3 : opacité, puis les trois interrupteurs
                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            text: "Fond"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }
                        Slider {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - 240 - Theme.space2 * 3
                            value: widgetCard.wOpacity
                            minimumValue: 0.0
                            maximumValue: 1.0
                            stepSize: 0.05
                            decimals: 2
                            onValueModified: newVal =>
                                root.runConfigCmd(["widget_set", widgetCard.wid, "opacity", String(newVal)])
                        }

                        Repeater {
                            model: [
                                { key: "enabled", label: "Actif",   on: widgetCard.wEnabled },
                                { key: "border",  label: "Bordure", on: widgetCard.wBorder },
                                { key: "blur",    label: "Flou",    on: widgetCard.wBlur }
                            ]

                            Rectangle {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: 72
                                height: 24
                                radius: Theme.globalRadius
                                color: modelData.on ? Theme.accent : Theme.surfaceVariant
                                border.width: 1
                                border.color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.on ? "✓ " : "✕ ") + modelData.label
                                    color: modelData.on ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.text2xs
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runConfigCmd([
                                        "widget_set", widgetCard.wid,
                                        modelData.key, modelData.on ? "false" : "true"
                                    ])
                                }
                            }
                        }
                    }

                    // Ligne 4 : options propres au type de widget. La ville
                    // vide retombe sur `weather_city` de style_vars.json.
                    Row {
                        width: parent.width
                        spacing: Theme.space2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            text: "Options"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        // L'échelle du texte vaut pour tous les widgets :
                        // c'est le premier réglage qu'on cherche quand un
                        // widget déborde de sa taille.
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Texte"
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.pixelSize: Theme.text2xs
                            }

                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92
                                value: widgetCard.wTextScale
                                minimumValue: 60
                                maximumValue: 160
                                stepSize: 5
                                suffix: " %"
                                onValueModified: newVal =>
                                    root.runConfigCmd(["widget_set", widgetCard.wid,
                                                       "text_scale", String(newVal)])
                            }
                        }

                        // Les secondes ne concernent que les widgets qui
                        // affichent une horloge.
                        Rectangle {
                            visible: widgetCard.wtype === "horloge"
                                     || widgetCard.wtype === "combo"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 86
                            height: 24
                            radius: Theme.globalRadius
                            color: widgetCard.wSeconds ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: (widgetCard.wSeconds ? "✓ " : "✕ ") + "Secondes"
                                color: widgetCard.wSeconds ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd([
                                    "widget_set", widgetCard.wid, "seconds",
                                    widgetCard.wSeconds ? "false" : "true"
                                ])
                            }
                        }

                        // Les navigateurs ne concernent que le widget
                        // musique : ailleurs, la question n'a pas de sens.
                        Rectangle {
                            visible: widgetCard.wtype === "musique"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 118
                            height: 24
                            radius: Theme.globalRadius
                            color: widgetCard.wIgnorerNavigateurs
                                ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: (widgetCard.wIgnorerNavigateurs ? "✓ " : "✕ ")
                                      + "Navigateurs"
                                color: widgetCard.wIgnorerNavigateurs ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd([
                                    "widget_set", widgetCard.wid, "ignorer_navigateurs",
                                    widgetCard.wIgnorerNavigateurs ? "false" : "true"
                                ])
                            }
                        }

                        // La ville ne concerne que la météo : elle
                        // s'affichait sur tous les autres widgets, avec son
                        // « Auto (IP) » qui n'y veut rien dire.
                        Row {
                            visible: widgetCard.wtype === "deepseek"
                                     || widgetCard.wtype === "ollama"
                                     || widgetCard.wtype === "antigravity"
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Rafraîchissement"
                                color: Qt.alpha(Theme.fg, 0.6)
                                font.pixelSize: Theme.text2xs
                            }

                            Stepper {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 108
                                value: widgetCard.wRefreshMin
                                minimumValue: 1
                                maximumValue: 120
                                stepSize: 1
                                suffix: " min"
                                onValueModified: newVal =>
                                    root.runConfigCmd(["widget_set", widgetCard.wid,
                                                       "refresh_min", String(newVal)])
                            }
                        }

                        Rectangle {
                            visible: widgetCard.wtype === "meteo"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 170
                            height: 24
                            radius: Theme.globalRadius
                            color: Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.surfaceVariant

                            TextInput {
                                id: cityInput
                                anchors.fill: parent
                                anchors.leftMargin: 7
                                anchors.rightMargin: 7
                                verticalAlignment: TextInput.AlignVCenter
                                text: widgetCard.wCity
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                selectByMouse: true
                                onAccepted: root.runConfigCmd([
                                    "widget_set", widgetCard.wid, "city", cityInput.text
                                ])
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cityInput.text === ""
                                // Champ vide = géolocalisation par IP.
                                text: "Auto (IP)"
                                color: Qt.alpha(Theme.fg, 0.42)
                                font.pixelSize: Theme.textXs
                            }
                        }
                    }
                    // Widget Tâches : quels fichiers suivis, combien de
                    // lignes d'items, et si les items cochés comptent. La
                    // liste vide veut dire « tous » (défaut historique).
                    Row {
                        width: parent.width
                        spacing: Theme.space2
                        visible: widgetCard.wtype === "todo"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 56
                            text: "Tâches"
                            color: Qt.alpha(Theme.fg, 0.75)
                            font.pixelSize: Theme.textXs
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Repeater {
                                model: root.todoFichiers

                                Rectangle {
                                    required property var modelData
                                    readonly property bool pris:
                                        widgetCard.wFichiers.indexOf(String(modelData.nom)) >= 0
                                    width: nomFichier.width + 16
                                    height: 24
                                    radius: Theme.globalRadius
                                    color: pris ? Qt.alpha(Theme.accent, 0.16)
                                                : Theme.surfaceVariant
                                    border.width: 1
                                    border.color: pris ? Theme.accent : Theme.surfaceVariant

                                    Text {
                                        id: nomFichier
                                        anchors.centerIn: parent
                                        text: String(modelData.nom || "")
                                        color: Theme.fg
                                        font.pixelSize: Theme.textXs
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.basculerFichierWidget(
                                                       widgetCard.wid, modelData.nom)
                                    }
                                }
                            }
                        }

                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 84
                            value: widgetCard.wLignes
                            minimumValue: 1
                            maximumValue: 6
                            stepSize: 1
                            suffix: " l."
                            onValueModified: newVal =>
                                root.runConfigCmd(["widget_set", widgetCard.wid,
                                                   "lignes", String(newVal)])
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 92
                            height: 24
                            radius: Theme.globalRadius
                            color: widgetCard.wAfficherFaits ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: widgetCard.wAfficherFaits ? "✓ cochés" : "✕ cochés"
                                color: widgetCard.wAfficherFaits ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfigCmd([
                                    "widget_set", widgetCard.wid, "afficher_faits",
                                    widgetCard.wAfficherFaits ? "false" : "true"
                                ])
                            }
                        }
                    }
                }


                id: widgetCard
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

        // Widgets disponibles : une case par nature, cochée quand le
        // widget est posé. Trois colonnes dans une zone qui défile à
        // la molette : cinq pastilles côte à côte débordaient du
        // panneau et la dernière (« + Musique ») était rognée.
        Row {
            width: parent.width
            spacing: Theme.space2

            Text {
                width: 76
                text: "Widgets"
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Theme.textXs
                topPadding: 6
            }

            Item {
                width: parent.width - 76 - Theme.space2
                // Six rangées visibles (28 px + 6 d'écart) : les dix-sept
                // natures tiennent en 6 lignes de trois colonnes. Au-delà,
                // on fait défiler et la bande du bas le signale.
                height: Math.min(gridPicker.implicitHeight, 6 * 28 + 5 * 6 + 2)

                Flickable {
                    id: widgetPicker
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.top: parent.top
                    height: parent.height
                    contentWidth: width
                    contentHeight: gridPicker.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: gridPicker
                        width: widgetPicker.width
                        columns: 3
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: root.widgetTypeRows

                            Rectangle {
                                id: typeCell
                                required property var modelData
                                width: (gridPicker.width - 2 * gridPicker.columnSpacing) / 3
                                height: 28
                                radius: Theme.globalRadius
                                color: modelData.present
                                    ? Qt.alpha(Theme.accent, 0.16) : Theme.surfaceVariant
                                border.width: 1
                                border.color: modelData.present
                                    ? Theme.accent : Theme.surfaceVariant

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Rectangle {
                                        width: 12
                                        height: 12
                                        radius: 3
                                        color: typeCell.modelData.present
                                            ? Theme.accent : "transparent"
                                        border.width: 1
                                        border.color: typeCell.modelData.present
                                            ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                                        Text {
                                            anchors.centerIn: parent
                                            visible: typeCell.modelData.present
                                            text: "✓"
                                            color: Theme.bg
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        width: parent.width - 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: typeCell.modelData.label
                                        color: Theme.fg
                                        font.pixelSize: Theme.textXs
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleWidgetType(typeCell.modelData.type,
                                                                    typeCell.modelData.present)
                                }
                            }
                        }
                    }
                }

                // Repère de défilement : n'apparaît que si la liste
                // dépasse les rangées visibles.
                Rectangle {
                    visible: gridPicker.implicitHeight > widgetPicker.height
                    width: 3
                    radius: 2
                    color: Qt.alpha(Theme.accent, 0.45)
                    x: parent.width - 4
                    height: Math.max(18, widgetPicker.height * widgetPicker.height
                                         / Math.max(1, gridPicker.implicitHeight))
                    y: widgetPicker.contentY + widgetPicker.contentY
                         * (widgetPicker.height - height)
                         / Math.max(1, gridPicker.implicitHeight - widgetPicker.height)
                }

                // « Il en reste en dessous » : une bande dégradée et un
                // chevron, qui disparaissent une fois arrivé au bas de la
                // liste. Le simple trait de 3 px ne se voyait pas.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 26
                    visible: widgetPicker.contentHeight > widgetPicker.height + 1
                             && widgetPicker.contentY + widgetPicker.height
                                < widgetPicker.contentHeight - 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.55; color: Qt.alpha(Theme.bg, 0.82) }
                        GradientStop { position: 1.0; color: Qt.alpha(Theme.bg, 0.96) }
                    }

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        glyph: "chevron-down"
                        size: 14
                        color: Theme.accent
                    }
                }
            }
        }


    }
}
// Tiroir : la pilule de lancement (Spotlight). Sa position et son
// historique étaient éparpillés dans deux onglets.
CollapsibleSection {
    id: secPilule
    objectName: "secPilule"
    title: "Lanceur Spotlight"
    summary: root.launcherPosition
    icon: "rocket"
    expanded: root.sectionOpen("widgets_pilule", false)
    onToggled: expanded => {
        root.setPanelSection("widgets_pilule", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_pilule")
    }

    // Le lanceur : intégré, position parmi six emplacements
    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

    Row {
    width: parent.width
    spacing: Theme.space2

    Icon {
    anchors.verticalCenter: parent.verticalCenter
    glyph: "search"
    size: Theme.iconSm
    color: Theme.accent
    }
    Text {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - 320
    text: "Lanceur — intégré, position fixe"
    color: Theme.fg
    font.pixelSize: Theme.textXs
    elide: Text.ElideRight
    }

    Repeater {
    model: [
    { key: "haut-gauche", tip: "↖" },
    { key: "haut-centre", tip: "↑" },
    { key: "haut-droit",  tip: "↗" },
    { key: "bas-gauche",  tip: "↙" },
    { key: "bas-centre",  tip: "↓" },
    { key: "bas-droit",   tip: "↘" }
    ]

    Rectangle {
    required property var modelData
    width: 30
    height: 26
    radius: Theme.globalRadius
    color: root.launcherPosition === modelData.key ? Theme.accent : Theme.surfaceVariant
    border.width: 1
    border.color: Theme.accent

    Text {
    anchors.centerIn: parent
    text: modelData.tip
    color: root.launcherPosition === modelData.key ? Theme.bg : Theme.fg
    font.pixelSize: Theme.textSm
    }
    MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.runConfigCmd(["style", "launcher_position", modelData.key])
    }
    }
    }
    }


    // Respiration entre le choix de position et la ligne d'historique :
    // les deux règlent la même pilule, mais se lisaient comme un seul
    // bloc compact.
    Item { width: parent.width; height: Theme.space2 * 3 }

    // Historique des lancements de la pilule (style_vars.json : launch_history)
    Row {
    id: launchHistoryRow
    width: parent.width
    spacing: 10

    Text {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - 32 - 10
    - (clearHistBtn.visible ? clearHistBtn.width + 10 : 0)
    text: "Mémoriser les lancements récents dans la pilule"
    color: Theme.fg
    font.pixelSize: Theme.textSm
    elide: Text.ElideRight
    }

    Rectangle {
    id: clearHistBtn
    visible: root.launchHistory
    // 0,8 × la taille du bouton voisin (32) : il efface un historique,
    // il n'a pas à peser autant que la bascule qu'il accompagne.
    width: visible ? clearHistText.implicitWidth + 18 : 0
    height: 26
    radius: Theme.globalRadius
    color: Theme.surfaceVariant
    border.color: Theme.accentMuted
    border.width: 1

    Text {
    id: clearHistText
    anchors.centerIn: parent
    text: "Vider"
    color: Theme.accent
    font.pixelSize: Theme.textSm
    }

    MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clearLaunchHistory()
    }
    }

    Rectangle {
    width: 32
    height: 32
    radius: Theme.globalRadius
    color: Theme.surfaceVariant
    border.color: root.launchHistory ? Theme.success : Theme.error
    border.width: 1

    Text {
    anchors.centerIn: parent
    text: root.launchHistory ? "✓" : "✕"
    color: root.launchHistory ? Theme.success : Theme.error
    font.pixelSize: root.launchHistory ? Theme.textMd : Theme.textSm
    font.bold: true
    }

    MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.runConfigCmd(["style", "launch_history",
    String(!root.launchHistory)])
    }
    }

    }
}


// Accès API : les widgets qui interrogent un service externe ont besoin
// d'une clé. Elle est rangée dans secrets.json (mode 600) et le panneau
// ne montre jamais que ses derniers caractères.

// Cadenas des widgets : hors tiroir, sous les réglages. Il vaut pour
// tout le bureau, pas pour un widget — c'est une garde contre le
// déplacement accidentel (SUPER + SHIFT + clic).
Item { width: 1; height: 12 }

Row {
    width: parent.width
    spacing: 10

    Text {
        width: 200
        anchors.verticalCenter: parent.verticalCenter
        text: "Déplacement des widgets :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Rectangle {
        width: 120
        height: 26
        radius: Theme.globalRadius
        color: Theme.widgetsLocked ? Theme.accent : Theme.surfaceVariant
        border.color: Theme.accent
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 6

            // Glyphe monochrome du jeu d'icônes : l'emoji de cadenas
            // arrive en couleur dans une barre qui n'en a aucun.
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "lock"
                size: Theme.iconSm
                color: Theme.widgetsLocked ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                opacityLevel: 1
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.widgetsLocked ? "Verrouillé" : "Libre"
                color: Theme.widgetsLocked ? Theme.bg : Theme.fg
                font.pixelSize: Theme.textXs
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runConfigCmd([
                "style", "widgets_locked",
                Theme.widgetsLocked ? "false" : "true"
            ])
        }
    }

}

}
