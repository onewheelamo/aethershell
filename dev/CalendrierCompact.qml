import QtQuick
import Quickshell
import Quickshell.Io

// ────────────────────────────────────────────────────────────────────────────
// CALENDRIER COMPACT — la grille du mois, à l'intérieur du widget « date »
//
// Même source que le panneau de l'applet (core/nextcloud_service.py month …),
// mais une autre présentation : pas de formulaire, pas de cache multi-mois, pas
// de fenêtre à ancrer. Le widget s'étend et la grille apparaît dessous.
//
// Le service est interrogé à l'ouverture et à chaque changement de mois ; sa
// propre réponse contient déjà les jours précédents et suivants, qu'on ignore.
// ────────────────────────────────────────────────────────────────────────────
Item {
    id: racine

    property real echelle: 1.0
    property int moisOffset: 0

    readonly property var moisNoms: ["janvier", "février", "mars", "avril", "mai",
                                     "juin", "juillet", "août", "septembre",
                                     "octobre", "novembre", "décembre"]
    readonly property var joursCourts: ["L", "M", "M", "J", "V", "S", "D"]

    readonly property date reference: {
        const d = new Date()
        return new Date(d.getFullYear(), d.getMonth() + moisOffset, 1)
    }
    readonly property int annee: reference.getFullYear()
    readonly property int mois: reference.getMonth() + 1

    readonly property string cleMois: String(annee) + "-" + String(mois).padStart(2, "0")
    readonly property string cleAujourdhui: {
        const d = new Date()
        return String(d.getFullYear()) + "-" + String(d.getMonth() + 1).padStart(2, "0")
               + "-" + String(d.getDate()).padStart(2, "0")
    }

    property var parJour: ({})        // "YYYY-MM-DD" → [événements]
    property string statut: "idle"
    property bool charge: false
    property int jourChoisi: 0        // 0 = aujourd'hui / rien de choisi

    // Cases de la grille : "" pour les blancs avant le 1er, puis 1..31.
    readonly property var cases: {
        const premier = new Date(annee, mois - 1, 1)
        const decalage = (premier.getDay() + 6) % 7      // lundi = 0
        const nb = new Date(annee, mois, 0).getDate()
        const out = []
        for (let i = 0; i < decalage; ++i) out.push(0)
        for (let j = 1; j <= nb; ++j) out.push(j)
        return out
    }

    function cleDe(jour) {
        return String(annee) + "-" + String(mois).padStart(2, "0") + "-" + String(jour).padStart(2, "0")
    }

    function evenementsDu(jour) {
        if (!jour) return []
        const l = parJour[cleDe(jour)]
        return Array.isArray(l) ? l : []
    }

    readonly property var jourAffiche: {
        if (jourChoisi > 0) return jourChoisi
        // Par défaut : aujourd'hui s'il est dans le mois affiché.
        if (cleAujourdhui.indexOf(cleMois) === 0) return Number(cleAujourdhui.slice(8, 10))
        return 0
    }

    readonly property var listeJour: jourAffiche > 0 ? evenementsDu(jourAffiche) : []

    function charger(force) {
        statut = "loading"
        proc.command = ["python3", Quickshell.shellPath("core/nextcloud_service.py"),
                        "month", String(annee), String(mois)]
        if (force) proc.command = proc.command.concat(["--force"])
        proc.running = true
    }

    onMoisOffsetChanged: {
        jourChoisi = 0
        charger(false)
    }

    Component.onCompleted: charger(false)

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text.trim())
                    racine.parJour = (r && r.days) ? r.days : ({})
                    racine.statut = (r && r.status) ? r.status : "ok"
                } catch (e) {
                    racine.parJour = ({})
                    racine.statut = "error"
                }
                racine.charge = true
            }
        }
    }

    implicitWidth: 196 * echelle
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: parent.width
        spacing: 6

        // ── navigation ──────────────────────────────────────────────────────
        Row {
            width: parent.width

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: prec.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: 14 * racine.echelle

                MouseArea {
                    id: prec
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: racine.moisOffset -= 1
                }
            }

            Item { width: 4; height: 1 }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 28
                text: racine.moisNoms[racine.mois - 1] + " " + racine.annee
                color: Theme.fg
                font.pixelSize: Math.round(11 * racine.echelle)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: suiv.containsMouse ? Theme.accent : Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: 14 * racine.echelle

                MouseArea {
                    id: suiv
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: racine.moisOffset += 1
                }
            }
        }

        // ── en-tête des jours ───────────────────────────────────────────────
        Row {
            width: parent.width
            Repeater {
                model: racine.joursCourts
                Text {
                    required property string modelData
                    width: colonne.width / 7
                    text: modelData
                    color: Qt.alpha(Theme.fg, 0.4)
                    font.pixelSize: Math.round(9 * racine.echelle)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // ── grille ──────────────────────────────────────────────────────────
        Grid {
            width: parent.width
            columns: 7
            rowSpacing: 2

            Repeater {
                model: racine.cases

                Item {
                    required property int modelData
                    // La cellule suit la largeur disponible : le widget peut
                    // être plus large que la grille nominale, et une grille
                    // étroite avec des jours tassés serait illisible.
                    readonly property real cote: colonne.width / 7
                    readonly property bool vide: modelData === 0
                    readonly property bool aujourdhui: !vide
                        && racine.cleAujourdhui === racine.cleDe(modelData)
                    readonly property bool choisi: !vide && racine.jourChoisi === modelData
                    readonly property int combien: racine.evenementsDu(modelData).length

                    width: cote
                    height: Math.round(Math.max(19 * racine.echelle, cote * 0.8))

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(Math.min(cote - 6, 22 * racine.echelle))
                        height: width
                        radius: width / 2
                        color: parent.choisi ? Theme.accent
                               : (parent.aujourdhui ? Qt.alpha(Theme.accent, 0.22) : "transparent")
                        border.width: parent.aujourdhui && !parent.choisi ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.55)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !parent.vide
                        text: parent.vide ? "" : String(parent.modelData)
                        color: parent.choisi ? Theme.bg : Theme.fg
                        font.pixelSize: Math.round(11 * racine.echelle)
                        font.bold: parent.aujourdhui
                    }

                    // Pastille : des événements ce jour-là.
                    Rectangle {
                        visible: parent.combien > 0 && !parent.choisi
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        width: 3
                        height: 3
                        radius: 2
                        color: Qt.alpha(Theme.accent, 0.85)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: racine.jourChoisi = parent.modelData
                    }
                }
            }
        }

        // ── la journée choisie ──────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        Column {
            width: parent.width
            spacing: 2

            Text {
                width: parent.width
                text: racine.listeJour.length === 0
                      ? (racine.statut === "loading" ? "chargement…" : "rien ce jour-là")
                      : (racine.listeJour.length + (racine.listeJour.length > 1
                                                    ? " événements" : " événement"))
                color: Qt.alpha(Theme.fg, 0.42)
                font.pixelSize: Math.round(9 * racine.echelle)
                elide: Text.ElideRight
            }

            Repeater {
                model: racine.listeJour.slice(0, 4)

                Row {
                    required property var modelData
                    width: colonne.width
                    spacing: 5

                    Text {
                        text: "•"
                        color: Qt.alpha(Theme.accent, 0.9)
                        font.pixelSize: Math.round(9 * racine.echelle)
                    }

                    Text {
                        width: parent.width - 12
                        text: String(modelData.summary || "")
                        color: Theme.fg
                        font.pixelSize: Math.round(9.5 * racine.echelle)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
