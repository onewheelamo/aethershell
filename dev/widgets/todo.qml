import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io

// TÂCHES — les cases à cocher des fichiers Markdown de l'utilisateur.
//
// Même source que l'applet et le popup : `core/todo_applet.py`. Le widget compte
// les items ouverts et montre les premiers ; une demande déposée par une coche
// passe en couleur d'accent, parce que c'est elle qui attend une action.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    property var etat: ({})

    // Options du widget (widgets.json, écrites par le panneau) : quels fichiers
    // suivis, combien de lignes d'items, et si les items cochés comptent. Une
    // liste de fichiers vide veut dire « tous » — c'est le défaut historique,
    // conservé pour qu'un widget sans options se comporte comme avant.
    readonly property var fichiersChoisis: {
        const brut = root.options && root.options.fichiers
        const liste = Array.isArray(brut) ? brut
                    : (typeof brut === "string" && brut !== "" ? brut.split(",") : [])
        const sortie = []
        for (let i = 0; i < liste.length; ++i) {
            const nom = String(liste[i]).trim()
            if (nom !== "") sortie.push(nom)
        }
        return sortie
    }
    readonly property bool afficherFaits: {
        // La valeur vient d'un `widget_set` par ligne de commande : elle peut
        // être le booléen JSON ou la chaîne « true ». `Boolean("false")` vaut
        // vrai, donc on compare explicitement.
        const v = root.options && root.options.afficher_faits
        return v === true || v === "true" || v === 1 || v === "1"
    }
    readonly property int lignesAffichees: {
        const v = Number(root.options && root.options.lignes)
        return (v >= 1 && v <= 6) ? Math.round(v) : 3
    }
    // Le filtre s'applique aussi au compteur : annoncer « 11 tâches » puis n'en
    // montrer que trois d'un seul fichier se lirait comme un bug.
    readonly property var itemsAffiches: {
        const choix = root.fichiersChoisis
        return (root.etat.items || []).filter(function (i) {
            const nom = String(i.nom_fichier || "")
            if (choix.length > 0 && choix.indexOf(nom) < 0) return false
            if (!root.afficherFaits && i.fait && !i.demande) return false
            return true
        })
    }
    readonly property int compteOuverts: {
        return root.itemsAffiches.filter(function (i) { return !i.fait || i.demande }).length
    }
    readonly property var ouverts: itemsAffiches.slice(0, root.lignesAffichees)

    function rafraichir() {
        proc.running = false
        proc.running = true
    }

    Component.onCompleted: rafraichir()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.rafraichir()
    }

    Process {
        id: proc
        // Le widget voit **tous** les fichiers ; l'applet n'en montre qu'un.
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"), "etat",
                  "--options={\"fichier\": \"*\"}"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    root.etat = (d.detail && d.detail.todo) ? d.detail.todo : d
                } catch (e) {
                    root.etat = ({})
                }
            }
        }
    }

    implicitWidth: Math.round(246 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(5 * echelle)

        Row {
            width: parent.width
            spacing: Math.round(5 * echelle)

            Rectangle {
                width: Math.round(10 * echelle)
                height: width
                radius: Math.round(2 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: 1
                border.color: (root.etat.demandes || []).length > 0
                              ? Theme.accent : Qt.alpha(Theme.fg, 0.45)

                Icon {
                    anchors.centerIn: parent
                    visible: (root.etat.demandes || []).length > 0
                    glyph: "check"
                    size: Math.round(7 * echelle)
                    color: Theme.accent
                }
            }

            Text {
                width: parent.width - Math.round(60 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: root.compteOuverts + (root.compteOuverts > 1 ? " tâches" : " tâche")
                color: Theme.fg
                font.pixelSize: Math.round(11 * echelle)
                elide: Text.ElideRight
            }

            Text {
                width: Math.round(52 * echelle)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: (root.etat.demandes || []).length > 0
                      ? root.etat.demandes.length + " att." : ""
                color: Qt.alpha(Theme.accent, 0.9)
                font.pixelSize: Math.round(9 * echelle)
            }
        }

        Repeater {
            model: root.ouverts

            Row {
                required property var modelData
                width: colonne.width
                spacing: Math.round(4 * echelle)

                Rectangle {
                    width: Math.round(4 * echelle)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.demande ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                }

                // Plusieurs fichiers alimentent ce widget : la provenance évite de
                // confondre deux items homonymes. Masquée quand un seul fichier est
                // suivi — le nom n'apprendrait alors rien.
                Text {
                    width: Math.round(34 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    // La provenance n'a de sens que si plusieurs fichiers sont
                    // affichés : le choix du widget prime sur la liste suivie.
                    visible: {
                        const suivis = root.fichiersChoisis.length > 0
                                       ? root.fichiersChoisis.length
                                       : (root.etat.fichiers || []).length
                        return suivis > 1
                    }
                    text: String(modelData.nom_fichier || "")
                    color: Qt.alpha(Theme.fg, 0.35)
                    font.pixelSize: Math.round(8.5 * echelle)
                    elide: Text.ElideRight
                }

                // Plusieurs fichiers alimentent ce widget : la provenance est
                // dans le texte, sinon deux items homonymes deviennent ambigus.
                Text {
                    width: parent.width - Math.round(42 * echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData.titre)
                    color: modelData.demande ? Qt.alpha(Theme.accent, 0.95)
                                             : Qt.alpha(Theme.fg, 0.75)
                    font.pixelSize: Math.round(9.5 * echelle)
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            visible: root.ouverts.length === 0
            text: root.etat.fichiers && root.etat.fichiers.length > 0
                  ? "aucune tâche ouverte" : "aucun fichier surveillé"
            color: Qt.alpha(Theme.fg, 0.4)
            font.pixelSize: Math.round(9.5 * echelle)
        }
    }
}
