import QtQuick
import Quickshell
import Quickshell.Wayland

// ────────────────────────────────────────────────────────────────────────────
// MENU CONTEXTUEL DU SYSTRAY — rendu maison, aux tokens du rice.
//
// `SystemTrayItem.display()` affiche le menu dans une fenêtre interne de
// Quickshell : fond blanc opaque, police par défaut, aucun arrondi, aucun flou —
// rien de commun avec la barre et le panneau. On rend donc le DBusMenu nous-mêmes
// à partir de `item.menu` (QsMenuHandle) via QsMenuOpener. Chaque entrée est
// elle-même un QsMenuHandle (`QsMenuEntry` en dérive) : un sous-menu s'affiche en
// forage dans la même surface, avec une ligne de retour.
//
// Deux fenêtres, dans cet ordre : un attrapeur plein écran transparent qui referme
// au clic (c'est l'équivalent du grab d'un popup, absent de cette version de
// Quickshell), puis la carte du menu, seule à porter le namespace `shell-tray-menu`
// donc seule à recevoir le flou de la règle de couche Hyprland.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var trayItem: null
    property real anchorX: 0
    property real anchorY: 0
    property bool opened: false

    // Niveau de sous-menu courant. L'entrée garde son opener vivant : le modèle
    // détruirait l'entrée qu'on est en train d'afficher sinon.
    property var subEntry: null
    property string subReturnLabel: ""

    function open(item, x, y) {
        trayItem = item
        subEntry = null
        subReturnLabel = ""
        anchorX = x
        anchorY = y
        opened = true
    }

    function back() {
        root.subEntry = null
        root.subReturnLabel = ""
    }

    function close() {
        opened = false
        subEntry = null
        subReturnLabel = ""
    }

    function activate(entry) {
        if (!entry || !entry.enabled)
            return
        if (entry.hasChildren) {
            subReturnLabel = String(entry.text || "")
            subEntry = entry
            return
        }
        // `triggered()` est le seul point d'entrée exposé au QML ; il envoie
        // l'événement `clicked` du DBusMenu. Les méthodes de `DBusMenuItem`
        // (`sendTriggered`, `sendOpened`, `sendClosed`) ne sont pas visibles
        // depuis QML — vérifié à l'exécution : `typeof` vaut « undefined ».
        // Ce n'était donc pas le défaut : voir l'attrapeur de clic, qui passait
        // au-dessus de la carte et avalait tous les clics.
        entry.triggered()
        close()
    }

    QsMenuOpener {
        id: mainOpener
        menu: root.trayItem ? root.trayItem.menu : null
    }

    QsMenuOpener {
        id: subOpener
        menu: root.subEntry
    }

    readonly property var currentEntries: root.subEntry ? subOpener.children : mainOpener.children
    // 240 : « The Binding of Isaac: Rebirth » tient dans le menu Steam.
    readonly property int rowWidth: 240

    // ────────────────────────────────────────────────────────────────────────
    // 1. Attrapeur de clic : transparent, plein écran, sous la carte du menu.
    // ────────────────────────────────────────────────────────────────────────
    PanelWindow {
        id: catcher
        visible: root.opened
        screen: topBarWindow.screen
        anchors { top: true; bottom: true; left: true; right: true }
        // L'attrapeur commence SOUS la barre : la barre reste cliquable, donc un
        // clic droit sur une autre icône ouvre son menu et remplace celui-ci au
        // lieu d'exiger un clic dans le vide d'abord.
        margins.top: Theme.barHeight + 12
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        // **Top, pas Overlay** : deux surfaces de couche identique sont empilées
        // dans un ordre que le compositeur décide (mesuré ici : l'attrapeur
        // passait au-dessus de la carte), et il avalait alors tous les clics —
        // le menu se refermait sans qu'aucune entrée ne reçoive le sien. Une
        // couche en dessous règle le problème sans dépendre de l'ordre de
        // création. L'attrapeur reste au-dessus des fenêtres, ce qui suffit.
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Namespace distinct : celui-ci ne doit PAS être dans la liste de flou.
        WlrLayershell.namespace: "shell-tray-menu-catcher"

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 2. La carte du menu.
    // ────────────────────────────────────────────────────────────────────────
    PanelWindow {
        id: menuWindow
        visible: root.opened
        screen: topBarWindow.screen

        anchors { top: true; left: true }
        margins.top: root.anchorY
        margins.left: Math.max(4, Math.min(root.anchorX,
                                          (menuWindow.screen ? menuWindow.screen.width : 1920)
                                          - card.implicitWidth - 8))
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shell-tray-menu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: card
            anchors.fill: parent
            implicitWidth: root.rowWidth + Theme.space2 * 2
            implicitHeight: (rows.implicitHeight + Theme.space2 * 2)
            radius: Theme.globalRadius
            color: Qt.alpha(Theme.surface, 0.92)
            border.width: 1
            border.color: Qt.alpha(Theme.accent, 0.16)

            Column {
                id: rows
                anchors.fill: parent
                anchors.margins: Theme.space2
                spacing: 0

                // Ligne de retour du sous-menu
                Item {
                    visible: root.subEntry !== null
                    width: rows.width
                    height: 22
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.space2
                        width: parent.width - Theme.space2 * 2
                        text: "‹  " + root.subReturnLabel
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.back()
                    }
                }

                Repeater {
                    model: root.currentEntries

                    Item {
                        id: entryRow
                        required property var modelData
                        width: rows.width
                        height: modelData.isSeparator ? 9 : 26

                        Rectangle {
                            visible: entryRow.modelData.isSeparator
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.alpha(Theme.fg, 0.09)
                        }

                        Rectangle {
                            visible: !entryRow.modelData.isSeparator && rowMa.containsMouse
                                     && entryRow.modelData.enabled
                            anchors.fill: parent
                            radius: Theme.globalRadius
                            color: Qt.alpha(Theme.surfaceVariant, 0.85)
                        }

                        Text {
                            visible: !entryRow.modelData.isSeparator
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space2
                            width: parent.width - Theme.space2 * 2 - (entryRow.modelData.hasChildren ? 14 : 0)
                            text: {
                                const check = entryRow.modelData.checkState
                                const mark = (check === Qt.Checked) ? "✓  "
                                           : (check === Qt.PartiallyChecked) ? "–  " : ""
                                return mark + String(entryRow.modelData.text || "")
                            }
                            color: entryRow.modelData.enabled ? Theme.fg : Qt.alpha(Theme.fg, 0.38)
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: !entryRow.modelData.isSeparator && entryRow.modelData.hasChildren
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space1
                            text: "›"
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textXs
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !entryRow.modelData.isSeparator
                            cursorShape: entryRow.modelData.enabled ? Qt.PointingHandCursor
                                                                    : Qt.ArrowCursor
                            onClicked: root.activate(entryRow.modelData)
                        }
                    }
                }
            }
        }
    }
}
