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

    // Noms de touches Lua → ce qu'on lit sur le clavier AZERTY.
    readonly property var keyLabels: ({
        "ampersand": "&", "eacute": "é", "quotedbl": "\"", "apostrophe": "'",
        "parenleft": "(", "minus": "-", "egrave": "è", "underscore": "_",
        "ccedilla": "ç", "agrave": "à", "Return": "Entrée", "Escape": "Échap"
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
    readonly property var groups: {
        const out = []
        let cur = null
        for (let i = 0; i < binds.length; ++i) {
            const b = binds[i]
            if (!b || !b.description) continue
            const cat = b.category || "Autres"
            if (!cur || cur.title !== cat) { cur = { title: cat, rows: [] }; out.push(cur) }
            cur.rows.push(b)
        }
        return out
    }

    // Répartition en deux colonnes : on remplit la plus courte.
    readonly property var columns: {
        const left = [], right = []
        let hl = 0, hr = 0
        for (let i = 0; i < groups.length; ++i) {
            const g = groups[i]
            const h = 26 + g.rows.length * 24
            if (hl <= hr) { left.push(g); hl += h } else { right.push(g); hr += h }
        }
        return [left, right]
    }

    implicitWidth: 660
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
                    text: "Raccourcis"
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }
                Item { width: parent.width - 300; height: 1 }
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
                        width: (content.width - 24) / 2
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

                                Repeater {
                                    model: modelData.rows
                                    Row {
                                        required property var modelData
                                        width: parent.width
                                        height: 20
                                        spacing: Theme.space2

                                        Text {
                                            width: 132
                                            text: root.prettyKey(modelData)
                                            color: Qt.alpha(Theme.fg, 0.72)
                                            font.pixelSize: Theme.textXs
                                            font.family: Theme.fontUi
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width - 140
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
