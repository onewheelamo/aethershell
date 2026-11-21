import QtQuick
import "."
import Quickshell

// ════════════════════════════════════════════════════════════════════════════
// VISUALISEUR — le dessin. Aucune capture ici : tout vient de VisualiseurAudio.
// ════════════════════════════════════════════════════════════════════════════
// Huit rendus, choisis par l'utilisateur (`styleOverride` ou `VisualiseurAudio.style`) :
//
//   Spectre (cava) :
//     • « barres »  — colonnes montant depuis le bas
//     • « miroir »  — colonnes symétriques autour de l'axe médian
//     • « pics »    — barres + repères de crête flottants (peak hold)
//     • « blocs »   — matrice LED en pastilles empilées
//     • « spectre » — courbe de Bézier lissée avec remplissage dégradé
//
//   Forme d'onde (pwscope) :
//     • « onde »    — enveloppe min/max en double polyline
//     • « ruban »   — enveloppe min/max remplie en ruban translucide
//     • « liquide » — 3 harmoniques sinusoïdales modulées par l'énergie
Item {
    id: viz
    clip: true

    property string barre: ""
    property string styleOverride: ""

    property color teinte: Theme.vizColor
    property real epaisseur: Theme.vizEpaisseur
    property real remplissage: 0.22
    property bool autorise: true

    readonly property string styleActif: styleOverride !== "" ? styleOverride : VisualiseurAudio.style

    // État interne des animations (« pics » et « liquide »)
    property var pics: []
    property real phase: 0

    readonly property bool enService: autorise
        && VisualiseurAudio.actif
        && VisualiseurAudio.etat === "run"
        && width > 24 && height > 8
        && (barre === "" || VisualiseurAudio.barre === barre)

    opacity: (enService && !VisualiseurAudio.silence) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

    onWidthChanged: canevas.requestPaint()
    onHeightChanged: canevas.requestPaint()

    Connections {
        target: VisualiseurAudio
        function onSeqChanged() {
            if (viz.opacity > 0.01) {
                viz.phase = (viz.phase + 0.16) % (Math.PI * 200)
                canevas.requestPaint()
            }
        }
        function onStyleChanged() {
            viz.pics = []
            if (viz.opacity > 0.01) canevas.requestPaint()
        }
    }

    Canvas {
        id: canevas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        function colonnesRegroupees(haut, l) {
            const n = haut.length
            const pas = l / n
            const groupe = Math.max(1, Math.ceil(4 / Math.max(0.5, pas)))
            const m = Math.max(1, Math.floor(n / groupe))
            const vals = []
            for (let j = 0; j < m; ++j) {
                let v = 0
                const fin = Math.min(n, (j + 1) * groupe)
                for (let k = j * groupe; k < fin; ++k) v = Math.max(v, haut[k])
                vals.push(Math.max(0.03, Math.min(1, v)))
            }
            return vals
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const haut = VisualiseurAudio.hauteurs
            if (!haut || haut.length < 2) return

            const n = haut.length
            const l = width
            const h = height
            if (l < 4 || h < 4) return

            const st = viz.styleActif
            ctx.strokeStyle = viz.teinte
            ctx.fillStyle = viz.teinte
            ctx.lineWidth = viz.epaisseur
            ctx.lineJoin = "round"
            ctx.lineCap = "round"

            if (st === "barres") {
                const vals = colonnesRegroupees(haut, l)
                const m = vals.length
                const pasBarre = l / m
                const largeur = Math.max(1, pasBarre * 0.62)
                const margeHaut = 2
                for (let j = 0; j < m; ++j) {
                    const hb = vals[j] * (h - margeHaut * 2)
                    const x = Math.round(j * pasBarre + (pasBarre - largeur) / 2)
                    ctx.fillRect(x, h - margeHaut - hb, largeur, hb)
                }
                return
            }

            if (st === "miroir") {
                const vals = colonnesRegroupees(haut, l)
                const m = vals.length
                const pasBarre = l / m
                const largeur = Math.max(1.5, pasBarre * 0.60)
                const demiH = (h - 4) / 2
                const cy = h / 2
                for (let j = 0; j < m; ++j) {
                    const demi = Math.max(1.5, vals[j] * demiH)
                    const x = Math.round(j * pasBarre + (pasBarre - largeur) / 2)
                    const r = Math.min(largeur / 2, demi)
                    ctx.beginPath()
                    ctx.roundedRect(x, cy - demi, largeur, demi * 2, r, r)
                    ctx.fill()
                }
                return
            }

            if (st === "pics") {
                const vals = colonnesRegroupees(haut, l)
                const m = vals.length
                if (viz.pics.length !== m) {
                    const init = []
                    for (let j = 0; j < m; ++j) init.push(vals[j])
                    viz.pics = init
                }
                const pasBarre = l / m
                const largeur = Math.max(1, pasBarre * 0.62)
                const margeHaut = 3
                const utile = h - margeHaut * 2
                const nouveauxPics = []
                for (let j = 0; j < m; ++j) {
                    const v = vals[j]
                    const prev = Number(viz.pics[j]) || 0
                    const pk = v >= prev ? v : Math.max(v, prev - 0.025)
                    nouveauxPics.push(pk)

                    const x = Math.round(j * pasBarre + (pasBarre - largeur) / 2)
                    const hb = v * utile
                    ctx.save()
                    ctx.globalAlpha = 0.72
                    ctx.fillRect(x, h - margeHaut - hb, largeur, hb)
                    ctx.restore()

                    const py = h - margeHaut - pk * utile - 1.5
                    ctx.fillRect(x, Math.max(1, py), largeur, 2)
                }
                viz.pics = nouveauxPics
                return
            }

            if (st === "blocs") {
                const vals = colonnesRegroupees(haut, l)
                const m = vals.length
                const pasBarre = l / m
                const largeur = Math.max(2, pasBarre * 0.64)
                const blocH = Math.max(2, Math.min(4, Math.floor(h / 7)))
                const gapY = 1.5
                const pasY = blocH + gapY
                const maxBlocs = Math.max(2, Math.floor((h - 4) / pasY))
                for (let j = 0; j < m; ++j) {
                    const nb = Math.max(1, Math.round(vals[j] * maxBlocs))
                    const x = Math.round(j * pasBarre + (pasBarre - largeur) / 2)
                    for (let b = 0; b < nb; ++b) {
                        const y = h - 2 - (b + 1) * pasY + gapY
                        ctx.save()
                        ctx.globalAlpha = 0.45 + 0.55 * ((b + 1) / maxBlocs)
                        ctx.fillRect(x, y, largeur, blocH)
                        ctx.restore()
                    }
                }
                return
            }

            if (st === "spectre") {
                const vals = colonnesRegroupees(haut, l)
                const m = vals.length
                if (m < 2) return
                const pas = l / (m - 1)
                const marge = 2
                const utile = h - marge * 2

                const pts = []
                for (let j = 0; j < m; ++j) {
                    pts.push({ x: j * pas, y: h - marge - vals[j] * utile })
                }

                // Remplissage dégradé sous la courbe
                const grad = ctx.createLinearGradient(0, marge, 0, h - marge)
                grad.addColorStop(0, Qt.rgba(viz.teinte.r, viz.teinte.g, viz.teinte.b, 0.48))
                grad.addColorStop(1, Qt.rgba(viz.teinte.r, viz.teinte.g, viz.teinte.b, 0.04))

                ctx.beginPath()
                ctx.moveTo(0, h - marge)
                ctx.lineTo(pts[0].x, pts[0].y)
                for (let j = 0; j < m - 1; ++j) {
                    const mx = (pts[j].x + pts[j + 1].x) / 2
                    const my = (pts[j].y + pts[j + 1].y) / 2
                    ctx.quadraticCurveTo(pts[j].x, pts[j].y, mx, my)
                }
                ctx.lineTo(pts[m - 1].x, pts[m - 1].y)
                ctx.lineTo(l, h - marge)
                ctx.closePath()
                ctx.save()
                ctx.fillStyle = grad
                ctx.fill()
                ctx.restore()

                // Ligne de crête
                ctx.beginPath()
                ctx.moveTo(pts[0].x, pts[0].y)
                for (let j = 0; j < m - 1; ++j) {
                    const mx = (pts[j].x + pts[j + 1].x) / 2
                    const my = (pts[j].y + pts[j + 1].y) / 2
                    ctx.quadraticCurveTo(pts[j].x, pts[j].y, mx, my)
                }
                ctx.lineTo(pts[m - 1].x, pts[m - 1].y)
                ctx.stroke()
                return
            }

            if (st === "liquide") {
                // Énergie instantanée depuis l'enveloppe pwscope (ou spectre)
                const bas = VisualiseurAudio.bas
                let energie = 0
                if (bas && bas.length === n) {
                    for (let i = 0; i < n; ++i) energie += Math.abs(haut[i] - bas[i])
                    energie = Math.min(1, (energie / n) * 2.2)
                } else {
                    for (let i = 0; i < n; ++i) energie += Math.abs(haut[i] - 0.5)
                    energie = Math.min(1, (energie / n) * 3.0)
                }
                const cy = h / 2
                const ampBase = Math.max(1.5, energie * (h * 0.42))
                const ondes = [
                    { freq: 2.2, vit: 1.0,  echelle: 1.0,  alpha: 0.95 },
                    { freq: 3.1, vit: -1.4, echelle: 0.68, alpha: 0.55 },
                    { freq: 1.5, vit: 0.7,  echelle: 0.45, alpha: 0.35 }
                ]
                const steps = Math.max(24, Math.min(96, Math.round(l / 4)))
                for (let w = 0; w < ondes.length; ++w) {
                    const o = ondes[w]
                    ctx.save()
                    ctx.globalAlpha = o.alpha
                    ctx.beginPath()
                    for (let s = 0; s <= steps; ++s) {
                        const u = s / steps
                        const env = Math.sin(u * Math.PI) // atténuation aux bords
                        const y = cy + Math.sin(u * Math.PI * 2 * o.freq + viz.phase * o.vit)
                                       * ampBase * o.echelle * env
                        if (s === 0) ctx.moveTo(0, y)
                        else ctx.lineTo(u * l, y)
                    }
                    ctx.stroke()
                    ctx.restore()
                }
                return
            }

            // « onde » & « ruban » : enveloppe min/max pwscope
            const pas = l / Math.max(1, n - 1)
            const centre = h / 2
            const gain = h - 6
            const bas = VisualiseurAudio.bas

            if (st === "ruban" && bas && bas.length === n) {
                ctx.save()
                ctx.globalAlpha = viz.remplissage
                ctx.beginPath()
                for (let i = 0; i < n; ++i) {
                    const y = centre - (haut[i] - 0.5) * gain
                    if (i === 0) ctx.moveTo(0, y)
                    else ctx.lineTo(i * pas, y)
                }
                for (let i = n - 1; i >= 0; --i) {
                    ctx.lineTo(i * pas, centre - (bas[i] - 0.5) * gain)
                }
                ctx.closePath()
                ctx.fill()
                ctx.restore()
            }

            ctx.beginPath()
            for (let i = 0; i < n; ++i) {
                const y = centre - (haut[i] - 0.5) * gain
                if (i === 0) ctx.moveTo(0, y)
                else ctx.lineTo(i * pas, y)
            }
            ctx.stroke()

            if (bas && bas.length === n) {
                ctx.save()
                ctx.globalAlpha = st === "ruban" ? 0.75 : 0.5
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
