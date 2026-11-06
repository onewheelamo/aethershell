import QtQuick
import "."

// ════════════════════════════════════════════════════════════════════════════
// ÎLOT GAUCHE — un conteneur, plus rien de plus.
// ════════════════════════════════════════════════════════════════════════════
// Les bureaux Hyprland étaient ici en dur, avec leur modèle, leurs envois et leur
// molette. Ils sont devenus l'applet « workspaces » (WorkspacesApplet.qml) : cet
// îlot ne fait plus que dessiner son fond et poser la rangée d'applets que le
// registre lui attribue. C'est ce qui rend la barre modulaire : déplacer les
// bureaux à droite, ou les éteindre, ne demande plus de toucher ce fichier.
Item {
    id: islandLeft
    implicitWidth: contentRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Theme.space2

            // Applets de l'îlot gauche (registre bar_applets.json).
            AppletRow {
                ile: "haut:debut"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
