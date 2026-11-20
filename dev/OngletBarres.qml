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

    function barreDe(donnee) {
        const p = String((donnee && donnee.ile) || "haut:fin").split(":")
        return p[0] || "haut"
    }

    function zoneDe(donnee) {
        const p = String((donnee && donnee.ile) || "haut:fin").split(":")
        return p[1] || "milieu"
    }

    function montagesChoisis(donnee) {
        const o = (donnee && donnee.options) || ({})
        if (Array.isArray(o.montages)) return o.montages.slice()
        const defaut = []
        for (let i = 0; i < root.disquesListe.length; ++i) {
            const m = String(root.disquesListe[i].montage || "")
            if (m !== "" && m !== "/") defaut.push(m)
        }
        return defaut
    }

    function montageCoche(donnee, montage) {
        return montagesChoisis(donnee).indexOf(String(montage)) >= 0
    }

    function entreeApplet(id) {
        const cle = String(id || "")
        for (let i = 0; i < root.appletRows.length; ++i) {
            if (String(root.appletRows[i].id) === cle) return root.appletRows[i]
        }
        return null
    }

    function basculerMontage(donnee, montage) {
        const vive = entreeApplet(donnee && donnee.id) || donnee
        const liste = montagesChoisis(vive)
        const i = liste.indexOf(String(montage))
        if (i >= 0) liste.splice(i, 1)
        else liste.push(String(montage))
        root.appletCommande(["option", (vive && vive.id) || donnee.id, "montages", JSON.stringify(liste)])
    }

    function appletBasculer(id, actif) {
        root.appletCommande([actif ? "desactiver" : "activer", id])
    }

    function appletEchelle(id, valeur) {
        const v = Math.max(60, Math.min(160, Math.round(valeur)))
        root.appletCommande(["echelle", id, String(v)])
    }

    function basculerVisualiseur() {
        root.appletCommande([root.vizActif ? "desactiver" : "activer", "visualiseur"])
        root.rechargerVisualiseur()
    }

    function allumerBarrePour(barCode) {
        if (barCode === "bas" && !Theme.barBottomVisible)
            root.runConfigCmd(["style", "bar_bottom", "true"])
        else if (barCode === "cote-gauche" && !Theme.barLeftVisible)
            root.runConfigCmd(["style", "bar_left", "true"])
        else if (barCode === "cote-droite" && !Theme.barRightVisible)
            root.runConfigCmd(["style", "bar_right", "true"])
    }

    function placerApplet(id, ile) {
        root.appletCommande(["placer", id, ile])
        allumerBarrePour(String(ile).split(":")[0])
    }

    function couleurViz(code) {
        return Theme.resolveVizColor(code)
    }

    property string selectedBar: "haut"
    property string selectedAppletId: ""
    property string addPickerZone: ""
    property string hoverCapsuleZone: ""
    property int hoverInsertIdx: -1
    property string hoverBarTab: ""
    property var barTabRefs: ({})
    property var capColDebutRef: null
    property var capColMilieuRef: null
    property var capColFinRef: null

    function findBarTabDrop(px, py) {
        const codes = ["haut", "bas", "cote-gauche", "cote-droite"]
        for (let i = 0; i < codes.length; ++i) {
            const tab = barTabRefs[codes[i]]
            if (!tab || !root) continue
            const pt = root.mapToItem(tab, px, py)
            if (pt.x >= 0 && pt.x <= tab.width && pt.y >= 0 && pt.y <= tab.height) {
                return codes[i]
            }
        }
        return ""
    }

    function updateCapsuleDrag(px, py) {
        hoverBarTab = findBarTabDrop(px, py)
        const hit = findCapsuleDrop(px, py)
        hoverCapsuleZone = hit ? hit.zone : ""
        hoverInsertIdx = hit ? hit.idx : -1
    }

    function finishCapsuleDrag(aid, px, py) {
        const bHit = findBarTabDrop(px, py)
        const hit = findCapsuleDrop(px, py)
        if (bHit !== "") {
            bloc.selectedBar = bHit
            root.appletCommande(["deplacer_vers", aid, bHit + ":milieu"])
            bloc.allumerBarrePour(bHit)
        } else if (hit) {
            root.appletCommande(["deplacer_vers", aid, bloc.selectedBar + ":" + hit.zone, String(hit.idx)])
            bloc.allumerBarrePour(bloc.selectedBar)
        }
        hoverBarTab = ""
        hoverCapsuleZone = ""
        hoverInsertIdx = -1
    }

    function cancelCapsuleDrag() {
        hoverBarTab = ""
        hoverCapsuleZone = ""
        hoverInsertIdx = -1
    }

    function appletsInZone(barCode, zoneCode) {
        const _ = root.appletSignature
        const target = barCode + ":" + zoneCode
        const list = []
        const rows = root.appletRows || []
        for (let i = 0; i < rows.length; ++i) {
            const a = rows[i]
            if (!a || !a.actif || a.fixe) continue
            if (String(a.ile || "") === target) list.push(a)
        }
        list.sort((a, b) => (Number(a.ordre) || 100) - (Number(b.ordre) || 100))
        return list
    }

    function inactiveApplets() {
        const _ = root.appletSignature
        const list = []
        const rows = root.appletRows || []
        for (let i = 0; i < rows.length; ++i) {
            const a = rows[i]
            if (!a || a.actif || a.fixe) continue
            list.push(a)
        }
        return list
    }

    function findCapsuleDrop(px, py) {
        const cols = [capColDebutRef, capColMilieuRef, capColFinRef]
        const zones = ["debut", "milieu", "fin"]
        for (let i = 0; i < cols.length; ++i) {
            const col = cols[i]
            if (!col) continue
            const pt = root.mapToItem(col, px, py)
            if (pt.x >= 0 && pt.x <= col.width && pt.y >= 0 && pt.y <= col.height) {
                const count = bloc.appletsInZone(bloc.selectedBar, zones[i]).length
                const relY = pt.y - 36
                const idx = Math.max(0, Math.min(count, Math.round(relY / 38)))
                return ({ zone: zones[i], idx: idx })
            }
        }
        return null
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

            ConfigSegmented {
                anchors.verticalCenter: parent.verticalCenter
                itemHeight: 24
                choices: [
                    { code: "classic", label: "Classique (3 îlots)" },
                    { code: "island",  label: "Îlot dynamique" }
                ]
                currentCode: Theme.barStyle
                onSelected: function(code) { root.runConfigCmd(["style", "bar_style", code]) }
            }
        }

        // 4c. Activation de l'onglet Projets (Kanban Planka) dans l'Îlot dynamique
        Row {
            visible: Theme.barStyle === "island"
            width: parent.width
            spacing: 8

            Text {
                width: 160
                anchors.verticalCenter: parent.verticalCenter
                text: "Onglet Projets (Kanban) :"
                color: Theme.fg
                font.pixelSize: Theme.textSm
                elide: Text.ElideRight
            }

            ConfigSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: Theme.ilotProjetsActif
                onToggled: root.runConfigCmd(["style", "ilot_projets_actif", Theme.ilotProjetsActif ? "false" : "true"])
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
                minimumValue: 14
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
                maximumValue: 280
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

            ConfigSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: Theme.showConfigButton
                onToggled: root.runConfigCmd(["style", "show_config_button", String(!Theme.showConfigButton)])
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
        Repeater {
            model: [
                { label: "Barre du bas",    key: "bar_bottom", val: Theme.barBottomVisible },
                { label: "Barre de gauche", key: "bar_left",   val: Theme.barLeftVisible },
                { label: "Barre de droite", key: "bar_right",  val: Theme.barRightVisible }
            ]
            delegate: Item {
                required property var modelData
                width: parent ? parent.width : 0
                height: 22

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                }

                ConfigSwitch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    checked: modelData.val
                    onToggled: root.runConfigCmd(["style", modelData.key, String(!modelData.val)])
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
        spacing: 10

        // En-tête : choix de barre + Réinitialiser + Ajouter
        Item {
            width: parent.width
            height: 30

            Row {
                id: barSelectSeg
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: [
                        { code: "haut",        label: "Haut" },
                        { code: "bas",         label: "Bas" },
                        { code: "cote-gauche", label: "Gauche" },
                        { code: "cote-droite", label: "Droite" }
                    ]

                    delegate: Rectangle {
                        id: barTab
                        required property var modelData
                        readonly property bool actif: bloc.selectedBar === modelData.code
                        readonly property bool dropHover: root && root.dragCapsuleId !== "" && bloc.hoverBarTab === modelData.code
                        width: Math.max(54, barTabLbl.implicitWidth + 18)
                        height: 26
                        radius: Theme.globalRadius
                        color: dropHover
                            ? Qt.alpha(Theme.accent, 0.28)
                            : (actif ? Theme.accent : (barTabMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55)))
                        border.color: (dropHover || actif) ? Theme.accent : Qt.alpha(Theme.fg, 0.12)
                        border.width: dropHover ? 2 : 1

                        Component.onCompleted: {
                            const r = Object.assign({}, bloc.barTabRefs)
                            r[modelData.code] = barTab
                            bloc.barTabRefs = r
                        }

                        Text {
                            id: barTabLbl
                            anchors.centerIn: parent
                            text: barTab.modelData.label
                            color: barTab.actif ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.text2xs
                            font.bold: barTab.actif || barTab.dropHover
                        }

                        MouseArea {
                            id: barTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                bloc.selectedBar = barTab.modelData.code
                                bloc.addPickerZone = ""
                            }
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Rectangle {
                    width: resetLbl.implicitWidth + 18
                    height: 26
                    radius: Theme.globalRadius
                    color: resetMa.containsMouse ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.55)
                    border.color: Qt.alpha(Theme.fg, 0.14)
                    border.width: 1

                    Text {
                        id: resetLbl
                        anchors.centerIn: parent
                        text: "↺ Défaut"
                        color: Theme.fg
                        font.pixelSize: Theme.text2xs
                    }

                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            bloc.selectedAppletId = ""
                            bloc.addPickerZone = ""
                            root.appletCommande(["reinitialiser"])
                        }
                    }
                }

                Rectangle {
                    width: addTopLbl.implicitWidth + 20
                    height: 26
                    radius: Theme.globalRadius
                    color: bloc.addPickerZone !== "" ? Theme.accent : (addTopMa.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Qt.alpha(Theme.accent, 0.88))

                    Text {
                        id: addTopLbl
                        anchors.centerIn: parent
                        text: bloc.addPickerZone !== "" ? "Fermer" : "+ Ajouter"
                        color: Theme.bg
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                    }

                    MouseArea {
                        id: addTopMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bloc.addPickerZone = (bloc.addPickerZone !== "" ? "" : "fin")
                    }
                }
            }
        }

        // Catalogue rapide d'ajout d'un applet inactif dans la capsule choisie
        Rectangle {
            visible: bloc.addPickerZone !== ""
            width: parent.width
            height: visible ? addPickerCol.implicitHeight + 16 : 0
            radius: Theme.globalRadius
            color: Qt.alpha(Theme.surfaceVariant, 0.65)
            border.color: Theme.accent
            border.width: 1

            Column {
                id: addPickerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                Text {
                    readonly property string zoneName: (bloc.selectedBar === "haut" || bloc.selectedBar === "bas")
                        ? (bloc.addPickerZone === "debut" ? "Gauche" : (bloc.addPickerZone === "milieu" ? "Centre" : "Droite"))
                        : (bloc.addPickerZone === "debut" ? "Haut" : (bloc.addPickerZone === "milieu" ? "Centre" : "Bas"))
                    text: "Ajouter un applet dans « " + zoneName + " » :"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: bloc.inactiveApplets()

                        Rectangle {
                            id: addChipRect
                            required property var modelData
                            width: addChipTxt.implicitWidth + 22
                            height: 26
                            radius: Theme.globalRadius
                            color: addChipMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                            border.color: Qt.alpha(Theme.fg, 0.14)
                            border.width: 1

                            Text {
                                id: addChipTxt
                                anchors.centerIn: parent
                                text: "+ " + modelData.nom
                                color: addChipMa.containsMouse ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                            }

                            MouseArea {
                                id: addChipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: dragging
                                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property real startX: 0
                                property real startY: 0
                                property bool dragging: false

                                onPressed: mouse => {
                                    startX = mouse.x
                                    startY = mouse.y
                                    dragging = false
                                }

                                onPositionChanged: mouse => {
                                    if (!pressed || !root) return
                                    if (!dragging && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                                        dragging = true
                                        root.dragCapsuleId = addChipRect.modelData.id
                                        root.dragCapsuleLabel = addChipRect.modelData.nom
                                    }
                                            if (dragging) {
                                                const pt = addChipRect.mapToItem(root, mouse.x, mouse.y)
                                                root.dragPointerX = pt.x
                                                root.dragPointerY = pt.y
                                                bloc.updateCapsuleDrag(pt.x, pt.y)
                                            }
                                        }

                                        onReleased: {
                                            if (dragging && root) {
                                                bloc.finishCapsuleDrag(addChipRect.modelData.id, root.dragPointerX, root.dragPointerY)
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                                dragging = false
                                                return
                                            }
                                            dragging = false
                                            root.appletCommande(["deplacer_vers", addChipRect.modelData.id, bloc.selectedBar + ":" + bloc.addPickerZone])
                                            bloc.addPickerZone = ""
                                        }

                                        onCanceled: {
                                            dragging = false
                                            bloc.cancelCapsuleDrag()
                                            if (root) {
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                            }
                                        }

                                        Component.onDestruction: {
                                            if (dragging && root) {
                                                dragging = false
                                                bloc.cancelCapsuleDrag()
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                            }
                                        }
                            }
                        }
                    }

                    Text {
                        visible: bloc.inactiveApplets().length === 0
                        text: "Tous les applets sont déjà placés sur une barre."
                        color: Qt.alpha(Theme.fg, 0.55)
                        font.pixelSize: Theme.text2xs
                    }
                }
            }
        }

        // Tableau 3 colonnes : Capsule Gauche / Centre / Droite (ou Haut / Centre / Bas)
        Row {
            id: capsulesBoard
            width: parent.width
            spacing: 8
            readonly property real colW: Math.floor((width - spacing * 2) / 3)
            readonly property bool horizontalBar: bloc.selectedBar === "haut" || bloc.selectedBar === "bas"

            Repeater {
                model: [
                    { code: "debut",  labelH: "Capsule Gauche", labelV: "Haut" },
                    { code: "milieu", labelH: "Capsule Centre", labelV: "Centre" },
                    { code: "fin",    labelH: "Capsule Droite", labelV: "Bas" }
                ]

                delegate: Rectangle {
                    id: capCol
                    required property var modelData
                    required property int index
                    readonly property string zoneCode: modelData.code
                    readonly property var items: bloc.appletsInZone(bloc.selectedBar, zoneCode)
                    readonly property bool isDropTarget: root && root.dragCapsuleId !== "" && bloc.hoverCapsuleZone === zoneCode

                    width: capsulesBoard.colW
                    height: Math.max(120, capColInner.implicitHeight + 16)
                    radius: Theme.globalRadius
                    color: isDropTarget ? Qt.alpha(Theme.accent, 0.10) : Qt.alpha(Theme.surfaceVariant, 0.35)
                    border.color: isDropTarget ? Theme.accent : Qt.alpha(Theme.fg, 0.12)
                    border.width: isDropTarget ? 2 : 1

                    Component.onCompleted: {
                        if (index === 0) bloc.capColDebutRef = capCol
                        else if (index === 1) bloc.capColMilieuRef = capCol
                        else if (index === 2) bloc.capColFinRef = capCol
                    }

                    Column {
                        id: capColInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                id: colTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: capsulesBoard.horizontalBar ? capCol.modelData.labelH : capCol.modelData.labelV
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: true
                            }

                            Rectangle {
                                anchors.left: colTitle.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(18, cntTxt.implicitWidth + 8)
                                height: 16
                                radius: 8
                                color: Qt.alpha(Theme.fg, 0.12)

                                Text {
                                    id: cntTxt
                                    anchors.centerIn: parent
                                    text: String(capCol.items.length)
                                    color: Qt.alpha(Theme.fg, 0.8)
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 5
                                color: colAddMa.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.10)

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    color: colAddMa.containsMouse ? Theme.bg : Theme.fg
                                    font.pixelSize: Theme.textXs
                                    font.bold: true
                                }

                                MouseArea {
                                    id: colAddMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bloc.addPickerZone = (bloc.addPickerZone === capCol.zoneCode ? "" : capCol.zoneCode)
                                }
                            }
                        }

                        Text {
                            visible: capCol.items.length === 0
                            width: parent.width
                            height: 44
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: "Vide · Glisser ou +"
                            color: Qt.alpha(Theme.fg, 0.38)
                            font.pixelSize: Theme.text2xs
                        }

                        Repeater {
                            model: capCol.items

                            delegate: Column {
                                id: cardWrap
                                required property var modelData
                                required property int index
                                readonly property bool selected: bloc.selectedAppletId === modelData.id
                                width: parent.width
                                spacing: 2

                                Rectangle {
                                    visible: capCol.isDropTarget && bloc.hoverInsertIdx === cardWrap.index
                                    width: parent.width
                                    height: 2
                                    radius: 1
                                    color: Theme.accent
                                }

                                Rectangle {
                                    id: appCard
                                    width: parent.width
                                    height: 34
                                    radius: Math.max(6, Math.round(Theme.globalRadius * 0.6))
                                    color: cardWrap.selected
                                        ? Qt.alpha(Theme.accent, 0.18)
                                        : (cardMa.containsMouse ? Qt.alpha(Theme.surfaceVariant, 0.95) : Theme.surfaceVariant)
                                    border.color: cardWrap.selected ? Theme.accent : Qt.alpha(Theme.fg, 0.10)
                                    border.width: 1

                                    MouseArea {
                                        id: cardMa
                                        anchors.left: parent.left
                                        anchors.right: optBtn.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.rightMargin: 2
                                        hoverEnabled: true
                                        preventStealing: dragging
                                        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property real startX: 0
                                        property real startY: 0
                                        property bool dragging: false

                                        onPressed: mouse => {
                                            startX = mouse.x
                                            startY = mouse.y
                                            dragging = false
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed || !root) return
                                            if (!dragging && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                                                dragging = true
                                                root.dragCapsuleId = cardWrap.modelData.id
                                                root.dragCapsuleLabel = cardWrap.modelData.nom
                                            }
                                            if (dragging) {
                                                const pt = appCard.mapToItem(root, mouse.x, mouse.y)
                                                root.dragPointerX = pt.x
                                                root.dragPointerY = pt.y
                                                bloc.updateCapsuleDrag(pt.x, pt.y)
                                            }
                                        }

                                        onReleased: {
                                            if (dragging && root) {
                                                bloc.finishCapsuleDrag(cardWrap.modelData.id, root.dragPointerX, root.dragPointerY)
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                                dragging = false
                                                return
                                            }
                                            dragging = false
                                            bloc.selectedAppletId = (bloc.selectedAppletId === cardWrap.modelData.id ? "" : cardWrap.modelData.id)
                                        }

                                        onCanceled: {
                                            dragging = false
                                            bloc.cancelCapsuleDrag()
                                            if (root) {
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                            }
                                        }

                                        Component.onDestruction: {
                                            if (dragging && root) {
                                                dragging = false
                                                bloc.cancelCapsuleDrag()
                                                root.dragCapsuleId = ""
                                                root.dragCapsuleLabel = ""
                                            }
                                        }
                                    }

                                    Text {
                                        id: dragGrip
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "⋮⋮"
                                        color: Qt.alpha(Theme.fg, 0.35)
                                        font.pixelSize: 10
                                    }

                                    Icon {
                                        id: appIco
                                        anchors.left: dragGrip.right
                                        anchors.leftMargin: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: String(cardWrap.modelData.icone || "widgets")
                                        size: Theme.iconXs
                                        color: Theme.accent
                                    }

                                    Text {
                                        anchors.left: appIco.right
                                        anchors.leftMargin: 6
                                        anchors.right: optBtn.left
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cardWrap.modelData.nom
                                        color: Theme.fg
                                        font.pixelSize: Theme.text2xs
                                        font.bold: cardWrap.selected
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: optBtn
                                        anchors.right: remBtn.left
                                        anchors.rightMargin: 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20
                                        height: 20
                                        radius: 4
                                        color: cardWrap.selected ? Theme.accent : (optMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : "transparent")

                                        Icon {
                                            anchors.centerIn: parent
                                            glyph: "cog"
                                            size: 11
                                            color: cardWrap.selected ? Theme.bg : Qt.alpha(Theme.fg, 0.65)
                                        }

                                        MouseArea {
                                            id: optMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: bloc.selectedAppletId = (bloc.selectedAppletId === cardWrap.modelData.id ? "" : cardWrap.modelData.id)
                                        }
                                    }

                                    Rectangle {
                                        id: remBtn
                                        anchors.right: parent.right
                                        anchors.rightMargin: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        radius: 4
                                        color: remMa.containsMouse ? Qt.alpha(Theme.error, 0.22) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            color: remMa.containsMouse ? Theme.error : Qt.alpha(Theme.fg, 0.45)
                                            font.pixelSize: 10
                                        }

                                        MouseArea {
                                            id: remMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (bloc.selectedAppletId === cardWrap.modelData.id) bloc.selectedAppletId = ""
                                                root.appletCommande(["desactiver", cardWrap.modelData.id])
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: capCol.isDropTarget && bloc.hoverInsertIdx >= capCol.items.length
                            width: parent.width
                            height: 2
                            radius: 1
                            color: Theme.accent
                        }
                    }
                }
            }
        }

        // Options de l'applet sélectionné (échelle + choix + cases + disques)
        Rectangle {
            id: selectedOptBox
            readonly property var donnee: {
                const _ = root.appletSignature
                const e = bloc.selectedAppletId !== "" ? bloc.entreeApplet(bloc.selectedAppletId) : null
                return (e && e.actif) ? e : null
            }
            visible: donnee !== null
            width: parent.width
            height: visible ? selOptCol.implicitHeight + 16 : 0
            radius: Theme.globalRadius
            color: Qt.alpha(Theme.surfaceVariant, 0.45)
            border.color: Qt.alpha(Theme.accent, 0.45)
            border.width: 1

            Column {
                id: selOptCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 8

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: selectedOptBox.donnee ? ("Options · " + selectedOptBox.donnee.nom) : ""
                        color: Theme.accent
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Taille"
                            color: Qt.alpha(Theme.fg, 0.7)
                            font.pixelSize: Theme.text2xs
                        }

                        Stepper {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 96
                            value: selectedOptBox.donnee ? selectedOptBox.donnee.text_scale : 100
                            minimumValue: 60
                            maximumValue: 160
                            stepSize: 5
                            suffix: " %"
                            onValueModified: newVal => {
                                if (selectedOptBox.donnee) bloc.appletEchelle(selectedOptBox.donnee.id, newVal)
                            }
                        }
                    }
                }

                // Choix catalogue
                Row {
                    visible: selectedOptBox.donnee && selectedOptBox.donnee.choix !== undefined
                    width: parent.width
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (selectedOptBox.donnee && selectedOptBox.donnee.choix && selectedOptBox.donnee.choix.libelle)
                            ? String(selectedOptBox.donnee.choix.libelle) : ""
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.text2xs
                    }

                    Repeater {
                        model: (selectedOptBox.donnee && selectedOptBox.donnee.choix && selectedOptBox.donnee.choix.valeurs) || []

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: {
                                if (!selectedOptBox.donnee) return false
                                const o = selectedOptBox.donnee.options || ({})
                                const cle = selectedOptBox.donnee.choix ? selectedOptBox.donnee.choix.cle : ""
                                return String(o[cle] || "") === String(modelData.code)
                            }
                            width: chLbl.implicitWidth + 16
                            height: 22
                            radius: 5
                            color: choisi ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.25)

                            Text {
                                id: chLbl
                                anchors.centerIn: parent
                                text: String(modelData.nom || modelData.code)
                                color: choisi ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: choisi
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (selectedOptBox.donnee)
                                    root.appletCommande(["option", selectedOptBox.donnee.id, selectedOptBox.donnee.choix.cle, String(modelData.code)])
                            }
                        }
                    }
                }

                // Cases booléennes catalogue
                Flow {
                    visible: selectedOptBox.donnee && (selectedOptBox.donnee.cases || []).length > 0
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: (selectedOptBox.donnee && selectedOptBox.donnee.cases) || []

                        Rectangle {
                            required property var modelData
                            readonly property bool coche: {
                                const _ = root.appletSignature
                                if (!selectedOptBox.donnee) return true
                                const o = selectedOptBox.donnee.options || ({})
                                const v = o[modelData.cle]
                                if (v === undefined || v === null || v === "") return true
                                return !(v === false || v === "false" || v === 0 || v === "0")
                            }
                            width: caseTexte.implicitWidth + 16
                            height: 22
                            radius: 5
                            color: coche ? Theme.accent : Theme.surfaceVariant
                            border.width: 1
                            border.color: coche ? Theme.accent : Qt.alpha(Theme.fg, 0.25)

                            Text {
                                id: caseTexte
                                anchors.centerIn: parent
                                text: (coche ? "✓ " : "✕ ") + String(modelData.libelle || modelData.cle)
                                color: coche ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.text2xs
                                font.bold: coche
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (selectedOptBox.donnee)
                                    root.appletCommande(["option", selectedOptBox.donnee.id, modelData.cle, coche ? "false" : "true"])
                            }
                        }
                    }
                }

                // Disques affichés
                CollapsibleSection {
                    id: secDisques
                    objectName: "secDisques"
                    visible: selectedOptBox.donnee && selectedOptBox.donnee.liste !== undefined
                    title: String((selectedOptBox.donnee && selectedOptBox.donnee.liste && selectedOptBox.donnee.liste.libelle) || "Disques affichés")
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

                            Item {
                                required property var modelData
                                readonly property string montage: String(modelData.montage || "")
                                readonly property bool coche: {
                                    const _ = root.appletSignature
                                    if (!selectedOptBox.donnee) return false
                                    return bloc.montageCoche(selectedOptBox.donnee, montage)
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
                                    border.color: parent.coche ? Theme.accent : Qt.alpha(Theme.fg, 0.4)

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
                                    onClicked: if (selectedOptBox.donnee) bloc.basculerMontage(selectedOptBox.donnee, parent.montage)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
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
                        onClicked: bloc.basculerVisualiseur()
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

            // Rendu indépendant Barre / Îlot : une ligne qui ne défile pas (onde)
            // ou des bandes qui montent avec la musique (barres).
            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: 160
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mode (Barre) :"
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
                        color: root.vizStyleClassic === modelData.code ? Theme.accent
                                                                       : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.vizStyleClassic === modelData.code
                                  ? ("✓ " + modelData.nom) : modelData.nom
                            color: root.vizStyleClassic === modelData.code ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.vizStyleClassic = modelData.code
                                root.runConfigCmd(["style", "viz_style_classic", modelData.code])
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8

                Text {
                    width: 160
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mode (Îlot) :"
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
                        color: root.vizStyleIsland === modelData.code ? Theme.accent
                                                                      : Theme.surfaceVariant
                        border.color: Theme.accent
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: root.vizStyleIsland === modelData.code
                                  ? ("✓ " + modelData.nom) : modelData.nom
                            color: root.vizStyleIsland === modelData.code ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.vizStyleIsland = modelData.code
                                root.runConfigCmd(["style", "viz_style_island", modelData.code])
                            }
                        }
                    }
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

                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Couleur (Barre) :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }

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
                            color: choisi ? bloc.couleurViz(modelData.code) : "transparent"
                            border.color: bloc.couleurViz(modelData.code)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.nom
                                color: parent.choisi ? Theme.bg : bloc.couleurViz(modelData.code)
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

            Row {
                width: parent.width
                spacing: 8

                Text { width: 160; anchors.verticalCenter: parent.verticalCenter; text: "Couleur (Îlot) :"; color: Theme.fg; font.pixelSize: Theme.textSm; elide: Text.ElideRight }

                Flow {
                    spacing: 6
                    width: parent.width - 168
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.vizCouleurs

                        Rectangle {
                            required property var modelData
                            readonly property bool choisi: root.vizCouleurIsland === modelData.code
                            width: 74; height: 22; radius: Theme.globalRadius
                            color: choisi ? bloc.couleurViz(modelData.code) : "transparent"
                            border.color: bloc.couleurViz(modelData.code)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.nom
                                color: parent.choisi ? Theme.bg : bloc.couleurViz(modelData.code)
                                font.pixelSize: Math.max(8, Theme.textXs - 2)
                                font.bold: parent.choisi
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.vizCouleurIsland = modelData.code
                                    root.runConfigCmd(["style", "viz_couleur_island", modelData.code])
                                }
                            }
                        }
                    }
                }
            }
        }
    }


}
