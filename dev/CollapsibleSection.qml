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
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    visible: root.icon !== ""
                    text: root.icon
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.title
                    color: root.titleColor
                    font.pixelSize: 13
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.expanded ? "▼" : "▶"
                color: Theme.accent
                font.pixelSize: 11
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
