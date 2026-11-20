import QtQuick
import "."

// Hub générique regroupant deux sous-onglets verticaux dans un pôle du panneau.
Column {
    id: hub
    property var root
    property var mainFlickable
    property int tabIndex: 0
    property string sourceA: ""
    property string sourceB: ""
    property var propsA: ({})
    property var propsB: ({})

    visible: root ? root.currentTab === hub.tabIndex : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property var sections: Object.assign(
        {},
        (loaderA.item && loaderA.item.sections) || ({}),
        (loaderB.item && loaderB.item.sections) || ({})
    )

    readonly property var cibles: Object.assign(
        {},
        (loaderA.item && loaderA.item.cibles) || ({}),
        (loaderB.item && loaderB.item.cibles) || ({})
    )

    Loader {
        id: loaderA
        width: hub.width
        onLoaded: if (item) item.width = Qt.binding(function() { return hub.width })
        Component.onCompleted: {
            if (hub.sourceA !== "") {
                setSource(hub.sourceA, Object.assign({ root: hub.root, mainFlickable: hub.mainFlickable }, hub.propsA || ({})))
            }
        }
    }

    Loader {
        id: loaderB
        width: hub.width
        onLoaded: if (item) item.width = Qt.binding(function() { return hub.width })
        Component.onCompleted: {
            if (hub.sourceB !== "") {
                setSource(hub.sourceB, Object.assign({ root: hub.root, mainFlickable: hub.mainFlickable }, hub.propsB || ({})))
            }
        }
    }
}
