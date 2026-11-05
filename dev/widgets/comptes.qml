import QtQuick
// Le dossier parent porte les singletons (Theme, Icon) : sans cet import, la
// couleur du séparateur lève « Theme is not defined » à la création du widget.
import ".."

// WIDGET DE COMPTES FUSIONNÉ — les services empilés dans une seule surface.
//
// Les widgets de compte partagent déjà un composant (llm.qml) : ce fichier ne
// refait aucun rendu, il instancie ce composant une fois par service et les
// empile. La hauteur suit donc le nombre de services, et ajouter un fournisseur
// se fait dans `options.services` — sans toucher au QML.
//
// Chaque bloc garde son propre service Python et sa propre cadence : trois
// processus indépendants plutôt qu'un agrégateur, pour qu'un fournisseur lent ou
// en panne n'attarde pas les autres, et pour qu'aucun code de lecture ne soit
// dupliqué ici.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property var services: {
        const v = options && options.services
        if (v && v.length !== undefined) {
            const liste = []
            for (let i = 0; i < v.length; i++) {
                const s = String(v[i] || "").trim()
                if (s !== "" && liste.indexOf(s) < 0) liste.push(s)
            }
            if (liste.length > 0) return liste
        }
        return ["deepseek", "ollama", "antigravity"]
    }

    // Même échelle que le composant de bloc : la respiration s'y accorde, sinon
    // un texte agrandi se retrouve collé à son séparateur.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 0.85
    }
    readonly property int respiration: Math.round(13 * root.echelle)
    // Retrait latéral du filet : il court sur toute la largeur du widget, mais
    // s'arrête à une respiration des bords — un trait qui touche le bord se lit
    // comme une bordure, pas comme une séparation.
    readonly property int margeFilet: Math.round(6 * root.echelle)

    // Largeur de chaque bloc, relevée au chargement : les séparateurs prennent
    // la plus grande, sinon chaque trait s'arrête à la largeur de son propre
    // bloc et la pile paraît décousue.
    property var largeurs: []
    readonly property real largeurCommun: {
        let m = 0
        for (let i = 0; i < largeurs.length; i++) m = Math.max(m, Number(largeurs[i]) || 0)
        return m
    }
    function noterLargeur(i, w) {
        const l = largeurs.slice()
        l[i] = w
        largeurs = l
    }

    implicitWidth: pile.implicitWidth
    implicitHeight: pile.implicitHeight

    Column {
        id: pile
        spacing: root.respiration

        Repeater {
            model: root.services

            delegate: Column {
                id: bloc
                property string service: String(modelData || "")
                spacing: root.respiration

                // Séparateur : une ligne fine, à la largeur du bloc, très
                // discrète — elle coupe sans transformer le widget en carte. La
                // respiration de la colonne joue au-dessus et en dessous.
                Item {
                    visible: index > 0
                    width: Math.max(1, root.largeurCommun)
                    height: 1

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: root.margeFilet
                        anchors.rightMargin: root.margeFilet
                        color: Qt.alpha(Theme.fg, 0.13)
                    }
                }

                Loader {
                    id: corps
                    source: "llm.qml"
                    onLoaded: {
                        if (!item) return
                        item.options = {
                            provider: bloc.service,
                            // L'en-tête ne sert que dans une pile : un widget seul
                            // n'a pas besoin de se nommer.
                            entete: true,
                            text_scale: root.options ? root.options.text_scale : undefined,
                            refresh_min: root.options ? root.options.refresh_min : undefined
                        }
                        item.widgetId = ""
                        root.noterLargeur(index, item.implicitWidth)
                    }
                }
            }
        }
    }
}
