import QtQuick

// ═══════════════════════════════════════════════════════════════════════════════
// COMPOSANT SLIDER : CURSEUR DE 1 PX
// ═══════════════════════════════════════════════════════════════════════════════
// Même API que Stepper.qml (value, minimumValue, maximumValue, stepSize,
// decimals, suffix, prefix, textFormatter, signal valueModified) pour que le
// remplacement d'un contrôle par l'autre soit mécanique dans config_panel.qml.
//
// Rendu : piste de 1 px (surfaceVariant) remplie en accent, poignée de 3 × 11 px
// qui passe à 5 × 13 au survol et pendant le glissement, valeur en chiffres
// tabulaires à droite. Aucun remplissage de fond : dans un tiroir de 420 px, un
// contrôle plein serait plus lourd que le réglage qu'il porte.
//
// La valeur n'est écrite dans le backend qu'au relâchement (et sur la molette),
// jamais à chaque pixel de glissement : `valueModified` déclenche un
// `config_manager.py` complet, on ne le lance pas soixante fois par seconde.
Item {
    id: root

    // ─────────────────────────────────────────────────────────────────────────────
    // 1. Propriétés d'entrée (miroir de Stepper)
    // ─────────────────────────────────────────────────────────────────────────────
    property real value: 0
    property real minimumValue: 0
    property real maximumValue: 100
    property real stepSize: 1
    property int decimals: 0
    property string suffix: ""
    property string prefix: ""
    property var textFormatter: null

    signal valueModified(real newValue)

    width: 150
    height: 26
    implicitWidth: 150
    implicitHeight: 26

    // Valeur affichée pendant un glissement, avant validation au relâchement.
    property real previewValue: value
    readonly property bool dragging: handleMa.pressed
    readonly property real shownValue: dragging ? previewValue : value
    readonly property real ratio: Math.max(0, Math.min(1,
        (shownValue - minimumValue) / Math.max(0.0001, maximumValue - minimumValue)))

    onValueChanged: if (!dragging) previewValue = value

    // ─────────────────────────────────────────────────────────────────────────────
    // 2. Calcul et validation
    // ─────────────────────────────────────────────────────────────────────────────
    function cleanVal(v) {
        const clamped = Math.max(root.minimumValue, Math.min(root.maximumValue, v))
        if (root.stepSize > 0) {
            const steps = Math.round((clamped - root.minimumValue) / root.stepSize)
            const snapped = root.minimumValue + steps * root.stepSize
            return root.decimals > 0 ? parseFloat(snapped.toFixed(root.decimals))
                                     : Math.round(snapped)
        }
        return root.decimals > 0 ? parseFloat(clamped.toFixed(root.decimals)) : Math.round(clamped)
    }

    // Émet la nouvelle valeur ; ne l'écrit en local que si le parent ne l'a pas
    // reprise (même précaution que Stepper, pour ne pas casser un binding).
    function commit(v) {
        const next = cleanVal(v)
        const old = root.value
        root.previewValue = next
        if (next !== old) {
            root.valueModified(next)
            if (root.value === old) root.value = next
        }
    }

    function valueFromX(x) {
        const r = Math.max(0, Math.min(1, x / Math.max(1, trackArea.width)))
        return root.minimumValue + r * (root.maximumValue - root.minimumValue)
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // 3. Interface : valeur, piste, poignée
    // ─────────────────────────────────────────────────────────────────────────────
    Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 54
        horizontalAlignment: Text.AlignRight
        text: {
            if (root.textFormatter && typeof root.textFormatter === "function") {
                return String(root.textFormatter(root.shownValue))
            }
            const vStr = root.decimals > 0 ? root.shownValue.toFixed(root.decimals)
                                           : String(Math.round(root.shownValue))
            return root.prefix + vStr + root.suffix
        }
        color: handleMa.containsMouse || root.dragging ? Theme.accent : Theme.fg
        font.pixelSize: Theme.textXs
        font.bold: true
        font.features: { "tnum": 1 }

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Item {
        id: trackArea
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: Theme.space2
        anchors.verticalCenter: parent.verticalCenter
        height: 20

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.18)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: trackArea.width * root.ratio
            height: 1
            color: Theme.accent
        }

        Rectangle {
            id: handle
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(trackArea.width - width,
                                    trackArea.width * root.ratio - width / 2))
            width: handleMa.containsMouse || root.dragging ? 5 : 3
            height: handleMa.containsMouse || root.dragging ? 13 : 11
            radius: 1
            color: Theme.accent

            Behavior on width { NumberAnimation { duration: 90 } }
            Behavior on height { NumberAnimation { duration: 90 } }
        }

        MouseArea {
            id: handleMa
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: mouse => root.previewValue = root.cleanVal(root.valueFromX(mouse.x))
            onPositionChanged: mouse => {
                if (pressed) root.previewValue = root.cleanVal(root.valueFromX(mouse.x))
            }
            onReleased: root.commit(root.previewValue)
            onCanceled: root.previewValue = root.value

            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) root.commit(root.value + root.stepSize)
                else if (wheel.angleDelta.y < 0) root.commit(root.value - root.stepSize)
            }
        }
    }
}
