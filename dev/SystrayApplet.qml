import QtQuick
import "."
import Quickshell
import Quickshell.Services.SystemTray

// APPLET SYSTRAY — les icônes des applications en arrière-plan.
//
// Composant QML : la source est le modèle `SystemTray.items` de Quickshell, pas
// un script. Il emporte son menu maison (TrayMenu.qml) et sa façon de calculer la
// position du menu à partir de la fenêtre de la barre — c'est la seule chose qui
// le rattachait à l'îlot.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0
    // Barre de côté : les icônes s'empilent au lieu de s'aligner. `Applet.qml`
    // pose la propriété.
    property bool verticale: false

    implicitWidth: rangee.implicitWidth
    implicitHeight: rangee.implicitHeight

    // Menu contextuel des items du systray, rendu maison.
    TrayMenu {
        id: trayMenu
    }

    // Un `Grid` plutôt qu'un `Row` : une seule colonne sur une barre latérale,
    // une seule rangée ailleurs. Les icônes doivent toutes rester visibles —
    // une colonne qui n'en montre qu'une serait inutilisable.
    Grid {
        id: rangee
        columns: root.verticale ? 1 : 64
        spacing: 2


    // Background Application Icons (Steam, ProtonVPN, etc.) via StatusNotifierItem
                Repeater {
                    model: SystemTray.items

                    Rectangle {
                        id: trayDelegate
                        required property var modelData

                        // Icône : celle de l'item, sauf correspondance déclarée dans
                        // core/tray_icons.json (par Id). Un item qui ne publie aucune
                        // image — IconPixmap vide, IconName vide — n'a pas de case du
                        // tout : c'est ce qui dessinait un pixmap illisible.
                        readonly property string itemIcon: Theme.trayIconFor(trayDelegate.modelData.id)
                        readonly property string iconSource: itemIcon !== ""
                            ? itemIcon
                            : (trayDelegate.modelData.icon ? String(trayDelegate.modelData.icon) : "")

                        width: 24
                        height: 24
                        radius: Theme.globalRadius
                        color: trayMa.containsMouse ? Theme.surfaceVariant : "transparent"
                        visible: iconSource !== ""

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: trayDelegate.iconSource
                            sourceSize: Qt.size(16, 16)
                            smooth: true
                        }

                        MouseArea {
                            id: trayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                const win = root.QsWindow.window
                                const pt = win ? win.contentItem.mapFromItem(trayDelegate, 0, trayDelegate.height) : Qt.point(0, 0)
                                if (mouse.button === Qt.RightButton || trayDelegate.modelData.onlyMenu) {
                                    if (trayDelegate.modelData.hasMenu && win) {
                                        // Pas `display()` : la fenêtre interne de Quickshell
                                        // rend un menu blanc sans nos tokens (TrayMenu.qml).
                                        // Même icône : referme. Autre icône : remplace le menu.
                                        if (trayMenu.opened && trayMenu.trayItem === trayDelegate.modelData)
                                            trayMenu.close()
                                        else
                                            trayMenu.open(trayDelegate.modelData, pt.x, pt.y)
                                    }
                                } else if (mouse.button === Qt.LeftButton) {
                                    if (trayMenu.opened)
                                        trayMenu.close()
                                    trayDelegate.modelData.activate()
                                } else if (mouse.button === Qt.MiddleButton) {
                                    trayDelegate.modelData.secondaryActivate()
                                }
                            }
                            onWheel: wheel => {
                                trayDelegate.modelData.scroll(wheel.angleDelta.y, false)
                            }
                        }
                    }
                }
    }
}
