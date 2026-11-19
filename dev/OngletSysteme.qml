import QtQuick
import "."

// Pôle 3 — Système (regroupe Écrans & Système + Clavier & Binds).
Column {
    id: hub
    property var root
    property var mainFlickable

    visible: root ? root.currentTab === 3 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: Object.assign(
        {},
        subEcrans.sections || ({}),
        subClavier.sections || ({})
    )

    readonly property var cibles: Object.assign(
        {},
        subEcrans.cibles || ({}),
        subClavier.cibles || ({})
    )

    OngletEcrans {
        id: subEcrans
        root: hub.root
        mainFlickable: hub.mainFlickable
        width: hub.width
    }

    OngletClavier {
        id: subClavier
        root: hub.root
        mainFlickable: hub.mainFlickable
        width: hub.width
    }
}
