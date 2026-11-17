import QtQuick
import QtQuick.Layouts
import "."

// ══════════════════════════════════════════════════════════════════════
// WHICH-KEY PAR SUBMAP (SubmapWhichKey.qml)
// ══════════════════════════════════════════════════════════════════════
// Overlay deux colonnes affiché automatiquement dès qu'une sous-carte
// Hyprland (`submap`) est active : liste les raccourcis du submap courant
// lus depuis `hyprctl binds -j`.
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property string submapName: ""
    property var binds: []

    function formatKey(key) {
        const k = String(key || "")
        if (k === "Left") return "←"
        if (k === "Right") return "→"
        if (k === "Up") return "↑"
        if (k === "Down") return "↓"
        if (k === "Return") return "Entrée"
        if (k === "Escape") return "Échap"
        if (k === "space") return "Espace"
        return k
    }

    function formatCombo(b) {
        const m = Number(b.modmask || 0)
        const parts = []
        if (m & 64) parts.push("SUPER")
        if (m & 4) parts.push("CTRL")
        if (m & 8) parts.push("ALT")
        if (m & 1) parts.push("SHIFT")
        parts.push(formatKey(b.key))
        return parts.join(" + ")
    }

    implicitWidth: Math.min(760, Math.max(420, contentCol.implicitWidth + 32))
    implicitHeight: contentCol.implicitHeight + 24

    opacity: 0.0
    Component.onCompleted: opacity = 1.0
    Behavior on opacity { NumberAnimation { duration: Theme.panelAnimDuration; easing.type: Easing.OutCubic } }

    SurfaceFloutee {
        anchors.fill: parent
        rayon: Math.max(Theme.globalRadius, 14)
        teinte: Theme.surfaceBg
        bordureCouleur: Qt.alpha(Theme.accent, 0.45)
        bordureLargeur: 1
        actif: true
    }

    Column {
        id: contentCol
        anchors.centerIn: parent
        width: Math.max(388, Math.max(headerRow.implicitWidth, bindsGrid.implicitWidth))
        spacing: 10

        RowLayout {
            id: headerRow
            width: parent.width
            spacing: 10

            Icon {
                glyph: "keyboard"
                size: Theme.iconSm
                color: Theme.accent
            }

            Text {
                text: "SUBMAP · " + root.submapName.toUpperCase()
                font.family: Theme.fontUi
                font.pixelSize: Theme.textXs
                font.weight: Font.Bold
                color: Theme.accent
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Échap / clic extérieur pour quitter"
                font.family: Theme.fontUi
                font.pixelSize: Theme.text2xs
                color: Qt.alpha(Theme.fg, 0.55)
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        Grid {
            id: bindsGrid
            columns: 2
            columnSpacing: 20
            rowSpacing: 6

            Repeater {
                model: root.binds

                delegate: Row {
                    required property var modelData
                    width: 240
                    spacing: 8

                    Rectangle {
                        id: keycap
                        width: Math.max(36, keyLbl.implicitWidth + 12)
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Math.max(4, Math.round(Theme.globalRadius * 0.4))
                        color: Qt.alpha(Theme.surfaceVariant, 0.65)
                        border.width: 1
                        border.color: Qt.alpha(Theme.accent, 0.35)

                        Text {
                            id: keyLbl
                            anchors.centerIn: parent
                            text: root.formatCombo(modelData)
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.text2xs
                            font.weight: Font.Bold
                            color: Theme.accent
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - keycap.width - 8
                        text: String(modelData.description || modelData.dispatcher || "")
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.textXs
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
