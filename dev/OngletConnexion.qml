import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Connexion » du panneau de configuration, sorti de config_panel.qml.
// Le panneau le charge par URL et ne l'instancie qu'a l'ouverture de
// l'onglet : le corps n'a pas bouge d'un caractere, hors indentation.
//
// `root` et `mainFlickable` viennent du panneau sous les noms qu'ils avaient
// deja dans ce corps, donc les appels a la racine sont restes intacts.
// `sections` et `cibles` sont remplies apres la decoupe (voir decouper.py) :
// le panneau ne peut plus nommer ces ids, il les demande ici.
Column {
    id: bloc
    property var root
    property var mainFlickable

    width: mainFlickable ? mainFlickable.width : 0

    readonly property var sections: ({
        "greeter_theme": secGreeter
    })

    readonly property var cibles: ({})
    spacing: 11

    CollapsibleSection {
        id: secGreeter
        objectName: "secGreeter"
        title: "Thème de l'écran de connexion (SDDM)"
        summary: root.greeterSelected !== "" ? root.greeterSelected : "thème par défaut"
        icon: "lock"
        expanded: root.sectionOpen("greeter_theme", true)
        onToggled: expanded => {
            root.setPanelSection("greeter_theme", expanded)
            if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("greeter_theme")
        }

        Loader {
            id: greeterTabLoader
            width: parent.width
            active: root.currentTab === 6
            source: "GreeterTab.qml"
            onLoaded: item.width = parent.width
        }
    }
}
