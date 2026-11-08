import QtQuick

// ═══════════════════════════════════════════════════════════════════════════════
// COMPOSANT COLLAPSIBLE SECTION : SECTION DÉROULANTE PLIABLE
// ═══════════════════════════════════════════════════════════════════════════════
// Utilisé dans le panneau de configuration pour organiser les catégories.
// - Bandeau d'en-tête interactif avec icône, titre et indicateur fléché (▼ / ▶)
// - Zone de contenu interne encapsulée via l'alias `contentCol.data`
// - Masquage et clippage stricts lorsque la section est repliée (hauteur 0)
// - Animation de déploiement fluide en 180 ms (Easing.OutCubic)
Item {
    id: root

    // ─────────────────────────────────────────────────────────────────────────────
    // 1. Dimensions, Propriétés & Alias de contenu
    // ─────────────────────────────────────────────────────────────────────────────
    width: parent ? parent.width : 400
    implicitHeight: col.implicitHeight
    height: implicitHeight

    property string title: ""
    // Résumé d'état affiché à droite du titre, sur le bandeau replié : d'un coup
    // d'œil on lit les réglages actifs d'un onglet sans rien déplier (point 3 des
    // maquettes). Vide = rien à dire, le bandeau reste tel quel.
    property string summary: ""
    property string icon: ""
    property bool expanded: false
    property color headerColor: Theme.surfaceBg
    property color titleColor: Theme.fg

    signal toggled(bool expanded)

    // Redirige tous les enfants QML déclarés à l'intérieur vers le conteneur scrollé
    default property alias content: contentCol.data

    Column {
        id: col
        width: parent.width
        spacing: 0

        // ─────────────────────────────────────────────────────────────────────────
        // 2. Bandeau d'en-tête (Titre, Icône & Flèche de bascule)
        // ─────────────────────────────────────────────────────────────────────────
        Rectangle {
            id: header
            width: parent.width
            height: 34
            implicitHeight: 34
            radius: Theme.globalRadius
            color: headerMa.containsMouse ? Theme.surfaceVariantBg : root.headerColor
            border.color: Theme.surfaceVariant
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.padH
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space2

            Icon {
                visible: root.icon !== ""
                glyph: root.icon
                size: Theme.iconSm
                color: Theme.accent
                opacityLevel: 1
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.title
                color: root.titleColor
                font.pixelSize: Theme.textMd
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            }

            Text {
                id: arrow
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.expanded ? "▼" : "▶"
                color: Theme.accent
                font.pixelSize: Theme.textXs
            }

            // Le résumé s'arrête avant la flèche et s'élide : il ne prend jamais
            // la place du titre, même sur un bandeau étroit (barre latérale).
            Text {
                id: resume
                visible: root.summary !== ""
                anchors.right: arrow.left
                anchors.rightMargin: Theme.space2 * 2
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width * 0.48)
                horizontalAlignment: Text.AlignRight
                text: root.summary
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: Theme.textXs
                elide: Text.ElideRight
            }

            MouseArea {
                id: headerMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.expanded = !root.expanded
                    root.toggled(root.expanded)
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────────────
        // 3. Zone de contenu clippée et animée
        // ─────────────────────────────────────────────────────────────────────────
        Item {
            id: bodyClip
            width: parent.width
            height: root.expanded ? contentCol.implicitHeight : 0
            implicitHeight: height
            clip: true
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Column {
                id: contentCol
                width: parent.width
                topPadding: 10
                visible: root.expanded || bodyClip.height > 0
            }
        }
    }
}
