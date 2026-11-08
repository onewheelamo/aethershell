import QtQuick
import Quickshell
import Quickshell.Io
import "."

// ════════════════════════════════════════════════════════════════════════════
// SÉLECTEUR DE DOSSIER — surface du shell, pas une fenêtre du compositeur.
//
// Un `FolderDialog` Qt ouvre une vraie fenêtre Wayland : le panneau de
// configuration est une surface de couche (Overlay), donc la fenêtre du dialogue
// s'ouvre **sous** elle et devient inatteignable. Le sélecteur est donc dessiné
// dans la même surface que le panneau, avec le verre du shell (mêmes couleurs,
// même opacité, même flou interne).
//
// Usage : `ouvert = true`, `titre` et `chemin` renseignés ; le composant émet
// `accepte(chemin)` ou `annule` et se referme tout seul.
// ════════════════════════════════════════════════════════════════════════════
Item {
    id: root

    property bool ouvert: false
    property string titre: "Choisir un dossier"
    // Chemin absolu, sans `file://` et sans `/` final.
    property string chemin: ""
    property string erreur: ""
    signal accepte(string chemin)
    signal annule()

    visible: ouvert
    // Au-dessus de tout le panneau : c'est une feuille modale.
    z: 1000
    anchors.fill: parent

    readonly property string cheminParent: {
        const p = String(chemin)
        const i = p.lastIndexOf("/")
        return i > 0 ? p.substring(0, i) : "/"
    }

    function entrer(dossier) {
        root.chemin = String(dossier).replace(/\/$/, "")
        listerProc.running = false
        listerProc.running = true
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

    // Voile : assombrit le panneau, et un clic dessus referme.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.45)
        // Le parent est le Loader qui porte la feuille : il n'a pas de rayon.
        radius: (root.parent && root.parent.radius !== undefined) ? root.parent.radius : 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.annule()
        }
    }

    Item {
        id: forceurActif
        focus: root.ouvert
        Keys.onEscapePressed: root.annule()
    }

    Rectangle {
        id: carte
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 60)
        height: Math.min(430, parent.height - 60)
        radius: Theme.globalRadius * 3
        color: Theme.surfaceBg
        border.color: Qt.alpha(Theme.accent, 0.35)
        border.width: 1

        FlouFond {
            anchors.fill: parent
            rayon: carte.radius
            intensite: Theme.shellFlouInterne
        }

        // Le clic dans la carte ne doit pas la refermer.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.padH
            spacing: Theme.space2

            Row {
                width: parent.width
                spacing: Theme.space2

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "folder"
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

            // Chemin courant + remontée.
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

            // L'arborescence, dossiers seulement.
            Rectangle {
                width: parent.width
                height: carte.height - 150
                radius: Theme.globalRadius
                color: Qt.alpha(Theme.bg, 0.35)
                border.color: Theme.surfaceVariant
                border.width: 1
                clip: true

                // Le contenu vient de core/lister_dossiers.py : le moteur QML de
                // Quickshell ne résout pas Qt.labs.folderlistmodel, et un
                // import manquant fait rejeter tout le composant.
                ListModel { id: modele }

                Process {
                    id: listerProc
                    command: ["python3", Quickshell.shellPath("core/lister_dossiers.py"),
                              root.chemin]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            modele.clear()
                            try {
                                const d = JSON.parse(text)
                                for (let i = 0; i < (d.dossiers || []).length; ++i)
                                    modele.append(d.dossiers[i])
                                root.erreur = String(d.erreur || "")
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
                    spacing: 1


                    delegate: Rectangle {
                        required property string nom
                        required property string chemin

                        width: liste.width
                        height: 26
                        radius: Theme.globalRadius
                        color: ligneMa.containsMouse ? Theme.surfaceVariant : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            spacing: Theme.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: "folder"
                                size: Theme.iconSm
                                color: Qt.alpha(Theme.accent, 0.8)
                                opacityLevel: 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: liste.width - 52
                                text: nom
                                color: Theme.fg
                                font.pixelSize: Theme.textXs
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: ligneMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.entrer(chemin)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: liste.count === 0
                    text: root.erreur !== "" ? root.erreur : "Aucun sous-dossier"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.textXs
                }
            }

            Item { width: parent.width; height: 2 }

            Row {
                width: parent.width
                spacing: Theme.space2

                Item { width: parent.width - 2 * 110 - Theme.space2; height: 1 }

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
                        onClicked: root.annule()
                    }
                }

                Rectangle {
                    width: 110
                    height: 30
                    radius: Theme.globalRadius
                    color: choisirMa.containsMouse ? Theme.accentMuted : Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: "Choisir"
                        color: Theme.bg
                        font.pixelSize: Theme.textXs
                        font.bold: true
                    }

                    MouseArea {
                        id: choisirMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.accepte(root.chemin)
                            root.ouvert = false
                        }
                    }
                }
            }
        }
    }
}
