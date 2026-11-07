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
//
// ── Veille ──────────────────────────────────────────────────────────────────
// Un visualiseur qui écoute en permanence coûte 2 à 3 % d'un cœur, même quand
// rien ne joue : inacceptable pour un applet qu'on laisse allumé. D'où trois
// mécanismes, du moins cher au plus cher :
//
//   1. après 10 s sans une seule trame non silencieuse, la capture s'arrête ;
//   2. en veille, `pactl subscribe` (un processus au repos, coût nul) réveille
//      dès qu'un flux audio apparaît ou change d'état ;
//   3. toutes les 20 s en veille, une écoute de 3 s rattrape le cas qu'aucun
//      événement ne signale (une application qui garde son flux ouvert et se
//      remet à écrire sans changer de propriété).
//
// Le réveil par événement est instantané ; l'écoute périodique coûte ~0,3 %
// d'un cœur en veille, contre 2-3 % en capture continue.
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

    // « idle » (aucune applet), « prepare » (compilation), « run », « veille »
    // (silence prolongé : plus de capture), « erreur »
    property string etat: "idle"
    property string detail: ""

    // Quelle barre porte le visualiseur (« haut », « bas », « cote-gauche »,
    // « cote-droite »). Une seule à la fois : deux barres qui captent en même
    // temps donneraient deux animations désynchronisées du même son.
    property string barre: "haut"

    // Filtre des navigateurs : même liste que core/musique_applet.py, pour que
    // « filtrer les navigateurs » veuille dire la même chose dans les deux
    // applets. Le son d'un navigateur est ignoré : la capture est celle du
    // sink entier, on ne peut pas l'isoler, donc on cesse de le visualiser.
    readonly property var navigateurs: ["firefox", "zen", "chromium", "chrome",
                                        "brave", "vivaldi", "opera", "edge",
                                        "librewolf", "waterfox"]
    property bool ignorerNavigateurs: true
    property bool seulementNavigateurs: false

    // Veille : capture arrêtée faute de son, réveil sur événement audio.
    property bool veille: false
    // Une trame non silencieuse est passée depuis le dernier réveil.
    property bool activiteVue: false
    // Échecs consécutifs du moteur : au troisième, on renonce (voir onExited).
    property int echecs: 0

    // Réglages de capture, lus dans le thème (donc dans style_vars.json, réglés
    // par le panneau). Ils ne changent qu'à l'arrêt/relance du processus : un
    // redémarrage du flux à chaque pixel serait pire que le défaut, d'où les
    // `on…Changed` qui réarment.
    readonly property int fps: Theme.vizFps
    readonly property int colsOnde: Theme.vizCols
    // cava veut un nombre de bandes, pas une largeur : on garde le même ordre de
    // grandeur que le mode onde (une bande pour quatre colonnes), borné.
    readonly property int colsBarres: Math.max(8, Math.min(64, Math.round(Theme.vizCols / 4)))

    onActifChanged: racine.rearmer()
    onStyleChanged: racine.rearmer()
    onFpsChanged: racine.rearmer()
    onColsOndeChanged: racine.rearmer()
    onColsBarresChanged: racine.rearmer()
    // La sensibilité et le lissage sont des arguments de pwscope : même régime.
    Connections {
        target: Theme
        function onVizSensibiliteChanged() { racine.rearmer() }
        function onVizLissageChanged() { racine.rearmer() }
    }

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

    // ── flux audio présents : qui joue, et est-ce un navigateur ? ───────────
    // `corked` = flux ouvert mais muet (lecteur en pause) : il ne compte pas.
    Process {
        id: flux
        command: ["pactl", "-f", "json", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: racine.lireFlux(text)
        }
    }

    function majFlux() {
        if (flux.running) return
        flux.running = true
    }

    function lireFlux(txt) {
        try {
            const d = JSON.parse(String(txt || "[]"))
            let actifs = 0
            let navigateursActifs = 0
            for (let i = 0; i < d.length; ++i) {
                const objet = d[i] || {}
                if (objet.corked === true) continue
                actifs++
                const p = objet.properties || {}
                const nom = String(p["application.name"] || "").toLowerCase()
                const binaire = String(p["application.process.binary"] || "").toLowerCase()
                let nav = false
                for (let k = 0; k < racine.navigateurs.length; ++k) {
                    const n = racine.navigateurs[k]
                    if (nom.indexOf(n) >= 0 || binaire.indexOf(n) >= 0) { nav = true; break }
                }
                if (nav) navigateursActifs++
            }
            racine.seulementNavigateurs = actifs > 0 && actifs === navigateursActifs
            // Un flux joue déjà au démarrage (ou reprend sans événement) : la
            // veille ne doit pas attendre. `majFlux` ne tourne qu'au démarrage
            // et sur événement, donc ce réveil ne boucle pas.
            if (actifs > 0 && racine.veille) racine.reveiller(false)
        } catch (e) {
            // Lecture impossible : on ne filtre pas plutôt que de tout masquer.
            racine.seulementNavigateurs = false
        }
    }

    // Vrai quand la seule source est un navigateur et que l'utilisateur a
    // demandé de les ignorer. La capture continue (on ne sait pas l'isoler),
    // mais les trames sont traitées comme du silence — donc le tracé s'efface
    // et la veille finit par couper le processus.
    function estFiltre() {
        return racine.ignorerNavigateurs && racine.seulementNavigateurs
    }

    onIgnorerNavigateursChanged: racine.majFlux()

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
            racine.barre = String(moi.ile || "haut:milieu").split(":")[0] || "haut"
            racine.ignorerNavigateurs = opt.ignorer_navigateurs !== false
        } catch (e) {
            racine.actif = false
        }
    }

    // ── compilation / disponibilité du moteur ───────────────────────────────
    property string binaire: ""

    // Balayage au démarrage : une coquille tuée brutalement (SIGKILL, OOM) ne
    // peut pas faire partir son enfant, et pwscope survit alors à tout — il
    // continuait de capter pour personne (constaté : un processus reparenté à
    // systemd). On tue les restes avant de démarrer les nôtres.
    Process {
        id: balayage
        // `-x` sur le nom exact : un `-f` sur le chemin tuerait aussi tout
        // processus dont la ligne de commande contient ce chemin (vécu : mon
        // propre shell de test). Le nom du binaire est unique.
        command: ["sh", "-c", "pkill -x pwscope 2>/dev/null; true"]
    }

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

    // Enfant gardé : pwscope ne meurt pas quand son lecteur disparaît (mesuré),
    // donc une coquille tuée laissait une capture orpheline derrière elle. On
    // l'enferme dans un shell qui se termine avec nous, y compris sur SIGTERM.
    function lanceur(commande) {
        return ["sh", "-c",
            "P=$PPID; trap 'kill $C 2>/dev/null; exit 0' TERM INT; "
            + commande + " & C=$!; "
            + "while kill -0 $P 2>/dev/null; do sleep 1; done; kill $C 2>/dev/null"]
    }

    // ── fournisseur « onde » : pwscope ──────────────────────────────────────
    Process {
        id: scope
        running: false
        command: racine.binaire !== ""
            ? racine.lanceur("'" + racine.binaire + "' --fps " + racine.fps
                             + " --cols " + racine.colsOnde
                             + " --sensitivity " + Theme.vizSensibilite
                             + " --smoothing " + Theme.vizLissage)
            : []
        stdout: SplitParser {
            onRead: line => racine.trameScope(line)
        }
        onExited: code => {
            if (!racine.actif || racine.style !== "onde") return
            if (racine.veille) return                    // arrêt volontaire
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
        command: racine.lanceur("cava -p '" + Quickshell.shellPath("core/cava_viz.conf")
                                + "' -b " + racine.colsBarres)
        stdout: SplitParser {
            onRead: line => racine.trameCava(line)
        }
        onExited: {
            if (!racine.actif || racine.style !== "barres") return
            if (racine.veille) return                    // arrêt volontaire
            relance.restart()
        }
    }

    Timer {
        id: relance
        interval: 2000
        repeat: false
        onTriggered: racine.demarrer()
    }

    Timer {
        id: demarrageDiffere
        interval: 250
        repeat: false
        onTriggered: racine.demarrer()
    }

    // ── veille : détection d'activité ───────────────────────────────────────
    // `pactl subscribe` reste au repos tant que rien ne bouge côté son : c'est
    // le réveil gratuit. On ignore les disparitions de flux (musique qui
    // s'arrête) — seuls un flux nouveau ou un changement d'état valent réveil.
    Process {
        id: surveille
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: ligne => {
                const l = String(ligne || "")
                if (l.indexOf("sink-input") < 0) return
                racine.majFlux()
                if (l.indexOf("'remove'") >= 0) return
                if (racine.veille) racine.reveiller(false)
            }
        }
        onExited: { if (racine.actif) { relanceSurveille.restart() } }
    }

    Timer {
        id: relanceSurveille
        interval: 5000
        onTriggered: { if (!surveille.running) surveille.running = true }
    }

    // 10 s de silence franc avant de dormir : un blanc entre deux morceaux ne
    // doit pas couper la capture.
    Timer {
        id: silenceDodo
        interval: 10000
        repeat: false
        onTriggered: racine.dormir()
    }

    // Écoute de contrôle périodique en veille : 3 s de capture toutes les 20 s.
    Timer {
        id: sonde
        interval: 20000
        repeat: true
        running: false
        onTriggered: if (racine.veille) racine.reveiller(true)
    }

    // Fin d'une écoute de contrôle : sans la moindre activité, on rendort.
    Timer {
        id: finSonde
        interval: 3000
        repeat: false
        onTriggered: {
            if (racine.veille || racine.activiteVue) return
            racine.dormir()
        }
    }

    function dormir() {
        if (!racine.actif || racine.veille) return
        racine.veille = true
        racine.etat = "veille"
        silenceDodo.stop()
        finSonde.stop()
        if (scope.running) scope.running = false
        if (barres.running) barres.running = false
        sonde.restart()
    }

    function reveiller(provisoire) {
        if (!racine.actif || !racine.veille) return
        racine.veille = false
        racine.activiteVue = false
        sonde.stop()
        silenceDodo.restart()
        // Le redémarrage est différé de 250 ms : après un `running = false`,
        // Quickshell garde `running` à vrai le temps que le processus meure, et
        // un `running = true` dans cet intervalle ne relance rien du tout — le
        // visualiseur restait alors muet jusqu'au prochain cycle (vécu).
        demarrageDiffere.restart()
        if (provisoire) finSonde.restart()
    }

    // Appelée à chaque trame : c'est ici que se décide le passage en veille.
    function noterTrame(silencieux) {
        if (silencieux) return
        racine.activiteVue = true
        finSonde.stop()
        silenceDodo.restart()
    }

    // ── trames ──────────────────────────────────────────────────────────────
    // « F seq rms peak flags min0 max0 min1 max1 … », amplitudes 0..255 avec
    // 128 pour le silence. On ne relit que ce dont le dessin a besoin.
    function trameScope(ligne) {
        if (racine.veille) return
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
        racine.silence = (flags & 1) === 1 || racine.estFiltre()
        racine.seq = Number(t[1]) || (racine.seq + 1)
        racine.etat = "run"
        racine.noterTrame(racine.silence)
    }

    // cava : une ligne par trame, « 12;40;8;… » sur 0..100.
    function trameCava(ligne) {
        if (racine.veille) return
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
        racine.silence = somme < 0.02 || racine.estFiltre()
        racine.seq = racine.seq + 1
        racine.etat = "run"
        racine.noterTrame(racine.silence)
    }

    // ── conduite des processus ──────────────────────────────────────────────
    function arreter() {
        relance.stop()
        sonde.stop()
        silenceDodo.stop()
        finSonde.stop()
        racine.veille = false
        racine.activiteVue = false
        if (scope.running) scope.running = false
        if (barres.running) barres.running = false
        racine.hauteurs = []
        racine.bas = []
        racine.silence = true
        racine.etat = "idle"
    }

    function demarrer() {
        if (!racine.actif) { racine.arreter(); return }
        // Le balayage des restes doit être fini : sinon il pourrait tuer le
        // processus qu'on vient de lancer.
        if (balayage.running) { relance.restart(); return }
        if (racine.style === "barres") {
            if (barres.running) return
            racine.etat = "run"
            barres.running = true
            silenceDodo.restart()      // sans son, on doit pouvoir rendormir
            return
        }
        // « onde » : il faut le binaire compilé avant tout.
        racine.majFlux()
        if (racine.binaire === "") {
            if (!compil.running) { racine.etat = "prepare"; compil.running = true }
            return
        }
        if (scope.running) return
        racine.etat = "run"
        scope.running = true
        silenceDodo.restart()
    }

    function rearmer() {
        racine.arreter()
        // Même raison que dans reveiller() : après un arrêt, `running` reste
        // vrai un instant côté Quickshell, et un démarrage immédiat ne relance
        // rien. Chaque réglage du panneau passe par ici.
        if (racine.actif) demarrageDiffere.restart()
    }

    Component.onCompleted: {
        balayage.running = true
        racine.lireRegistre()
    }
}
