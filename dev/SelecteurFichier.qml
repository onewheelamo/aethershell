import QtQuick
import Quickshell
import Quickshell.Io
import "."

// ════════════════════════════════════════════════════════════════════════════
// SÉLECTEUR DE FICHIER — surface du shell, pas une fenêtre du compositeur.
//
// Un `FileDialog` Qt ouvre une vraie fenêtre Wayland qui passerait sous la surface
// de couche du panneau. Le sélecteur est donc dessiné directement dans la même
// surface que le panneau, avec le verre du shell (mêmes couleurs, opacité, flou).
//
// Usage : `ouvert = true`, `titre`, `chemin` et `extensions` renseignés.
// Émet `accepte(cheminFichier)` ou `annule()` et se referme.
// ════════════════════════════════════════════════════════════════════════════
Item {
    id: root

    property bool ouvert: false
    property string titre: "Choisir un fichier Markdown"
    // Dossier en cours d'exploration (chemin absolu, sans slash final)
    property string chemin: ""
    // Fichier actuellement sélectionné dans la liste
    property string fichierSelectionne: ""
    // Liste des extensions autorisées (ex: ["md", "markdown"])
    property var extensions: ["md", "markdown"]
    property string erreur: ""

    signal accepte(string chemin)
    signal annule()

    visible: ouvert
    z: 1000
    anchors.fill: parent

    readonly property string cheminParent: {
        const p = String(chemin)
        const i = p.lastIndexOf("/")
        return i > 0 ? p.substring(0, i) : "/"
    }

    function nomFichier(p) {
        const s = String(p || "")
        const i = s.lastIndexOf("/")
        return i >= 0 ? s.substring(i + 1) : s
    }

    function entrer(dossier) {
        root.chemin = String(dossier).replace(/\/$/, "")
        root.fichierSelectionne = ""
        listerProc.running = false
        listerProc.running = true
    }

    function valider() {
        if (root.fichierSelectionne === "")
            return
        root.accepte(root.fichierSelectionne)
        root.ouvert = false
    }

    function fermer() {
        root.ouvert = false
    }

    onOuvertChanged: {
        if (ouvert) {
            forceurActif.forceActiveFocus()
            listerProc.running = false
            listerProc.running = true
        }
    }

    // Voile assombrissant le panneau
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.45)
        radius: (root.parent && root.parent.radius !== undefined) ? root.parent.radius : 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.annule()
                root.ouvert = false
            }
        }
    }

    Item {
        id: forceurActif
        focus: root.ouvert
        Keys.onEscapePressed: {
            root.annule()
            root.ouvert = false
        }
    }

    Rectangle {
        id: carte
        anchors.centerIn: parent
        width: Math.min(580, parent.width - 60)
        height: Math.min(460, parent.height - 60)
        radius: Theme.globalRadius * 3
        color: Theme.surfaceBg
        border.color: Qt.alpha(Theme.accent, 0.35)
        border.width: 1

        FlouFond {
            anchors.fill: parent
            rayon: carte.radius
            intensite: Theme.shellFlouInterne
        }

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.padH
            spacing: Theme.space2

            // Titre avec icône
            Row {
                width: parent.width
                spacing: Theme.space2

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "markdown"
                    size: Theme.iconSm
                    color: Theme.accent
                    opacityLevel: 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconSm - Theme.space2
                    text: root.titre
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            // Chemin courant + bouton parent
            Row {
                width: parent.width
                spacing: Theme.space2

                Rectangle {
                    width: 32
                    height: 26
                    radius: Theme.globalRadius
                    color: remonterMa.containsMouse ? Theme.surfaceVariant : "transparent"
                    border.color: Theme.surfaceVariant
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        color: Theme.accent
                        font.pixelSize: Theme.textSm
                        font.bold: true
                    }

                    MouseArea {
                        id: remonterMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.entrer(root.cheminParent)
                    }
                }

                Rectangle {
                    width: parent.width - 32 - Theme.space2
                    height: 26
                    radius: Theme.globalRadius
                    color: Theme.bg
                    border.color: Theme.surfaceVariant
                    border.width: 1
                    clip: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        width: parent.width - 16
                        text: root.chemin
                        color: Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideMiddle
                    }
                }
            }

            // Arborescence : dossiers pour naviguer, fichiers pour sélectionner
            Rectangle {
                width: parent.width
                height: carte.height - 156
                radius: Theme.globalRadius
                color: Qt.alpha(Theme.bg, 0.35)
                border.color: Theme.surfaceVariant
                border.width: 1
                clip: true

                ListModel { id: modele }

                Process {
                    id: listerProc
                    command: {
                        let cmd = ["python3", Quickshell.shellPath("core/lister_fichiers.py"), root.chemin]
                        for (let i = 0; i < (root.extensions || []).length; ++i) {
                            cmd.push(String(root.extensions[i]))
                        }
                        return cmd
                    }
                    stdout: StdioCollector {
                        onStreamFinished: {
                            modele.clear()
                            try {
                                const d = JSON.parse(text)
                                for (let i = 0; i < (d.entrees || []).length; ++i)
                                    modele.append(d.entrees[i])
                                root.erreur = String(d.erreur || "")
                                if (d.chemin)
                                    root.chemin = d.chemin
                            } catch (e) {
                                root.erreur = "lecture impossible"
                            }
                        }
                    }
                }

                ListView {
                    id: liste
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: modele
                    spacing: 2

                    delegate: Rectangle {
                        id: ligneDossierFichier
                        required property string nom
                        required property string chemin
                        required property bool est_dossier

                        readonly property bool estSelectionne: !est_dossier && root.fichierSelectionne === chemin

                        width: liste.width
                        height: 28
                        radius: Theme.globalRadius
                        color: estSelectionne
                               ? Qt.alpha(Theme.accent, 0.22)
                               : (ligneMa.containsMouse ? Theme.surfaceVariant : "transparent")
                        border.color: estSelectionne ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                        border.width: estSelectionne ? 1 : 0

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: est_dossier ? "folder" : "markdown"
                                size: Theme.iconSm
                                color: est_dossier
                                       ? Qt.alpha(Theme.accent, 0.85)
                                       : (estSelectionne ? Theme.accent : Qt.alpha(Theme.fg, 0.75))
                                opacityLevel: 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: ligneDossierFichier.width - 60
                                text: nom
                                color: estSelectionne ? Theme.accent : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: estSelectionne || est_dossier
                                elide: Text.ElideRight
                            }

                            Item {
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                visible: est_dossier

                                Icon {
                                    anchors.centerIn: parent
                                    glyph: "chevron-right"
                                    size: Math.round(Theme.iconSm * 0.7)
                                    color: Qt.alpha(Theme.fg, 0.3)
                                    opacityLevel: 1
                                }
                            }
                        }

                        MouseArea {
                            id: ligneMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (est_dossier) {
                                    root.entrer(chemin)
                                } else {
                                    if (root.fichierSelectionne === chemin) {
                                        root.valider()
                                    } else {
                                        root.fichierSelectionne = chemin
                                    }
                                }
                            }
                            onDoubleClicked: {
                                if (est_dossier) {
                                    root.entrer(chemin)
                                } else {
                                    root.fichierSelectionne = chemin
                                    root.valider()
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: liste.count === 0
                    text: root.erreur !== "" ? root.erreur : "Aucun dossier ni fichier correspondant"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.textXs
                }
            }

            Item { width: parent.width; height: 2 }

            // Barre inférieure : fichier sélectionné + boutons
            Row {
                width: parent.width
                spacing: Theme.space2

                // Indicateur du fichier sélectionné
                Row {
                    width: parent.width - 2 * 110 - Theme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    clip: true

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "check"
                        size: Math.round(Theme.iconSm * 0.8)
                        color: Theme.accent
                        visible: root.fichierSelectionne !== ""
                        opacityLevel: 1
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24
                        text: root.fichierSelectionne !== ""
                              ? root.nomFichier(root.fichierSelectionne)
                              : "Sélectionnez un fichier .md"
                        color: root.fichierSelectionne !== "" ? Theme.fg : Qt.alpha(Theme.fg, 0.4)
                        font.pixelSize: Theme.textXs
                        font.bold: root.fichierSelectionne !== ""
                        elide: Text.ElideMiddle
                    }
                }

                // Bouton Annuler
                Rectangle {
                    width: 110
                    height: 30
                    radius: Theme.globalRadius
                    color: annulerMa.containsMouse ? Theme.surfaceVariant : "transparent"
                    border.color: Theme.surfaceVariant
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Annuler"
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                    }

                    MouseArea {
                        id: annulerMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.annule()
                            root.ouvert = false
                        }
                    }
                }

                // Bouton Choisir
                Rectangle {
                    width: 110
                    height: 30
                    radius: Theme.globalRadius
                    readonly property bool actif: root.fichierSelectionne !== ""
                    color: !actif ? Qt.alpha(Theme.surfaceVariant, 0.5)
                                  : (choisirMa.containsMouse ? Theme.accentMuted : Theme.accent)
                    opacity: actif ? 1.0 : 0.45

                    Text {
                        anchors.centerIn: parent
                        text: "Choisir"
                        color: parent.actif ? Theme.bg : Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        id: choisirMa
                        anchors.fill: parent
                        enabled: parent.actif
                        hoverEnabled: parent.actif
                        cursorShape: parent.actif ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.valider()
                    }
                }
            }
        }
    }
}
