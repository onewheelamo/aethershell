import QtQuick

// ────────────────────────────────────────────────────────────────────────────
// BARRE DE CAPTURE (SUPER + SHIFT + S) — pastille verticale, bord gauche.
// ────────────────────────────────────────────────────────────────────────────
// Quatre entrées sur une seule page, en deux paires : la photo (accent) puis
// la vidéo (rouge), séparées par un trait. Chaque paire va du plus petit au plus
// grand — région puis écran entier — pour que le regard n'ait qu'un axe à suivre
// (« la même chose, en plus large »).
//
//   région photo  sélection pointillée      vidéo région  caméra dans un cadre
//   écran photo   moniteur + cadre          vidéo écran   caméra
//
// La version précédente cachait le choix vidéo derrière une seconde page (le
// bouton vidéo basculait la pastille) : le chemin existait mais ne se voyait pas,
// et « la vidéo ne marche pas » voulait dire « je n'ai jamais atteint l'entrée ».
// Quatre icônes tiennent dans la même pastille : plus de page, plus de chevron.
//
// Pendant un enregistrement, les deux entrées vidéo laissent la place à un seul
// carré « arrêter » : il n'y a rien d'autre à faire tant que ça tourne.
//
// La surface qui héberge la pastille (main.qml) est plein écran pour attraper le
// clic extérieur ; la pastille, elle, ne prend pas la hauteur : elle est centrée
// et glisse depuis le bord gauche. Géométrie maquettée dans
// dev/mockups/shotbar_mock.html.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property int barWidth: 60
    readonly property int buttonSize: 44
    readonly property int pad: 8
    readonly property int gap: 6
    readonly property color surfaceColor: Qt.alpha(Theme.surface, 0.88)

    // Renseigné à l'ouverture de la barre par un `pgrep -x wf-recorder` dans
    // main.qml : un enregistrement peut tourner depuis une ouverture précédente.
    property bool recording: false

    signal regionRequested()
    signal fullRequested()
    signal recordRegionRequested()
    signal recordFullRequested()
    signal recordStopRequested()

    readonly property var entries: recording
        ? [
            { glyph: "selection",   action: "region",       video: false },
            { glyph: "screen-shot", action: "full",         video: false },
            { glyph: "stop",        action: "recordStop",   video: true, sep: true }
          ]
        : [
            { glyph: "selection",   action: "region",       video: false },
            { glyph: "screen-shot", action: "full",         video: false },
            { glyph: "video-region", action: "recordRegion", video: true, sep: true },
            { glyph: "video-full",  action: "recordFull",   video: true }
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
                            ? Qt.alpha(entry.modelData.video ? Theme.error : Theme.accent, 0.14)
                            : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            glyph: entry.modelData.glyph
                            size: 21
                            color: entry.modelData.video ? Theme.error : Theme.accent
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
                                case "recordRegion": root.recordRegionRequested(); break
                                case "recordFull":   root.recordFullRequested(); break
                                case "recordStop":   root.recordStopRequested(); break
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
