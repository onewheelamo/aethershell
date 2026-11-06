import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit « not defined ».
import ".."
import Quickshell
import Quickshell.Io

// WIDGETS DE COMPTE — un seul composant pour tous les fournisseurs.
//
// DeepSeek, Ollama Cloud et Antigravity ne mesurent pas la même chose (un solde,
// une enveloppe mensuelle, une échéance de quota), mais ils s'affichent pareil :
// un chiffre en grand, une ligne en petit. Ce composant ne connaît donc aucun
// fournisseur : il rend le contrat que le service Python lui donne
// (core/llm_contrat.py) et déduit lequel lancer de son propre id — « deepseek-3 »
// → deepseek — que le shell pose déjà sur chaque widget chargé. Ajouter un
// fournisseur, c'est un service et une entrée dans llm_providers.json ; aucune
// ligne de QML, et le réglage de taille de texte n'existe qu'ici.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    // Le fournisseur vient de l'id (« ollama-4 » → ollama). L'option `provider`
    // n'existe que pour un cas légitime : deux widgets sur le même fournisseur,
    // avec un id qui ne dit plus rien.
    readonly property string provider: {
        const p = String((options && options.provider) || "").trim()
        if (p !== "") return p
        return String(root.widgetId || "").split("-")[0]
    }

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte partent plus
    // petit (85) parce qu'ils empilent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 0.85
    }

    // Hauteur d'une ligne de tableau, un cran sous les libellés du thème : le
    // tableau doit tenir sur cinq lignes sans manger le bureau.
    readonly property int tailleLigne: Math.max(8, Math.round(Theme.widgetLabel * 0.86 * root.echelle))

    // Hauteur d'une cellule du tableau des quotas : elle fixe le pas des quatre
    // colonnes, y compris quand une cellule ne porte rien.
    //
    // Mesuré (sonde à quatre variantes, mêmes données, une échéance vide) : une
    // cellule dont `text` est la chaîne vide est comptée **zéro** par le
    // positionneur, qui ne se rattrape jamais — les suivantes remontent d'une
    // ligne et les dates se retrouvent en face du mauvais modèle. Une `height`
    // explicite n'y change rien (la mesure reste 0,0,15 pour des cellules de
    // 15 px). Ce qui corrige est de ne **jamais** écrire une chaîne vide : une
    // espace garde la ligne (mesure 0,15,30, comme une colonne sans vide).
    readonly property int hauteurLigne: Math.round(root.tailleLigne * 1.35)

    // Dans le widget fusionné, plusieurs comptes se suivent : l'icône ne suffit
    // pas à dire de quel service parle un bloc, d'où un en-tête facultatif qui
    // reprend le nom renvoyé par le service (« Ollama Cloud »).
    readonly property bool entete: !!(options && options.entete === true)
    readonly property string titre: (donnees && donnees.fournisseur)
                                    ? String(donnees.fournisseur) : ""

    property var donnees: ({})
    property bool loaded: false
    // Horloge : les décomptes avancent sans relancer le service.
    property real maintenant: Date.now() / 1000
    // Évite de relancer le service à chaque battement une fois l'échéance passée.
    property bool relanceFaite: false

    readonly property bool ok: root.loaded && donnees && donnees.ok === true
    readonly property var mesures: (root.ok && donnees.mesures) ? donnees.mesures : []
    readonly property bool alerte: root.ok && donnees.alerte === true

    // Certains services décrivent un tableau plutôt que deux lignes : un modèle
    // par ligne, sa tranche et ce qui lui reste (Antigravity). Le pied garde ce
    // qui ne se lit pas dans les lignes (réouverture, fraîcheur, palier).
    readonly property var lignes: (root.ok && donnees.lignes && donnees.lignes.length)
                                  ? donnees.lignes : []
    readonly property bool enTableau: lignes.length > 0
    readonly property string pied: {
        if (!enTableau) return ""
        const morceaux = []
        for (let i = 0; i < mesures.length; i++) {
            const p = root.phrase(mesures[i])
            if (p !== "") morceaux.push(p)
        }
        return morceaux.join(" · ")
    }

    // Première mesure : la grande ligne. Son échéance, si elle est encore à venir,
    // remplace la valeur et défile toute seule.
    readonly property var principale: mesures.length > 0 ? mesures[0] : ({})
    // Deux horodatages, deux rôles : `fin` remplace la valeur par un décompte,
    // `releve` ne s'affiche pas et sert seulement à relancer le service au bon
    // moment (une valeur en pourcentage change à l'échéance, mais reste un
    // pourcentage : on ne l'efface pas par un compte à rebours).
    readonly property real echeance: Number(principale.fin) || 0
    readonly property real releve: {
        let prochain = 0
        for (let i = 0; i < mesures.length; i++) {
            const t = Number(mesures[i].releve) || 0
            if (t > root.maintenant && (prochain === 0 || t < prochain)) prochain = t
        }
        return prochain
    }
    readonly property bool aRebours: root.echeance > root.maintenant

    readonly property int refreshMin: {
        const v = Number(options && options.refresh_min)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    // « 26 min », « 2h58 », « 2 j 02 » — même règle que côté Python, pour que la
    // valeur reçue et le décompte local s'écrivent pareil.
    function duree(secondes) {
        const s = Math.max(0, Math.floor(secondes))
        const jours = Math.floor(s / 86400)
        const heures = Math.floor((s % 86400) / 3600)
        const minutes = Math.floor((s % 3600) / 60)
        if (jours > 0) return jours + " j " + (heures < 10 ? "0" : "") + heures
        if (heures > 0) return heures + "h" + (minutes < 10 ? "0" : "") + minutes
        return minutes + " min"
    }

    // Une mesure réduite à sa phrase : « session libre », « $21.03 sur 7 j »,
    // « libre depuis 1 h 12 ». Les parties vides sont retirées, pas remplacées.
    function phrase(m) {
        if (!m) return ""
        // Phrase déjà composée par le service : certaines mesures ne s'écrivent
        // pas « valeur libelle » (« 5 h · Gemini 96 % »).
        if (String(m.texte || "") !== "") return String(m.texte)
        const parties = []
        if (String(m.valeur || "") !== "") parties.push(String(m.valeur))
        if (String(m.libelle || "") !== "") parties.push(String(m.libelle))
        // Horodatage passé : « reset hebdo il y a 1 h 12 ». Il a fallu un champ
        // à part parce que la mesure n'est pas une valeur mais un événement daté.
        const depuis = Number(m.depuis) || 0
        if (depuis > 0 && depuis < root.maintenant)
            parties.push("il y a " + root.duree(root.maintenant - depuis))
        return parties.join(" ")
    }

    readonly property string grande: {
        if (!root.loaded) return "…"
        if (!root.ok) return "—"
        if (root.aRebours) return root.duree(root.echeance - root.maintenant)
        return String(principale.valeur || "—")
    }

    // La petite ligne : les mesures suivantes, ou le libellé de la première.
    readonly property string petite: {
        if (!root.loaded) return "…"
        if (!root.ok) return String((donnees && donnees.error) || "indisponible").split(" (")[0]
        let texte = ""
        // Le libellé de la grande mesure porte son contexte (« hebdo · Claude ») :
        // sans lui, un « 0 % » ne dit pas de quelle fenêtre il parle.
        const tete = String(principale.libelle || "")
        if (mesures.length > 1) {
            const suivantes = []
            for (let i = 1; i < mesures.length; i++) {
                const p = root.phrase(mesures[i])
                if (p !== "") suivantes.push(p)
            }
            texte = suivantes.join(" · ")
            if (texte !== "" && tete !== "") texte = tete + " · " + texte
        }
        if (texte === "") texte = tete
        // « cached » veut dire « lu du cache », pas « faux » : seule une requête
        // ratée pose stale_reason, et c'est elle qu'il faut signaler.
        // Avec l'en-tête, le nom du service est déjà écrit au-dessus : le
        // répéter en dessous ne dit rien de plus (« DeepSeek » puis « DeepSeek »,
        // ou « à recharger · Ollama Cloud »). On retire le seul segment qui
        // répète ce nom, le reste de la ligne est conservé.
        if (root.entete && texte !== "") {
            const morceaux = texte.split(" · ")
            const gardes = []
            for (let i = 0; i < morceaux.length; i++) {
                const m = morceaux[i].trim()
                if (m !== "" && m !== root.titre) gardes.push(m)
            }
            texte = gardes.join(" · ")
        }
        if (donnees && donnees.stale_reason !== undefined)
            texte += (texte === "" ? "" : " · ") + "périmé"
        return texte
    }

    function refresh(force) {
        const args = ["python3", Quickshell.shellPath("core/" + root.provider + "_service.py")]
        if (force) args.push("--force")
        proc.command = args
        proc.running = true
    }

    // Le loader pose `options` et `widgetId` *après* la création de l'item :
    // `Component.onCompleted` peut donc tomber avant que le fournisseur soit
    // connu, et la commande partait sur `core/_service.py` (sortie vide, donc
    // « réponse illisible »). On relance dès que le fournisseur apparaît, quel
    // que soit l'ordre — et on ne lance rien tant qu'il est vide.
    onProviderChanged: if (root.provider !== "") root.refresh(false)
    Component.onCompleted: if (root.provider !== "") root.refresh(false)

    Timer {
        interval: root.refreshMin * 60000
        repeat: true
        running: true
        // La cadence choisie par l'utilisateur est la cadence réelle : sans
        // --force, le cache du service ignorerait un réglage à 1 ou 2 minutes.
        onTriggered: root.refresh(true)
    }

    // Le décompte bat toutes les 30 s et ne coûte rien. Quand l'échéance tombe,
    // une seule relance est demandée : c'est le service qui sait si le quota est
    // réellement revenu, le widget ne fait que cesser d'afficher un zéro.
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            root.maintenant = Date.now() / 1000
            // L'échéance affichée est tombée, ou une valeur doit changer : une
            // seule relance, c'est le service qui sait ce qu'il en est ensuite.
            const bascule = root.echeance > 0 && root.maintenant >= root.echeance
            const change = root.echeance === 0 && root.releve > 0
                           && root.maintenant >= root.releve
            if ((bascule || change) && !root.relanceFaite) {
                root.relanceFaite = true
                root.refresh(true)
            }
        }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.donnees = JSON.parse(text.trim())
                } catch (e) {
                    root.donnees = { ok: false, error: "réponse illisible" }
                }
                root.loaded = true
                root.relanceFaite = false
                root.maintenant = Date.now() / 1000
            }
        }
    }

    Column {
        id: enveloppe
        spacing: Math.round(6 * root.echelle)

        Text {
            visible: root.entete && text !== ""
            text: root.titre
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Math.round(Theme.widgetLabel * 0.78 * root.echelle)
            font.letterSpacing: 0.4
            style: Text.Raised
            styleColor: Qt.alpha(Theme.bg, 0.55)
        }

    Row {
        id: contentRow
        visible: !root.enTableau
        spacing: Theme.space3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: (root.ok && donnees.icone) ? String(donnees.icone) : "wallet"
            size: Math.round(Theme.widgetWeatherIcon * root.echelle)
            color: root.alerte ? Theme.warn : Theme.accent
            opacityLevel: root.ok ? 1.0 : 0.45
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: root.grande
                color: root.alerte ? Theme.warn : Theme.fg
                font.pixelSize: Math.round(Theme.widgetTemp * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                // Lisible sur un wallpaper clair sans ajouter de carte.
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: root.petite
                visible: text !== ""
                color: Qt.alpha(Theme.fg, 0.78)
                font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }
    }

    Row {
        id: tableauRow
        visible: root.enTableau
        spacing: Theme.space3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: (root.ok && donnees.icone) ? String(donnees.icone) : "rocket"
            size: Math.round(Theme.widgetWeatherIcon * root.echelle)
            color: root.alerte ? Theme.warn : Theme.accent
            opacityLevel: root.ok ? 1.0 : 0.45
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Row {
                spacing: Math.round(9 * root.echelle)

                // Trois colonnes plutôt qu'une grille : chacune prend la largeur
                // de son plus long texte, donc les pourcentages s'alignent sans
                // qu'on ait à mesurer quoi que ce soit.
                Column {
                    Repeater {
                        model: root.lignes
                        Text {
                            text: String(modelData.nom || " ")
                            color: Theme.fg
                            font.pixelSize: root.tailleLigne
                            height: root.hauteurLigne
                            verticalAlignment: Text.AlignVCenter
                            style: Text.Raised
                            styleColor: Qt.alpha(Theme.bg, 0.55)
                        }
                    }
                }

                Column {
                    Repeater {
                        model: root.lignes
                        Text {
                            text: String(modelData.tranche || " ")
                            color: Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: root.tailleLigne
                            height: root.hauteurLigne
                            verticalAlignment: Text.AlignVCenter
                            style: Text.Raised
                            styleColor: Qt.alpha(Theme.bg, 0.55)
                        }
                    }
                }

                Column {
                    Repeater {
                        model: root.lignes
                        Text {
                            text: String(modelData.valeur || " ")
                            color: modelData.alerte ? Theme.warn : Theme.fg
                            font.pixelSize: root.tailleLigne
                            height: root.hauteurLigne
                            verticalAlignment: Text.AlignVCenter
                            font.features: { "tnum": 1 }
                            style: Text.Raised
                            styleColor: Qt.alpha(Theme.bg, 0.55)
                        }
                    }
                }

                // Échéance propre à la ligne : « 20:06 » aujourd'hui, la date
                // complète au-delà. Chaque modèle porte la sienne, y compris ceux
                // dont la tranche n'est pas bloquée.
                Column {
                    Repeater {
                        model: root.lignes
                        Text {
                            text: String(modelData.echeance || " ")
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: root.tailleLigne
                            height: root.hauteurLigne
                            verticalAlignment: Text.AlignVCenter
                            font.features: { "tnum": 1 }
                            style: Text.Raised
                            styleColor: Qt.alpha(Theme.bg, 0.55)
                        }
                    }
                }
            }

            Text {
                text: root.pied
                visible: text !== ""
                color: Qt.alpha(Theme.fg, 0.7)
                font.pixelSize: Math.round(Theme.widgetLabel * 0.8 * root.echelle)
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }
    }
    }

    implicitWidth: enveloppe.implicitWidth
    implicitHeight: enveloppe.implicitHeight
}
