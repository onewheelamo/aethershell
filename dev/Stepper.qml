import QtQuick

// ═══════════════════════════════════════════════════════════════════════════════
// COMPOSANT STEPPER : CONTRÔLE NUMÉRIQUE INTERACTIF [ − ] Valeur [ + ]
// ═══════════════════════════════════════════════════════════════════════════════
// Contrôle pas-à-pas pour le réglage fin des valeurs numériques du bureau.
// - Clics unitaires sur les boutons [ − ] et [ + ]
// - Défilement continu via la molette de souris (wheel) sur toute la surface
// - Auto-répétition rapide lors d'un appui prolongé (320 ms d'amorce, 70 ms de cadence)
// - Préservation des bindings d'expression QML (sans écrasement destructif)
// - Prise en charge des décimales, suffixes d'unités (ex: ' px') et formateurs personnalisés
Item {
    id: root

    // ─────────────────────────────────────────────────────────────────────────────
    // 1. Propriétés d'entrée & Dimensions
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

    width: 140
    height: 26
    implicitWidth: 140
    implicitHeight: 26

    // ─────────────────────────────────────────────────────────────────────────────
    // 2. Fonctions de calcul, clamping mathématique & émission d'événement
    // ─────────────────────────────────────────────────────────────────────────────
    function cleanVal(v) {
        const clamped = Math.max(root.minimumValue, Math.min(root.maximumValue, v))
        if (root.decimals > 0) {
            return parseFloat(clamped.toFixed(root.decimals))
        }
        return Math.round(clamped)
    }

    function stepUp() {
        const next = cleanVal(root.value + root.stepSize)
        if (next !== root.value) {
            const oldVal = root.value
            root.valueModified(next)
            // Met à jour en local uniquement si le parent n'a pas lié la valeur à une propriété externe
            if (root.value === oldVal) root.value = next
        }
    }

    function stepDown() {
        const next = cleanVal(root.value - root.stepSize)
        if (next !== root.value) {
            const oldVal = root.value
            root.valueModified(next)
            // Met à jour en local uniquement si le parent n'a pas lié la valeur à une propriété externe
            if (root.value === oldVal) root.value = next
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // 3. Minuteurs d'auto-répétition à l'appui maintenu
    // ─────────────────────────────────────────────────────────────────────────────
    Timer {
        id: repeatTimer
        interval: 70
        repeat: true
        property string direction: ""
        onTriggered: {
            if (direction === "up") {
                if (root.value >= root.maximumValue) stop()
                else root.stepUp()
            } else if (direction === "down") {
                if (root.value <= root.minimumValue) stop()
                else root.stepDown()
            }
        }
    }

    Timer {
        id: startRepeatTimer
        interval: 320
        repeat: false
        property string direction: ""
        onTriggered: {
            repeatTimer.direction = direction
            repeatTimer.start()
        }
    }

    function stopRepeat() {
        startRepeatTimer.stop()
        repeatTimer.stop()
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // 4. Interface graphique & Contrôles utilisateur
    // ─────────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.globalRadius
        color: Theme.surfaceVariant
        border.color: (wholeMa.containsMouse || decMa.containsMouse || incMa.containsMouse) ? Theme.accent : Theme.surfaceVariant
        border.width: 1

        Behavior on border.color { ColorAnimation { duration: 120 } }

        Row {
            anchors.fill: parent

            // 4.1 Bouton Décrémenter [-]
            Rectangle {
                id: decBtn
                width: root.height
                height: root.height
                radius: Theme.globalRadius
                color: decMa.pressed
                    ? Qt.alpha(Theme.accent, 0.25)
                    : (decMa.containsMouse ? Qt.alpha(Theme.accent, 0.15) : "transparent")
                opacity: root.value <= root.minimumValue ? 0.35 : 1.0

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.accent
                    font.pixelSize: Theme.textLg
                    font.bold: true
                }

                MouseArea {
                    id: decMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.value > root.minimumValue ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: {
                        if (root.value > root.minimumValue) {
                            root.stepDown()
                            startRepeatTimer.direction = "down"
                            startRepeatTimer.start()
                        }
                    }
                    onReleased: root.stopRepeat()
                    onCanceled: root.stopRepeat()
                    onWheel: wheel => {
                        if (wheel.angleDelta.y > 0) root.stepUp()
                        else if (wheel.angleDelta.y < 0) root.stepDown()
                    }
                }
            }

            // 4.2 Affichage central de la valeur
            Item {
                width: parent.width - (root.height * 2)
                height: parent.height

                Text {
                    id: valueText
                    anchors.centerIn: parent
                    text: {
                        if (root.textFormatter && typeof root.textFormatter === "function") {
                            return String(root.textFormatter(root.value))
                        }
                        const vStr = root.decimals > 0 ? root.value.toFixed(root.decimals) : String(Math.round(root.value))
                        return root.prefix + vStr + root.suffix
                    }
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }
            }

            // 4.3 Bouton Incrémenter [+]
            Rectangle {
                id: incBtn
                width: root.height
                height: root.height
                radius: Theme.globalRadius
                color: incMa.pressed
                    ? Qt.alpha(Theme.accent, 0.25)
                    : (incMa.containsMouse ? Qt.alpha(Theme.accent, 0.15) : "transparent")
                opacity: root.value >= root.maximumValue ? 0.35 : 1.0

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.accent
                    font.pixelSize: Theme.textLg
                    font.bold: true
                }

                MouseArea {
                    id: incMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.value < root.maximumValue ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: {
                        if (root.value < root.maximumValue) {
                            root.stepUp()
                            startRepeatTimer.direction = "up"
                            startRepeatTimer.start()
                        }
                    }
                    onReleased: root.stopRepeat()
                    onCanceled: root.stopRepeat()
                    onWheel: wheel => {
                        if (wheel.angleDelta.y > 0) root.stepUp()
                        else if (wheel.angleDelta.y < 0) root.stepDown()
                    }
                }
            }
        }

        // 4.4 Zone globale de défilement molette (wheel)
        MouseArea {
            id: wholeMa
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) root.stepUp()
                else if (wheel.angleDelta.y < 0) root.stepDown()
            }
        }
    }
}
