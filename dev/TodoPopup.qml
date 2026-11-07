import QtQuick
import Quickshell
import Quickshell.Io

// POPUP « TÂCHES » — les cases à cocher des fichiers Markdown de l'utilisateur.
//
// Source : `core/todo_applet.py`. Cocher n'est pas une décoration : l'applet
// écrit `- [x]` dans le fichier et dépose une demande que l'agent consomme. Le
// panneau le dit quand une demande attend encore — sinon on croit que la coche
// n'a rien fait.
Item {
    id: root

    property var options: ({})
    property bool ouvert: false
    property string widgetId: ""
    property var notifier: null
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        return (v >= 60 && v <= 160) ? v / 100 : 1.0
    }
    readonly property real corps: Theme.textXs * 1.15

    property var etat: ({})
    readonly property var items: root.etat.items || []
    readonly property var demandes: root.etat.demandes || []

    // Regroupement par fichier puis par section, dans l'ordre des fichiers.
    readonly property var groupes: {
        const out = []
        const l = root.items
        for (let i = 0; i < l.length; ++i) {
            const it = l[i]
            // Une tâche cochée qui attend encore l'agent reste affichée : c'est
            // ce qui montre la demande en cours et permet de la décocher.
            if (it.fait && !it.demande) continue
            let g = null
            for (let j = 0; j < out.length; ++j) {
                if (out[j].fichier === it.nom_fichier) { g = out[j]; break }
            }
            if (g === null) {
                g = { fichier: it.nom_fichier, sections: [] }
                out.push(g)
            }
            let s = null
            for (let k = 0; k < g.sections.length; ++k) {
                if (g.sections[k].titre === it.section) { s = g.sections[k]; break }
            }
            if (s === null) {
                s = { titre: it.section, items: [] }
                g.sections.push(s)
            }
            s.items.push(it)
        }
        return out
    }

    function charger() {
        proc.running = false
        proc.running = true
    }

    function basculer(item) {
        geste.identifiant = String(item.id || "")
        geste.action = item.fait ? "decocher" : "cocher"
        geste.running = false
        geste.running = true
    }

    Component.onCompleted: charger()
    onOuvertChanged: if (ouvert) charger()

    // L'agent travaille pendant que le panneau est ouvert : la liste doit suivre
    // (une demande consommée disparaît, une ligne « ✓ fait le … » s'ajoute).
    Timer {
        interval: 5000
        running: root.ouvert
        repeat: true
        onTriggered: root.charger()
    }

    Process {
        id: proc
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"), "etat"]
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

    Process {
        id: focusProc
        property string nom: ""
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"), "focus", focusProc.nom]
        onExited: { root.charger(); if (root.notifier) root.notifier() }
    }

    Process {
        id: geste
        property string identifiant: ""
        property string action: "cocher"
        command: ["python3", Quickshell.shellPath("core/todo_applet.py"),
                  geste.action, geste.identifiant]
        onExited: { root.charger(); if (root.notifier) root.notifier() }
    }

    implicitWidth: Math.round(336 * echelle)
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: Math.round(6 * echelle)

        Row {
            width: parent.width

            // Le fichier au focus : l'applet n'en montre qu'un. Le clic passe au
            // suivant — un seul fichier à la fois, mais pas un fichier imposé.
            Text {
                width: parent.width - Math.round(90 * echelle)
                text: "Tâches · " + String(root.etat.focus || "")
                color: survolTitre.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * echelle)
                elide: Text.ElideRight

                MouseArea {
                    id: survolTitre
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const noms = (root.etat.fichiers || []).map(function (f) { return f.nom })
                        if (noms.length < 2) return
                        const i = noms.indexOf(String(root.etat.focus || ""))
                        focusProc.nom = noms[(i + 1) % noms.length]
                        focusProc.running = false
                        focusProc.running = true
                    }
                }
            }

            Text {
                width: Math.round(90 * echelle)
                horizontalAlignment: Text.AlignRight
                text: root.etat.ouverts !== undefined
                      ? root.etat.ouverts + (root.etat.ouverts > 1 ? " ouvertes" : " ouverte")
                      : ""
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Math.round(root.corps * 0.8 * echelle)
            }
        }

        Text {
            width: parent.width
            visible: root.items.length === 0
            text: root.etat.fichiers && root.etat.fichiers.length > 0
                  ? "Aucune case à cocher dans les fichiers surveillés."
                  : "Aucun fichier surveillé."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Math.round(root.corps * 0.9 * echelle)
            wrapMode: Text.WordWrap
        }

        // ── un bloc par fichier ─────────────────────────────────────────────
        Repeater {
            model: root.groupes

            Column {
                id: blocFichier
                required property var modelData
                width: colonne.width
                spacing: Math.round(3 * echelle)

                Text {
                    width: parent.width
                    text: String(blocFichier.modelData.fichier).toUpperCase()
                    color: Qt.alpha(Theme.fg, 0.35)
                    font.pixelSize: Math.round(root.corps * 0.72 * echelle)
                    font.letterSpacing: 0.6
                }

                Repeater {
                    model: blocFichier.modelData.sections

                    Column {
                        id: blocSection
                        required property var modelData
                        width: blocFichier.width
                        spacing: Math.round(2 * echelle)

                        Text {
                            width: parent.width
                            visible: String(blocSection.modelData.titre).length > 0
                            text: String(blocSection.modelData.titre)
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: Math.round(root.corps * 0.78 * echelle)
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: blocSection.modelData.items

                            Rectangle {
                                id: ligneItem
                                required property var modelData
                                readonly property bool demande: Boolean(modelData.demande)
                                width: blocSection.width
                                height: contenuItem.implicitHeight + Math.round(8 * echelle)
                                radius: Math.round(5 * echelle)
                                color: survol.containsMouse
                                       ? Qt.alpha(Theme.fg, 0.06) : "transparent"

                                Row {
                                    id: contenuItem
                                    width: parent.width
                                    height: Math.round(16 * echelle)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Math.round(7 * echelle)

                                    // La case : un carré dessiné, pas un glyphe —
                                    // même grille optique que les autres pastilles.
                                    Rectangle {
                                        width: Math.round(12 * echelle)
                                        height: width
                                        radius: Math.round(3 * echelle)
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: ligneItem.modelData.fait
                                               ? Qt.alpha(Theme.accent, 0.85) : "transparent"
                                        border.width: 1
                                        border.color: ligneItem.modelData.fait
                                                      ? Qt.alpha(Theme.accent, 0.9)
                                                      : Qt.alpha(Theme.fg, 0.4)

                                        Icon {
                                            anchors.centerIn: parent
                                            visible: ligneItem.modelData.fait
                                            glyph: "check"
                                            size: Math.round(9 * echelle)
                                            color: Theme.bg
                                        }
                                    }

                                    Column {
                                        width: parent.width - Math.round(30 * echelle)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0

                                        Text {
                                            width: parent.width
                                            text: String(ligneItem.modelData.titre)
                                            color: ligneItem.demande ? Theme.accent : Theme.fg
                                            font.pixelSize: Math.round(root.corps * 0.9 * echelle)
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            visible: String(ligneItem.modelData.detail).length > 0
                                            text: String(ligneItem.modelData.detail)
                                            color: Qt.alpha(Theme.fg, 0.4)
                                            font.pixelSize: Math.round(root.corps * 0.75 * echelle)
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Une demande partie chez l'agent : le dire,
                                    // sinon la coche semble n'avoir rien déclenché.
                                    Text {
                                        width: Math.round(22 * echelle)
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        visible: ligneItem.demande
                                        text: "…"
                                        color: Theme.accent
                                        font.pixelSize: Math.round(root.corps * 0.9 * echelle)
                                    }
                                }

                                MouseArea {
                                    id: survol
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // On ne coche que ce qui reste à faire, et
                                    // jamais une ligne « ✓ fait le … » : elle est
                                    // l'œuvre de l'agent, pas un geste à défaire.
                                    enabled: !ligneItem.modelData.fait
                                             || String(ligneItem.modelData.date).length === 0
                                    onClicked: root.basculer(ligneItem.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── demandes en attente ─────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: root.demandes.length > 0 ? 1 : 0
            color: Qt.alpha(Theme.fg, 0.09)
        }

        Text {
            width: parent.width
            visible: root.demandes.length > 0
            text: root.demandes.length === 1
                  ? "1 demande attend l'agent"
                  : root.demandes.length + " demandes attendent l'agent"
            color: Qt.alpha(Theme.accent, 0.9)
            font.pixelSize: Math.round(root.corps * 0.82 * echelle)
            wrapMode: Text.WordWrap
        }
    }
}
