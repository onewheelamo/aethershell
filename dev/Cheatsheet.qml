import QtQuick
import Quickshell
import Quickshell.Io

// ────────────────────────────────────────────────────────────────────────────
// ÉCRAN DES RACCOURCIS (SUPER + K)
//
// La liste ne vient pas d'ici : elle vient de `binds.lua`, via
// `config_manager.py state` → `binds`, et ne retient que les binds qui portent
// une `description`. Un raccourci ajouté dans binds.lua apparaît donc ici, et un
// raccourci renommé ne peut pas diverger de la réalité.
//
// Position fixe : cette surface est centrée par main.qml, comme le panneau de
// configuration. Seuls l'opacité et le flou sont réglables (style_vars).
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var binds: []
    property color surfaceColor: Qt.alpha(Theme.surface, 0.88)

    // Deux niveaux de lecture : « essentiel » au premier abord (les gestes du
    // quotidien), « tout » pour qui veut découvrir le reste — redimensionner,
    // envoyer une fenêtre sur un autre bureau, la souris. Le marquage vit dans
    // binds.lua (`-- essentiel` en fin de ligne), pas ici.
    property bool etendu: false

    // Noms de touches Lua → ce qu'on lit sur le clavier AZERTY.
    readonly property var keyLabels: ({
        "ampersand": "&", "eacute": "é", "quotedbl": "\"", "apostrophe": "'",
        "parenleft": "(", "minus": "-", "egrave": "è", "underscore": "_",
        "ccedilla": "ç", "agrave": "à", "Return": "Entrée", "Escape": "Échap",
        "mouse:272": "clic gauche", "mouse:273": "clic droit",
        "mouse_down": "molette bas", "mouse_up": "molette haut"
    })

    // Ce qu'un débutant ne devine pas : la même flèche change de sens selon le
    // modificateur. Une ligne d'explication vaut mieux que dix raccourcis nus.
    readonly property var astuces: ({
        "Fenêtres": "SUPER + flèche espace · + SHIFT redimensionne · + CTRL échange deux fenêtres",
        "Workspaces": "SUPER + chiffre va au bureau · + SHIFT y envoie la fenêtre · + ALT l'y envoie et suit",
        "Souris": "SUPER + molette change de bureau, SUPER + glisser déplace la fenêtre"
    })

    function prettyKey(b) {
        if (!b) return ""
        const parts = String(b.key || "").split("+").map(s => s.trim())
        const key = parts.pop() || ""
        const label = keyLabels[key] || key
        // Tous ces binds partent de mainMod : on l'affiche, sinon « Q » ne dit
        // pas grand-chose dans un écran de raccourcis.
        return [b.mod || "SUPER"].concat(parts, [label]).join(" + ")
    }

    // Regroupement par catégorie, dans l'ordre du fichier.
    // Dix bureaux × deux modificateurs = vingt lignes identiques à une lettre
    // près. On les replie en deux motifs : c'est la règle qu'on veut faire
    // comprendre, pas la liste qu'on veut faire défiler.
    readonly property var familles: [
        { motif: /^envoyer la fenêtre sur le bureau \d+$/, cle: "SHIFT + 1…0",
          texte: "envoyer la fenêtre sur le bureau N (et rester ici)" },
        { motif: /^envoyer la fenêtre sur le bureau \d+ et l'y suivre$/, cle: "ALT + 1…0",
          texte: "envoyer la fenêtre sur le bureau N et l'y suivre" }
    ]

    function _replier(rows) {
        const out = []
        const posees = []
        for (let i = 0; i < rows.length; ++i) {
            const b = rows[i]
            let repliee = false
            for (let f = 0; f < familles.length; ++f) {
                if (familles[f].motif.test(b.description)) {
                    if (posees.indexOf(f) < 0) {
                        posees.push(f)
                        out.push({ mod: b.mod, key: familles[f].cle, description: familles[f].texte })
                    }
                    repliee = true
                    break
                }
            }
            if (!repliee) out.push(b)
        }
        return out
    }

    readonly property var groups: {
        const out = []
        let cur = null
        for (let i = 0; i < binds.length; ++i) {
            const b = binds[i]
            if (!b || !b.description) continue
            if (!etendu && !b.essentiel) continue
            const cat = b.category || "Autres"
            if (!cur || cur.title !== cat) { cur = { title: cat, rows: [] }; out.push(cur) }
            cur.rows.push(b)
        }
        for (let i = 0; i < out.length; ++i) out[i].rows = _replier(out[i].rows)
        return out
    }

    // Répartition en deux colonnes : on remplit la plus courte.
    readonly property int nbColonnes: 2

    readonly property var columns: {
        const cols = []
        const poids = []
        for (let c = 0; c < nbColonnes; ++c) { cols.push([]); poids.push(0) }
        for (let i = 0; i < groups.length; ++i) {
            const g = groups[i]
            const h = 26 + g.rows.length * 24
            let k = 0
            for (let c = 1; c < nbColonnes; ++c) if (poids[c] < poids[k]) k = c
            cols[k].push(g); poids[k] += h
        }
        return cols
    }

    implicitWidth: etendu ? 900 : 660
    implicitHeight: Math.max(180, content.implicitHeight + 44)

    Rectangle {
        anchors.fill: parent
        radius: Theme.globalRadius
        color: root.surfaceColor
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.18)

        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 22
            spacing: Theme.space3

            Row {
                width: parent.width
                spacing: Theme.space2

                Icon { anchors.verticalCenter: parent.verticalCenter; glyph: "keyboard"; size: Theme.iconSm; color: Theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AetherShell — raccourcis"
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }
                Item { width: Math.max(0, parent.width - 420); height: 1 }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: basculeTexte.implicitWidth + 22
                    height: 22
                    radius: height / 2
                    color: survolBascule.containsMouse
                        ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.accent, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(Theme.accent, root.etendu ? 0.55 : 0.22)

                    Text {
                        id: basculeTexte
                        anchors.centerIn: parent
                        text: root.etendu ? "Essentiel" : "Tout afficher"
                        color: Theme.accent
                        font.pixelSize: Theme.text2xs
                        font.bold: true
                    }

                    MouseArea {
                        id: survolBascule
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.etendu = !root.etendu
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SUPER + K pour fermer"
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.09) }

            Row {
                width: parent.width
                spacing: 24

                Repeater {
                    model: root.columns
                    Column {
                        required property var modelData
                        width: (content.width - (root.nbColonnes - 1) * 24) / root.nbColonnes
                        spacing: Theme.space3

                        Repeater {
                            model: modelData
                            Column {
                                required property var modelData
                                width: parent.width
                                spacing: 4

                                Text {
                                    text: modelData.title.toUpperCase()
                                    color: Qt.alpha(Theme.accent, 0.85)
                                    font.pixelSize: Theme.text2xs
                                    font.bold: true
                                    font.letterSpacing: 0.6
                                }

                                // En mode étendu seulement : sinon le panneau
                                // court se remplit de prose.
                                Text {
                                    visible: root.etendu && root.astuces[modelData.title] !== undefined
                                    width: parent.width
                                    text: root.astuces[modelData.title] || ""
                                    color: Qt.alpha(Theme.fg, 0.42)
                                    font.pixelSize: Theme.text2xs
                                    wrapMode: Text.WordWrap
                                    bottomPadding: 2
                                }

                                Repeater {
                                    model: modelData.rows
                                    Row {
                                        required property var modelData
                                        width: parent.width
                                        height: 20
                                        spacing: Theme.space2

                                        Text {
                                            width: root.etendu ? 142 : 132
                                            text: root.prettyKey(modelData)
                                            color: Qt.alpha(Theme.fg, 0.72)
                                            font.pixelSize: Theme.textXs
                                            font.family: Theme.fontUi
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width - (root.etendu ? 150 : 140)
                                            text: modelData.description
                                            color: Theme.fg
                                            font.pixelSize: Theme.textXs
                                            elide: Text.ElideRight
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
