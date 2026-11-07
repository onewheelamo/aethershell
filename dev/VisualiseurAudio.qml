pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// ════════════════════════════════════════════════════════════════════════════
// VISUALISEUR AUDIO — la source unique des colonnes, une seule capture
// ════════════════════════════════════════════════════════════════════════════
// Un singleton, donc un seul processus de capture quel que soit le nombre de
// visualiseurs affichés (deux par barre). C'est la leçon du plugin Noctalia
// d'origine : plusieurs instances partagent une seule source, sinon chacune
// ouvrirait son propre flux PipeWire.
//
// Deux fournisseurs, un même modèle de sortie (`hauteurs` / `bas`, 0..1) :
//
//   • « onde »    — pwscope (C, PipeWire) : enveloppe min/max par colonne du
//                   signal temporel, phase verrouillée par YIN. Une ligne qui
//                   ne défile pas.
//   • « barres »  — cava : spectre du monitor du sink, 24 bandes. Des barres
//                   qui montent et redescendent avec la musique.
//
// Le choix appartient à l'utilisateur et vit dans le registre des applets
// (`bar_applets.json`, option `style` de l'applet « visualiseur »), comme les
// autres options d'applet : le panneau n'a rien de spécial à savoir.
Singleton {
    id: racine

    // ── état lu dans le registre ────────────────────────────────────────────
    property bool actif: false
    property string style: "onde"          // "onde" | "barres"

    // ── sortie normalisée, consommée par Visualiseur.qml ────────────────────
    property var hauteurs: []              // 0..1, une entrée par colonne
    property var bas: []                   // 0..1, enveloppe basse (mode onde)
    property bool silence: true
    property int seq: 0                    // compteur de trames : rejoue le dessin
    property int nbColonnes: 0

    // « idle » (aucune applet), « prepare » (compilation), « run », « erreur »
    property string etat: "idle"
    property string detail: ""

    // Réglages de capture. Ils ne changent qu'à l'arrêt/relance du processus :
    // c'est voulu, un redémarrage du flux à chaque pixel serait pire que le
    // défaut. Le panneau les écrira dans style_vars plus tard.
    readonly property int fps: 30
    readonly property int colsOnde: 96
    readonly property int colsBarres: 24

    onActifChanged: racine.rearmer()
    onStyleChanged: racine.rearmer()

    // ── registre : quels applets sont allumés, et avec quelles options ──────
    // `onLoaded` et non `onTextChanged` : FileView charge en asynchrone, donc
    // au `Component.onCompleted` le texte est encore vide. C'est le motif de
    // Theme.qml (styleFile) — sans lui, l'applet restait vu comme éteint au
    // démarrage et le moteur ne démarrait jamais.
    FileView {
        id: registre
        path: Quickshell.shellPath("core/bar_applets.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: racine.lireRegistre()
    }

    function lireRegistre() {
        try {
            // `text()` est une méthode du FileView : dans une fonction du
            // singleton, il faut la qualifier (`registre.text()`), sinon
            // ReferenceError silencieuse au premier chargement.
            const d = JSON.parse(registre.text())
            const entrees = (d && d.actifs) ? d.actifs : {}
            const moi = entrees["visualiseur"] || null
            racine.actif = moi !== null
            const opt = (moi && moi.options) ? moi.options : {}
            const s = String(opt.style || "onde")
            racine.style = (s === "barres") ? "barres" : "onde"
        } catch (e) {
            racine.actif = false
        }
    }

    // ── compilation / disponibilité du moteur ───────────────────────────────
    property string binaire: ""

    Process {
        id: compil
        command: ["sh", Quickshell.shellPath("core/pwscope_make.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const chemin = String(text || "").trim()
                if (chemin !== "" && chemin.indexOf("/") === 0) {
                    racine.binaire = chemin
                    racine.rearmer()
                } else {
                    racine.etat = "erreur"
                    racine.detail = "compilation pwscope"
                }
            }
        }
        onExited: code => {
            if (code !== 0) {
                racine.etat = "erreur"
                racine.detail = "compilation pwscope (code " + code + ")"
            }
        }
    }

    // ── fournisseur « onde » : pwscope ──────────────────────────────────────
    Process {
        id: scope
        running: false
        command: racine.binaire !== ""
            ? [racine.binaire, "--fps", String(racine.fps), "--cols", String(racine.colsOnde)]
            : []
        stdout: SplitParser {
            onRead: line => racine.trameScope(line)
        }
        onExited: code => {
            if (!racine.actif || racine.style !== "onde") return
            // Trois échecs d'affilée = le binaire ne marche pas ici (PipeWire
            // absent, cible introuvable). Inutile de relancer indéfiniment :
            // le visualiseur se tait, la barre n'en sait rien.
            racine.echecs = (code === 0) ? 0 : (racine.echecs + 1)
            if (racine.echecs >= 3) {
                racine.etat = "erreur"
                racine.detail = "pwscope (code " + code + ")"
                return
            }
            relance.restart()
        }
    }

    // ── fournisseur « barres » : cava ───────────────────────────────────────
    Process {
        id: barres
        running: false
        command: ["cava", "-p", Quickshell.shellPath("core/cava_viz.conf")]
        stdout: SplitParser {
            onRead: line => racine.trameCava(line)
        }
        onExited: {
            if (racine.actif && racine.style === "barres") relance.restart()
        }
    }

    Timer {
        id: relance
        interval: 2000
        repeat: false
        onTriggered: racine.demarrer()
    }

    // ── trames ──────────────────────────────────────────────────────────────
    // « F seq rms peak flags min0 max0 min1 max1 … », amplitudes 0..255 avec
    // 128 pour le silence. On ne relit que ce dont le dessin a besoin.
    function trameScope(ligne) {
        const l = String(ligne || "")
        if (l.charAt(0) !== "F") return                  // diagnostic « # … »
        const t = l.split(/\s+/)
        if (t.length < 7) return
        const n = Math.floor((t.length - 5) / 2)
        if (n < 2) return
        const haut = []
        const basse = []
        for (let i = 0; i < n; ++i) {
            const mn = Number(t[5 + i * 2]) / 255
            const mx = Number(t[6 + i * 2]) / 255
            haut.push(isFinite(mx) ? mx : 0.5)
            basse.push(isFinite(mn) ? mn : 0.5)
        }
        const flags = Number(t[4])
        racine.hauteurs = haut
        racine.bas = basse
        racine.nbColonnes = n
        racine.silence = (flags & 1) === 1
        racine.seq = Number(t[1]) || (racine.seq + 1)
        racine.etat = "run"
    }

    // cava : une ligne par trame, « 12;40;8;… » sur 0..100.
    function trameCava(ligne) {
        const l = String(ligne || "").trim()
        if (l === "" || l.indexOf(";") < 0) return
        const morceaux = l.split(";")
        const vals = []
        for (let i = 0; i < morceaux.length; ++i) {
            const v = Number(morceaux[i])
            if (!isFinite(v)) continue
            vals.push(Math.max(0, Math.min(1, v / 100)))
        }
        if (vals.length < 2) return
        let somme = 0
        for (let i = 0; i < vals.length; ++i) somme += vals[i]
        racine.hauteurs = vals
        racine.bas = []
        racine.nbColonnes = vals.length
        racine.silence = somme < 0.02
        racine.seq = racine.seq + 1
        racine.etat = "run"
    }

    // ── conduite des processus ──────────────────────────────────────────────
    function arreter() {
        relance.stop()
        if (scope.running) scope.running = false
        if (barres.running) barres.running = false
        racine.hauteurs = []
        racine.bas = []
        racine.silence = true
        racine.etat = "idle"
    }

    function demarrer() {
        if (!racine.actif) { racine.arreter(); return }
        if (racine.style === "barres") {
            if (barres.running) return
            racine.etat = "run"
            barres.running = true
            return
        }
        // « onde » : il faut le binaire compilé avant tout.
        if (racine.binaire === "") {
            if (!compil.running) { racine.etat = "prepare"; compil.running = true }
            return
        }
        if (scope.running) return
        racine.etat = "run"
        scope.running = true
    }

    function rearmer() {
        racine.arreter()
        if (racine.actif) racine.demarrer()
    }

    Component.onCompleted: racine.lireRegistre()
}
