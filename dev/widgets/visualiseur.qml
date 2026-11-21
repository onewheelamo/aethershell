import QtQuick
import ".."

// VISUALISEUR BUREAU — permet de détacher le visualiseur audio hors de la barre ou de l'îlot.
Item {
    id: root

    property var options: ({})
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    property string widgetId: ""

    implicitWidth: Math.round(280 * echelle)
    implicitHeight: Math.round(78 * echelle)

    Visualiseur {
        id: viz
        anchors.fill: parent
        anchors.margins: 8
        barre: ""
        autorise: true
        styleOverride: (options && options.viz_style) ? String(options.viz_style) : ""
    }

    Text {
        anchors.centerIn: parent
        visible: VisualiseurAudio.silence || VisualiseurAudio.etat !== "run"
        text: "Visualiseur audio · " + Theme.vizEffectiveStyle
        color: Qt.alpha(Theme.fg, 0.45)
        font.pixelSize: Math.round(Theme.textXs * root.echelle)
    }
}
