import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
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

    // Double clic → la fenêtre de l'application.
    //
    // `activate()` seul ne suffit pas : un item publié avec `ItemIsMenu = true`
    // (Proton VPN) n'a aucun handler Activate, l'appel ne fait rien du tout. Le
    // choix est donc confié à `core/tray_apps.py` : fenêtre déjà ouverte → au
    // premier plan (`hl.dsp.focus`), sinon lancement de l'entrée .desktop, et
    // code 3 quand l'application n'a ni fenêtre ni entrée — on retombe alors sur
    // `activate()`, seule chose qui reste.
    Process {
        id: ouvreur
        property var cible: null
        onExited: code => {
            if (code === 3 && cible)
                cible.activate()
            cible = null
        }
    }

    function ouvrirFenetre(item) {
        if (!item)
            return
        if (trayMenu.opened)
            trayMenu.close()
        ouvreur.cible = item
        ouvreur.command = ["python3", Quickshell.shellPath("core/tray_apps.py"),
                           String(item.id || ""), String(item.title || "")]
        ouvreur.running = true
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
                            id: trayIconImg
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: trayDelegate.iconSource
                            sourceSize: Qt.size(16, 16)
                            smooth: true
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: trayIconImg
                            source: trayIconImg
                            saturation: -1.0
                            brightness: 0.15
                            contrast: 0.1
                            opacity: trayDelegate.hovered ? 1.0 : 0.82
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
                            // Deuxième clic : `ouvrirFenetre` met la fenêtre au
                            // premier plan ou lance l'application (tray_apps.py).
                            onDoubleClicked: mouse => {
                                if (mouse.button === Qt.LeftButton)
                                    root.ouvrirFenetre(trayDelegate.modelData)
                            }
                            onWheel: wheel => {
                                trayDelegate.modelData.scroll(wheel.angleDelta.y, false)
                            }
                        }
                    }
                }
    }
}
