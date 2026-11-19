import QtQuick
import "."

// Pôle 1 — Barre & Îlot (unifié, avec mise en contexte selon Theme.barStyle).
Column {
    id: hub
    property var root
    property var mainFlickable
    property var disquesListeProc

    visible: root ? root.currentTab === 1 : false
    width: mainFlickable ? mainFlickable.width : 0
    spacing: 12

    readonly property bool estIlot: Theme.barStyle === "island"

    readonly property var sections: Object.assign(
        {},
        subIlot.sections || ({}),
        subBarres.sections || ({})
    )

    readonly property var cibles: Object.assign(
        {},
        subIlot.cibles || ({}),
        subBarres.cibles || ({})
    )

    // Bandeau contextuel : indique le mode actif et permet de basculer ici.
    Rectangle {
        width: hub.width
        height: 44
        radius: Theme.globalRadius
        color: Qt.alpha(Theme.accent, 0.10)
        border.color: Qt.alpha(Theme.accent, 0.35)
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "widgets"
                size: Theme.iconSm
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(120, parent.width - segMode.width - 42)
                text: hub.estIlot
                    ? "Mode actif : Îlot dynamique (les options « Barre classique » ci-dessous sont atténuées)"
                    : "Mode actif : Barre classique (les options « Îlot dynamique » ci-dessous sont atténuées)"
                color: Theme.fg
                font.pixelSize: Theme.textXs
                elide: Text.ElideRight
            }

            ConfigSegmented {
                id: segMode
                anchors.verticalCenter: parent.verticalCenter
                choices: [
                    { code: "island",  label: "Îlot dynamique" },
                    { code: "classic", label: "Barre classique" }
                ]
                currentCode: Theme.barStyle
                onSelected: code => {
                    if (hub.root) hub.root.runConfigCmd(["style", "bar_style", code])
                }
            }
        }
    }

    Item {
        width: hub.width
        implicitHeight: subIlot.implicitHeight
        opacity: hub.estIlot ? 1.0 : 0.48
        Behavior on opacity { NumberAnimation { duration: 160 } }

        OngletIlot {
            id: subIlot
            root: hub.root
            mainFlickable: hub.mainFlickable
            width: parent.width
        }
    }

    Item {
        width: hub.width
        implicitHeight: subBarres.implicitHeight
        opacity: !hub.estIlot ? 1.0 : 0.58
        Behavior on opacity { NumberAnimation { duration: 160 } }

        OngletBarres {
            id: subBarres
            root: hub.root
            mainFlickable: hub.mainFlickable
            disquesListeProc: hub.disquesListeProc
            width: parent.width
        }
    }
}
