import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// PEINTURE DU MASQUE DE PARALLAXE
//
// Une fenêtre pour désigner à la main ce qui passe devant : on peint sur une
// vignette du fond courant, et les calques sont découpés sur ce tracé. C'est la
// seule façon d'obtenir des contours qui suivent des objets choisis : mesuré sur
// Fantasy-Landscape1, le modèle de profondeur range la rive de l'étang à 0,45,
// les bosquets de gauche à 0,19 et l'eau à 0,14 — aucun seuil ne peut réunir
// des zones que le modèle sépare ainsi.
//
// Les traits sont envoyés en coordonnées normalisées à core/masque_peinture.py,
// qui rastérise à la taille de l'écran (blanc, bord adouci) et écrit
// `<dossier du fond>/masque.png`. La génération des calques suit, avec
// `--masque-de`, puis `Theme.calquesVersion` fait relire les images au fond.
//
// Ce qui n'est pas fait ici : reprendre une peinture existante (on repeint à
// chaque fois) et gommer (on annule le dernier trait ou on efface tout).
PanelWindow {
    id: fenetre

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    visible: Theme.masqueParallaxeVisible
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "shell-masque"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ── localisation du fond courant ─────────────────────────────────────────
    property string fondCourant: ""
    readonly property string racineFonds: {
        let d = String(Theme.wallpaperDir || "")
        const home = Quickshell.env("HOME") || ""
        if (d.startsWith("$HOME")) d = home + d.slice(5)
        else if (d.startsWith("~")) d = home + d.slice(1)
        return d.replace(/\/?$/, "/")
    }
    readonly property string nomFond: {
        const p = fenetre.fondCourant
        if (p === "") return ""
        const base = p.split("/").pop()
        return base.replace(/\.[^.]+$/, "")
    }
    readonly property string dossier: fenetre.racineFonds + "profondeur/"
                                     + (fenetre.nomFond === "" ? "" : fenetre.nomFond + "/")
    readonly property string cheminMasque: fenetre.dossier + "masque.png"

    readonly property int ecranLargeur: fenetre.screen ? fenetre.screen.width : Screen.width
    readonly property int ecranHauteur: fenetre.screen ? fenetre.screen.height : Screen.height

    // ── état de la peinture ──────────────────────────────────────────────────
    // Chaque trait : { points: [[x, y], …] en 0–1, taille: diamètre en px écran }
    property var traits: []
    property var traitEnCours: null
    // Contours fermés, chacun une liste de points [x, y] normalisés. Le mode
    // « points » sert aux zones qu'on veut suivre au plus près : on pose les
    // sommets sur les contours de l'objet, puis on referme.
    property var contours: []
    property var contourEnCours: []
    // Deux outils : « pinceau » (geste libre) et « points » (polygone).
    property string outil: "pinceau"
    // Position du pointeur dans la vignette (0–1), pour le fil élastique et le
    // cercle de visée.
    property real survolX: 0
    property real survolY: 0
    property bool survol: false
    property real pinceau: 40
    property string message: ""
    property bool travail: false

    function ouvrir() {
        fenetre.traits = []
        fenetre.traitEnCours = null
        fenetre.contours = []
        fenetre.contourEnCours = []
        fenetre.message = ""
        if (!sondeFond.running)
            sondeFond.running = true
    }

    function ajouterPoint(x, y) {
        if (fenetre.traitEnCours === null)
            fenetre.traitEnCours = { points: [], taille: fenetre.pinceau }
        // Les points sont copiés : muter la liste sur place ne réveille pas les
        // propriétés qui en dépendent (le Canvas ne se redessinait pas).
        const points = fenetre.traitEnCours.points.concat([[x / canvasPeinture.width,
                                                            y / canvasPeinture.height]])
        fenetre.traitEnCours = { points: points, taille: fenetre.traitEnCours.taille }
        canvasPeinture.requestPaint()
    }

    function terminerTrait() {
        if (fenetre.traitEnCours === null) return
        if (fenetre.traitEnCours.points.length > 0)
            fenetre.traits = fenetre.traits.concat([fenetre.traitEnCours])
        fenetre.traitEnCours = null
        canvasPeinture.requestPaint()
    }

    function ajouterSommet(x, y) {
        // Recliquer sur le premier sommet referme le contour : c'est le geste
        // naturel d'un outil de détourage.
        const pts = fenetre.contourEnCours
        if (pts.length >= 3) {
            const p0 = pts[0]
            const dx = (x - p0[0]) * canvasPeinture.width
            const dy = (y - p0[1]) * canvasPeinture.height
            if (Math.sqrt(dx * dx + dy * dy) < 12) {
                fenetre.fermerContour()
                return
            }
        }
        fenetre.contourEnCours = pts.concat([[x, y]])
        canvasPeinture.requestPaint()
    }

    function fermerContour() {
        if (fenetre.contourEnCours.length < 3) {
            fenetre.message = "trois points au moins pour fermer un contour."
            return
        }
        fenetre.contours = fenetre.contours.concat([fenetre.contourEnCours])
        fenetre.contourEnCours = []
        fenetre.message = fenetre.contours.length + " contour(s)."
        canvasPeinture.requestPaint()
    }

    function annuler() {
        if (fenetre.outil === "points") {
            if (fenetre.contourEnCours.length > 0)
                fenetre.contourEnCours = fenetre.contourEnCours.slice(0, -1)
            else if (fenetre.contours.length > 0)
                fenetre.contours = fenetre.contours.slice(0, -1)
        } else if (fenetre.traits.length > 0) {
            fenetre.traits = fenetre.traits.slice(0, -1)
        }
        canvasPeinture.requestPaint()
    }

    function enregistrer() {
        fenetre.terminerTrait()
        if (fenetre.contourEnCours.length >= 3)
            fenetre.fermerContour()
        if (fenetre.traits.length === 0 && fenetre.contours.length === 0) {
            fenetre.message = "désigne d'abord la zone qui passe devant."
            return
        }
        if (fenetre.nomFond === "") {
            fenetre.message = "fond courant introuvable."
            return
        }
        fenetre.travail = true
        fenetre.message = "peinture du masque…"
        peintre.command = ["python3", Quickshell.shellPath("core/masque_peinture.py"),
                           "--sortie", fenetre.cheminMasque,
                           "--ecran", fenetre.ecranLargeur + "x" + fenetre.ecranHauteur]
        peintre.running = true
        const envoi = fenetre.traits.map(function (t) {
            return { genre: "trait", points: t.points, taille: t.taille }
        }).concat(fenetre.contours.map(function (c) {
            return { genre: "contour", points: c }
        }))
        peintre.write(JSON.stringify(envoi))
    }

    onVisibleChanged: if (visible) fenetre.ouvrir()

    Process {
        id: sondeFond
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) fenetre.fondCourant = m[1]
            }
        }
    }

    // 1) la peinture → masque.png
    Process {
        id: peintre
        stdinEnabled: true
        stderr: StdioCollector {
            onStreamFinished: if (String(text).trim() !== "") fenetre.message = String(text).trim()
        }
        onExited: (code, statut) => {
            if (code !== 0) {
                fenetre.travail = false
                if (fenetre.message === "") fenetre.message = "échec de la peinture."
                return
            }
            fenetre.message = "découpage des calques…"
            generateur.command = ["python3", Quickshell.shellPath("core/parallaxe_layers.py"),
                                  "generate",
                                  "--wallpaper", fenetre.fondCourant,
                                  "--out", fenetre.dossier,
                                  "--ecran", fenetre.ecranLargeur + "x" + fenetre.ecranHauteur,
                                  "--masque-de", fenetre.cheminMasque]
            generateur.running = true
        }
    }

    // 2) le masque → les trois calques
    Process {
        id: generateur
        stderr: StdioCollector {
            onStreamFinished: if (String(text).trim() !== "") fenetre.message = String(text).trim()
        }
        onExited: (code, statut) => {
            fenetre.travail = false
            if (code !== 0) {
                if (fenetre.message === "") fenetre.message = "échec du découpage."
                return
            }
            Theme.calquesVersion = Theme.calquesVersion + 1
            Theme.masqueParallaxeVisible = false
        }
    }

    // ── fond assombri, clic à côté pour fermer ───────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: if (!fenetre.travail) Theme.masqueParallaxeVisible = false
        }
    }

    Rectangle {
        id: carte
        anchors.centerIn: parent
        width: Math.min(1040, fenetre.width - 120)
        height: entete.height + apercu.height + pied.height + 56
        radius: 14
        color: Theme.surface
        border.color: Qt.alpha(Theme.accent, 0.35)
        border.width: 1

        // Rectangle ne consomme pas les clics : sans cette surface, un clic sur
        // une zone morte de la carte (en-tête, libellés, espaces du pied)
        // traversait jusqu'au fond assombri et **fermait la fenêtre** — d'où
        // l'impression qu'elle se fermait toute seule pendant qu'on peignait.
        MouseArea {
            anchors.fill: parent
            onClicked: {}
            onWheel: (roue) => { roue.accepted = true }
        }

        // ── en-tête ───────────────────────────────────────────────────────────
        Item {
            id: entete
            width: parent.width
            height: 62

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Masque de la parallaxe"
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.weight: Font.Medium
                }

                Text {
                    text: fenetre.nomFond === ""
                          ? "fond courant introuvable"
                          : (fenetre.nomFond + (fenetre.outil === "points"
                             ? " — clic = sommet, Entrée ou clic sur le premier point pour fermer"
                             : " — peins ce qui doit passer devant ; molette = taille du pinceau"))
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Theme.textXs
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: Qt.alpha(Theme.fg, 0.6)
                font.pixelSize: Theme.textMd

                MouseArea {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!fenetre.travail) Theme.masqueParallaxeVisible = false
                }
            }
        }

        // ── vignette peignable ────────────────────────────────────────────────
        Item {
            id: apercu
            anchors.top: entete.bottom
            width: parent.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            height: Math.round(width * 9 / 16)

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.bg
                clip: true

                Image {
                    anchors.fill: parent
                    source: fenetre.fondCourant === "" ? ""
                            : "file://" + fenetre.fondCourant
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                Canvas {
                    id: canvasPeinture
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        const echelle = width / 1920
                        const tous = rootTraits()
                        for (let i = 0; i < tous.length; i++) {
                            const trait = tous[i]
                            const r = Math.max(1, trait.taille * echelle / 2)
                            ctx.fillStyle = Qt.alpha("#ffffff", 0.55)
                            ctx.strokeStyle = Qt.alpha("#ffffff", 0.55)
                            for (let j = 0; j < trait.points.length; j++) {
                                const p = trait.points[j]
                                ctx.beginPath()
                                ctx.arc(p[0] * width, p[1] * height, r, 0, Math.PI * 2)
                                ctx.fill()
                                if (j > 0) {
                                    const q = trait.points[j - 1]
                                    ctx.beginPath()
                                    ctx.moveTo(q[0] * width, q[1] * height)
                                    ctx.lineTo(p[0] * width, p[1] * height)
                                    ctx.lineWidth = 2 * r
                                    ctx.lineCap = "round"
                                    ctx.stroke()
                                }
                            }
                        }

                        // Contours fermés : remplis à moitié, pour juger la
                        // couverture sans masquer le fond dessous.
                        for (let i = 0; i < fenetre.contours.length; i++)
                            dessinerContour(ctx, fenetre.contours[i], true)

                        // Contour en cours : segments posés, fil élastique
                        // jusqu'au pointeur, sommets marqués.
                        if (fenetre.contourEnCours.length > 0) {
                            dessinerContour(ctx, fenetre.contourEnCours, false)
                            const dernier = fenetre.contourEnCours[fenetre.contourEnCours.length - 1]
                            if (fenetre.survol) {
                                ctx.beginPath()
                                ctx.moveTo(dernier[0] * width, dernier[1] * height)
                                ctx.lineTo(fenetre.survolX * width, fenetre.survolY * height)
                                ctx.strokeStyle = Qt.alpha("#ffffff", 0.45)
                                ctx.setLineDash([5, 4])
                                ctx.lineWidth = 1
                                ctx.stroke()
                                ctx.setLineDash([])
                            }
                        }
                    }

                    // Trace un contour ; `ferme` remplit et referme le tracé.
                    function dessinerContour(ctx, points, ferme) {
                        if (points.length === 0) return
                        ctx.beginPath()
                        ctx.moveTo(points[0][0] * width, points[0][1] * height)
                        for (let i = 1; i < points.length; i++)
                            ctx.lineTo(points[i][0] * width, points[i][1] * height)
                        if (ferme) {
                            ctx.closePath()
                            ctx.fillStyle = Qt.alpha("#ffffff", 0.4)
                            ctx.fill()
                        }
                        ctx.strokeStyle = Qt.alpha("#ffffff", 0.95)
                        ctx.lineWidth = 1.5
                        ctx.stroke()
                        for (let i = 0; i < points.length; i++) {
                            ctx.beginPath()
                            ctx.arc(points[i][0] * width, points[i][1] * height, 3, 0, Math.PI * 2)
                            ctx.fillStyle = "#ffffff"
                            ctx.fill()
                        }
                    }

                    function rootTraits() {
                        return fenetre.traitEnCours === null
                               ? fenetre.traits
                               : fenetre.traits.concat([fenetre.traitEnCours])
                    }

                    // Cercle du pinceau : on voit la taille avant de peindre, et
                    // la molette la change sur place (10 à 300 px).
                    Rectangle {
                        id: curseur
                        visible: fenetre.outil === "pinceau" && fenetre.survol && !fenetre.travail
                        width: Math.max(4, fenetre.pinceau * (canvasPeinture.width / 1920))
                        height: width
                        radius: width / 2
                        color: Qt.alpha("#ffffff", 0.12)
                        border.color: Qt.alpha("#ffffff", 0.75)
                        border.width: 1
                        x: zonePeinture.mouseX - width / 2
                        y: zonePeinture.mouseY - height / 2
                    }

                    MouseArea {
                        id: zonePeinture
                        anchors.fill: parent
                        enabled: !fenetre.travail
                        cursorShape: Qt.CrossCursor
                        hoverEnabled: true
                        onWheel: (roue) => {
                            const pas = roue.angleDelta.y > 0 ? 6 : -6
                            fenetre.pinceau = Math.max(10, Math.min(300, fenetre.pinceau + pas))
                        }
                        onPositionChanged: (souris) => {
                            fenetre.survolX = souris.x / width
                            fenetre.survolY = souris.y / height
                            fenetre.survol = true
                            if (fenetre.outil === "pinceau" && pressed)
                                fenetre.ajouterPoint(souris.x, souris.y)
                            canvasPeinture.requestPaint()
                        }
                        onExited: {
                            fenetre.survol = false
                            canvasPeinture.requestPaint()
                        }
                        onClicked: (souris) => {
                            if (fenetre.outil === "points")
                                fenetre.ajouterSommet(souris.x / width, souris.y / height)
                        }
                        onPressed: (souris) => {
                            fenetre.survolX = souris.x / width
                            fenetre.survolY = souris.y / height
                            if (fenetre.outil === "pinceau") {
                                fenetre.traitEnCours = null
                                fenetre.ajouterPoint(souris.x, souris.y)
                            }
                        }
                        onReleased: if (fenetre.outil === "pinceau") fenetre.terminerTrait()
                    }
                }
            }
        }

        // ── pied : pinceau, annulations, enregistrement ───────────────────────
        Item {
            id: pied
            anchors.top: apercu.bottom
            width: parent.width
            height: 62

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                // Deux outils côte à côte : la pastille active est remplie.
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: [{ cle: "pinceau", nom: "Pinceau" },
                                { cle: "points", nom: "Points" }]

                        Rectangle {
                            required property var modelData
                            width: 74
                            height: 26
                            radius: 6
                            color: fenetre.outil === modelData.cle ? Theme.accent : Theme.surfaceVariant
                            border.color: Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.nom
                                color: fenetre.outil === modelData.cle ? Theme.bg : Theme.fg
                                font.pixelSize: Theme.textXs
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !fenetre.travail
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    fenetre.outil = modelData.cle
                                    if (modelData.cle === "points")
                                        fenetre.terminerTrait()
                                    fenetre.message = ""
                                    canvasPeinture.requestPaint()
                                }
                            }
                        }
                    }
                }

                // « Fermer » n'apparaît qu'en mode points : il referme le
                // contour en cours (on peut aussi recliquer sur le premier
                // sommet, ou appuyer sur Entrée).
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fenetre.outil === "points"
                    width: visible ? 74 : 0
                    height: 26
                    radius: 6
                    color: fenetre.contourEnCours.length >= 3 ? Qt.alpha(Theme.accent, 0.85)
                                                                : Theme.surfaceVariant
                    border.color: Qt.alpha(Theme.fg, 0.25)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Fermer"
                        color: fenetre.contourEnCours.length >= 3 ? Theme.bg : Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: Theme.textXs
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !fenetre.travail && fenetre.contourEnCours.length >= 3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fenetre.fermerContour()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fenetre.outil === "pinceau"
                    text: "Taille"
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Theme.textXs
                }

                Rectangle {
                    id: railPinceau
                    visible: fenetre.outil === "pinceau"
                    width: visible ? 150 : 0
                    height: 4
                    radius: 2
                    color: Theme.surfaceVariant

                    Rectangle {
                        width: parent.width * (fenetre.pinceau - 10) / 290
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }

                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.fg
                        border.color: Theme.accent
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width,
                                                parent.width * (fenetre.pinceau - 10) / 290 - width / 2))
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        enabled: !fenetre.travail
                        onClicked: (souris) => {
                            const f = Math.max(0, Math.min(1, souris.x / width))
                            fenetre.pinceau = Math.round(10 + f * 290)
                        }
                        onPositionChanged: (souris) => {
                            if (!pressed) return
                            const f = Math.max(0, Math.min(1, souris.x / width))
                            fenetre.pinceau = Math.round(10 + f * 290)
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fenetre.outil === "pinceau"
                    text: Math.round(fenetre.pinceau) + " px"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Theme.textXs
                    width: 44
                }

                Rectangle {
                    width: 82
                    height: 30
                    radius: 6
                    color: Theme.surfaceVariant
                    border.color: Qt.alpha(Theme.fg, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Annuler"
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !fenetre.travail
                                 && (fenetre.traits.length > 0 || fenetre.contours.length > 0
                                     || fenetre.contourEnCours.length > 0)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fenetre.annuler()
                    }
                }

                Rectangle {
                    width: 72
                    height: 30
                    radius: 6
                    color: Theme.surfaceVariant
                    border.color: Qt.alpha(Theme.fg, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Effacer"
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !fenetre.travail
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            fenetre.traits = []
                            fenetre.traitEnCours = null
                            fenetre.contours = []
                            fenetre.contourEnCours = []
                            fenetre.message = ""
                            canvasPeinture.requestPaint()
                        }
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: fenetre.message
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Theme.textXs
                }

                Rectangle {
                    width: 176
                    height: 32
                    radius: 6
                    color: Qt.alpha(Theme.accent, fenetre.travail ? 0.25 : 0.9)
                    border.color: Qt.alpha(Theme.bg, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: fenetre.travail ? "en cours…" : "Enregistrer"
                        color: Theme.bg
                        font.pixelSize: Theme.textXs
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !fenetre.travail
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fenetre.enregistrer()
                    }
                }
            }
        }
    }

    // Échap referme, comme le panneau.
    Item {
        anchors.fill: parent
        focus: fenetre.visible
        Keys.onEscapePressed: {
            if (fenetre.travail) return
            if (fenetre.contourEnCours.length > 0) {
                fenetre.contourEnCours = []
                canvasPeinture.requestPaint()
                return
            }
            Theme.masqueParallaxeVisible = false
        }
        Keys.onReturnPressed: if (fenetre.outil === "points") fenetre.fermerContour()
        Keys.onEnterPressed: if (fenetre.outil === "points") fenetre.fermerContour()
    }
}
