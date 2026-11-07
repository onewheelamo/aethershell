import QtQuick
import "." 
import Quickshell

// ════════════════════════════════════════════════════════════════════════════
// VISUALISEUR — le dessin. Aucune capture ici : tout vient de VisualiseurAudio.
// ════════════════════════════════════════════════════════════════════════════
// Deux rendus, choisis par l'utilisateur (option `style` de l'applet) :
//
//   • « onde »   — l'enveloppe min/max du signal, tracée en polyline autour de
//                  l'axe médian. C'est l'oscilloscope phase-locké : la figure
//                  ne défile pas, elle respire.
//   • « barres » — le spectre de cava, une barre par bande, qui montent depuis
//                  le bas (ou depuis le bord extérieur sur une barre de côté).
//
// Le composant ne déborde jamais : `clip` est posé ici, et l'amplitude est
// normalisée à la hauteur disponible. Sur une barre de côté, c'est l'appelant
// qui pose la rotation — ce fichier dessine toujours « vers le haut ».
Item {
    id: viz
    clip: true

    // Couleur du tracé : l'accent, comme le reste du shell. Le panneau la
    // rendra réglable quand les autres options y passeront.
    // Barre que ce dessin sert (« haut », « bas », « cote-gauche »…). Une seule
    // barre à la fois porte le visualiseur : c'est un réglage, pas un hasard.
    property string barre: ""

    property color teinte: Theme.vizColor
    property real epaisseur: Theme.vizEpaisseur
    property real remplissage: 0.16

    // L'appelant autorise le dessin (mode « espaces transparents » de la barre).
    property bool autorise: true

    // Tout est piloté par l'**opacité**, jamais par `visible` : passer un item en
    // invisible ne garantit pas que la surface de couche repeigne la zone, et une
    // onde fantôme restait peinte sur la barre qu'on venait de quitter (vécu au
    // passage du visualiseur d'une barre à l'autre). À l'opacité 0 le Canvas ne
    // se redessine plus : coût nul au repos.
    readonly property bool enService: autorise
        && VisualiseurAudio.actif
        && VisualiseurAudio.etat === "run"
        && width > 24 && height > 8
        && (barre === "" || VisualiseurAudio.barre === barre)

    // Rien à montrer : applet éteint, barre non concernée, ou silence (les
    // espaces restent, l'animation s'efface — décision d'Amo).
    opacity: (enService && !VisualiseurAudio.silence) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

    onWidthChanged: canevas.requestPaint()
    onHeightChanged: canevas.requestPaint()

    Connections {
        target: VisualiseurAudio
        function onSeqChanged() { if (viz.opacity > 0.01) canevas.requestPaint() }
        function onStyleChanged() { if (viz.opacity > 0.01) canevas.requestPaint() }
    }

    Canvas {
        id: canevas
        anchors.fill: parent
        antialiasing: true
        // Pas de `renderTarget: FramebufferObject` : la cible FBO ne se vidait
        // pas franchement entre deux trames, et un changement de couleur
        // laissait l'ancienne teinte par-dessous (constaté). Le rendu direct
        // coûte un peu plus, pour 128 points à 30 fps c'est sans importance.
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const haut = VisualiseurAudio.hauteurs
            if (!haut || haut.length < 2) return

            const n = haut.length
            const l = width
            const h = height
            if (l < 4 || h < 4) return

            ctx.strokeStyle = viz.teinte
            ctx.fillStyle = viz.teinte
            ctx.lineWidth = viz.epaisseur
            ctx.lineJoin = "round"
            ctx.lineCap = "round"

            if (VisualiseurAudio.style === "barres") {
                // Une barre par bande, mais pas plus dense qu'un trait lisible :
                // dans un espace de 60 px, 24 barres feraient un peigne. On
                // regroupe alors les bandes par paquets en gardant le maximum
                // — une crête ne doit pas disparaître parce que la place est
                // étroite.
                const pas = l / n
                const groupe = Math.max(1, Math.ceil(4 / Math.max(0.5, pas)))
                const m = Math.max(1, Math.floor(n / groupe))
                const pasBarre = l / m
                const largeur = Math.max(1, pasBarre * 0.62)
                const margeHaut = 2
                for (let j = 0; j < m; ++j) {
                    let v = 0
                    const fin = Math.min(n, (j + 1) * groupe)
                    for (let k = j * groupe; k < fin; ++k) v = Math.max(v, haut[k])
                    v = Math.max(0.03, Math.min(1, v))
                    const hb = v * (h - margeHaut * 2)
                    const x = Math.round(j * pasBarre + (pasBarre - largeur) / 2)
                    ctx.fillRect(x, h - margeHaut - hb, largeur, hb)
                }
                return
            }

            // Enveloppe : la colonne i occupe une fraction de la largeur, le
            // max au-dessus de l'axe, le min en dessous. 0,5 = silence.
            const pas = l / Math.max(1, n - 1)
            const centre = h / 2
            const gain = h - 6

            ctx.beginPath()
            for (let i = 0; i < n; ++i) {
                const y = centre - (haut[i] - 0.5) * gain
                if (i === 0) ctx.moveTo(0, y)
                else ctx.lineTo(i * pas, y)
            }
            ctx.stroke()

            const bas = VisualiseurAudio.bas
            if (bas && bas.length === n) {
                ctx.save()
                ctx.globalAlpha = 0.5
                ctx.beginPath()
                for (let i = 0; i < n; ++i) {
                    const y = centre - (bas[i] - 0.5) * gain
                    if (i === 0) ctx.moveTo(0, y)
                    else ctx.lineTo(i * pas, y)
                }
                ctx.stroke()
                ctx.restore()
            }
        }
    }
}
