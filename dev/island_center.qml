import QtQuick
import Quickshell
import Quickshell.Hyprland

// ════════════════════════════════════════════════════════════════════════════
// ÎLOT CENTRAL (island_center.qml)
// ════════════════════════════════════════════════════════════════════════════
// Ce fichier n'est plus qu'un conteneur : la rangée d'applets du centre, le
// bouton du panneau de réglages, l'attrapeur de clic extérieur, et les deux
// panneaux qui s'ouvrent sous lui.
//
// Les panneaux ont leur propre fichier depuis qu'ils ne dépendent plus de l'îlot :
//   • MediaPanneau.qml       — popup MPRIS (applet « musique »)
//   • CalendrierPanneau.qml  — grille du mois et Nextcloud (applet « calendrier »,
//                              widget « date »)
// Ils reçoivent `ancre` (cet îlot) et `ouvert`, et se placent eux-mêmes.
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: islandCenter
    implicitWidth: contentRow.implicitWidth + Theme.padH * 2
    implicitHeight: Theme.barHeight
    height: Theme.barHeight
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 1: POPUP GEOMETRY & SCREEN CLAMPING HELPERS
    // ────────────────────────────────────────────────────────────────────────
    // Gardés ici parce que les panneaux reçoivent cet îlot comme `ancre` : ils
    // ne connaissent ni la fenêtre de la barre, ni les marges de l'écran.
    function popupY(item) {
        return islandCenter.height + 6 - islandCenter.mapFromItem(item, 0, 0).y
    }

    function clampPopupX(item, relX, popupW) {
        const win = islandCenter.QsWindow.window
        if (!win) return relX
        const ix = win.contentItem.mapFromItem(item, 0, 0).x
        const absX = Math.max(8, Math.min(win.width - popupW - 8, ix + relX))
        return absX - ix
    }

    readonly property bool calendarOpen: Theme.activePopup === "calendar"
    readonly property bool mediaOpen: Theme.activePopup === "media"

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 6: MAIN ISLAND BAR UI
    // ────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: background
        anchors.fill: parent
        color: Theme.barMerged ? "transparent" : Theme.barBg
        radius: Theme.globalRadius
        border.color: islandCenter.calendarOpen ? Theme.accentMuted : Theme.accent
        border.width: Theme.barMerged ? 0 : (Theme.barBorder ? 1 : 0)
        clip: true

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }


        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 0
            // La date et le titre du morceau ne sont plus ici : ce sont deux
            // applets (« calendrier » et « musique »), posés dans cette rangée
            // par AppletRow. Le survol n'a donc plus rien à déplier.

            // ────────────────────────────────────────────────────────────────
            // Applets de l'îlot central, après l'heure (registre
            // bar_applets.json) : « jeu. 5 nov. », puis le morceau s'il joue.
            // La rangée du centre n'a pas d'espacement propre (chaque enfant
            // gère sa marge) : d'où l'écart posé ici.
            Item { width: 10; height: 1 }
            AppletRow {
                ile: "haut:milieu"
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: 4; height: 1 }

            // SUB-SECTION 6.3: SYSTEM CONFIGURATION PANEL GEAR BUTTON
            // ────────────────────────────────────────────────────────────────
            Row {
                visible: Theme.showConfigButton
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Item { width: 10; height: 1 }

                Rectangle {
                    width: 1
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceVariant
                }

                Item { width: 10; height: 1 }

                Rectangle {
                    id: gearBtn
                    width: 24
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.globalRadius
                    color: Theme.configPanelVisible
                        ? Theme.accent
                        : (gearMa.containsMouse ? Theme.surfaceVariant : "transparent")

                    Icon {
                        anchors.centerIn: parent
                        glyph: "cog"
                        size: Theme.iconMd
                        color: Theme.configPanelVisible ? Theme.bg : Theme.fg
                        opacityLevel: 1
                    }

                    MouseArea {
                        id: gearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.configPanelVisible = !Theme.configPanelVisible
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // Le clic est porté par l'heure elle-même (voir 6.1) : un attrapeur plein
        // îlot aurait recouvert les applets posés dans la même rangée.
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 7: HYPRLAND OUTSIDE CLICK / FOCUS GRAB
    // ────────────────────────────────────────────────────────────────────────
    // Armer l'attrapeur trop tôt le fait relâcher par Hyprland avant que la
    // surface du panneau ne soit mappée : le popup se referme dans la seconde.
    // Même remède que dans Applet.qml — on laisse le compositeur finir le map.
    property bool grabPret: false
    Timer {
        interval: 180
        running: islandCenter.calendarOpen || islandCenter.mediaOpen
        onTriggered: islandCenter.grabPret = true
        onRunningChanged: if (!running) islandCenter.grabPret = false
    }

    HyprlandFocusGrab {
        active: (islandCenter.calendarOpen || islandCenter.mediaOpen) && islandCenter.grabPret
        windows: [calendarPopup.surface, mediaPopup.surface, islandCenter.QsWindow.window]
        onCleared: {
            if (Theme.activePopup === "calendar" || Theme.activePopup === "media") {
                Theme.activePopup = ""
            }
        }
    }


    // ────────────────────────────────────────────────────────────────────────
    // SECTION 8: PANNEAUX
    // ────────────────────────────────────────────────────────────────────────
    MediaPanneau {
        id: mediaPopup
        ancre: islandCenter
        ouvert: islandCenter.mediaOpen
    }

    CalendrierPanneau {
        id: calendarPopup
        ancre: islandCenter
        ouvert: islandCenter.calendarOpen
    }
}
