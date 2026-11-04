import QtQuick

// ────────────────────────────────────────────────────────────────────────────
// BARRE DE CAPTURE (SUPER + SHIFT + S) — pastille verticale, bord gauche.
// ────────────────────────────────────────────────────────────────────────────
// Trois entrées : région, écran entier, enregistrement vidéo. La surface qui
// l'héberge (main.qml) est plein écran pour attraper le clic extérieur, mais la
// pastille, elle, ne prend pas la hauteur : elle est centrée et glisse depuis
// le bord gauche. Géométrie maquettée dans dev/mockups/shotbar_mock.html.
//
// L'enregistrement a besoin d'un choix (région / écran entier) que trois icônes
// ne peuvent pas porter : le bouton vidéo bascule la pastille sur une seconde
// page de deux entrées, et un chevron ramène à la première. Pendant qu'un
// enregistrement tourne, l'entrée vidéo devient « arrêter » (carré plein).
//
// Variante « icônes + libellés » (maquette B) : `barWidth: 188`, un libellé dans
// chaque entrée et la marge du bouton qui va avec — la variante A est retenue.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property int barWidth: 60
    readonly property int buttonSize: 44
    readonly property int pad: 8
    readonly property int gap: 6
    readonly property color surfaceColor: Qt.alpha(Theme.surface, 0.88)

    // Page courante et état de l'enregistrement (renseigné à l'ouverture de la
    // barre par un `pgrep -x wf-recorder` dans main.qml).
    property bool recordMode: false
    property bool recording: false

    signal regionRequested()
    signal fullRequested()
    signal recordMenuRequested()
    signal recordRegionRequested()
    signal recordFullRequested()
    signal recordStopRequested()
    signal backRequested()

    readonly property var entries: recordMode
        ? [
            { glyph: "selection",   action: "recordRegion",  record: true },
            { glyph: "screen-shot", action: "recordFull",    record: true },
            { glyph: "chevron-left", action: "back",         record: false, sep: true }
          ]
        : [
            { glyph: "selection",   action: "region", record: false },
            { glyph: "screen-shot", action: "full",   record: false },
            recording
                ? { glyph: "stop",   action: "recordStop", record: true, sep: true }
                : { glyph: "record", action: "recordMenu", record: true, sep: true }
          ]

    implicitWidth: barWidth
    implicitHeight: pill.height

    Rectangle {
        id: pill
        width: root.barWidth
        height: stack.implicitHeight + root.pad * 2
        radius: 22
        color: root.surfaceColor
        border.color: Qt.alpha(Theme.accent, 0.22)
        border.width: 1

        Column {
            id: stack
            anchors.top: parent.top
            anchors.topMargin: root.pad
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.gap

            Repeater {
                model: root.entries

                Column {
                    id: entry
                    required property var modelData
                    spacing: root.gap

                    Rectangle {
                        visible: entry.modelData.sep === true
                        width: root.buttonSize - 14
                        height: 1
                        x: 7
                        color: Qt.alpha(Theme.fg, 0.09)
                    }

                    Rectangle {
                        width: root.buttonSize
                        height: root.buttonSize
                        radius: 14
                        color: entryMouse.containsMouse
                            ? Qt.alpha(entry.modelData.record ? Theme.error : Theme.accent, 0.14)
                            : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            glyph: entry.modelData.glyph
                            size: 21
                            color: entry.modelData.record ? Theme.error : Theme.accent
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (entry.modelData.action) {
                                case "region":       root.regionRequested(); break
                                case "full":         root.fullRequested(); break
                                case "recordMenu":   root.recordMenuRequested(); break
                                case "recordRegion": root.recordRegionRequested(); break
                                case "recordFull":   root.recordFullRequested(); break
                                case "recordStop":   root.recordStopRequested(); break
                                case "back":         root.backRequested(); break
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
