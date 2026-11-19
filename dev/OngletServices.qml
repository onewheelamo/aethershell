import QtQuick
import "."

// Pôle 4 — Services & Comptes (regroupe Données & Comptes + Apps & Alertes).
Column {
    id: hub
    property var root
    property var mainFlickable
    property var ncEtatProc

    visible: root ? root.currentTab === 4 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: Object.assign(
        {},
        subDonnees.sections || ({}),
        subApps.sections || ({})
    )

    readonly property var cibles: Object.assign(
        {},
        subDonnees.cibles || ({}),
        subApps.cibles || ({})
    )

    OngletDonnees {
        id: subDonnees
        root: hub.root
        mainFlickable: hub.mainFlickable
        ncEtatProc: hub.ncEtatProc
        width: hub.width
    }

    OngletApps {
        id: subApps
        root: hub.root
        mainFlickable: hub.mainFlickable
        width: hub.width
    }
}
