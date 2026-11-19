import QtQuick
import "."

// Pôle 0 — Apparence & Thème (regroupe Apparence + Connexion/Greeter).
Column {
    id: hub
    property var root
    property var mainFlickable

    visible: root ? root.currentTab === 0 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: Object.assign(
        {},
        subApparence.sections || ({}),
        subConnexion.sections || ({})
    )

    readonly property var cibles: Object.assign(
        {},
        subApparence.cibles || ({}),
        subConnexion.cibles || ({})
    )

    OngletApparence {
        id: subApparence
        root: hub.root
        mainFlickable: hub.mainFlickable
        width: hub.width
    }

    OngletConnexion {
        id: subConnexion
        root: hub.root
        mainFlickable: hub.mainFlickable
        width: hub.width
    }
}
