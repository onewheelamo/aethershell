import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit « not defined ».
import ".."
import Quickshell
import Quickshell.Io

// OLLAMA CLOUD — solde restant et consommation des sept derniers jours.
//
// Les données viennent de core/ollama_service.py, qui interroge `ollama.com` et
// non le démon local : celui-ci ne connaît que les modèles installés, il n'a
// rien à dire sur un compte cloud. Deux chiffres, deux questions différentes :
// le montant restant (« combien puis-je encore dépenser ») et le coût des sept
// derniers jours (« à quel rythme ») — un solde seul ne dit pas s'il tiendra la
// semaine.
//
// L'enveloppe incluse du mois est consommée chez moi en ce moment même : le
// solde affiché est alors fait des seuls crédits achetés. C'est le service qui
// additionne les deux postes, le widget n'a qu'un nombre à montrer.
//
// Sans clé, le widget reste en place et dit « clé absente » plutôt que de
// disparaître : un widget qui s'évapore ne dit pas qu'il manque une clé.
Item {
    id: root
    property var options: ({})

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte LLM partent
    // plus petit (85) parce qu'ils affichent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 0.85
    }
    property string widgetId: ""

    property var compte: ({})
    property bool loaded: false

    readonly property bool ok: loaded && compte && compte.ok === true
    readonly property real total: root.ok ? Number(compte.total) : 0
    // Seuil d'alerte : sous 1 $, à ~20 $ par semaine, il reste moins d'une heure.
    readonly property bool bas: root.ok && root.total < 1

    // Minutes entre deux requêtes, réglables par widget (`refresh_min`).
    readonly property int refreshMin: {
        const v = Number(options && options.refresh_min)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    readonly property string symbole: {
        if (!root.ok) return ""
        if (root.compte.currency === "USD") return "$"
        if (root.compte.currency === "CNY") return "¥"
        return ""
    }

    function montant(valeur) {
        if (!root.ok) return "—"
        return root.symbole + Number(valeur).toFixed(2)
    }

    // « 21.03 $ sur 7 j » — le coût est déjà arrondi par le service.
    readonly property string conso: {
        if (!root.ok || root.compte.usage_7d === null || root.compte.usage_7d === undefined)
            return ""
        return root.symbole + Number(root.compte.usage_7d).toFixed(2) + " sur 7 j"
    }

    function refresh(force) {
        const args = ["python3", Quickshell.shellPath("core/ollama_service.py")]
        if (force) args.push("--force")
        proc.command = args
        proc.running = true
    }

    Component.onCompleted: refresh(false)

    Timer {
        interval: root.refreshMin * 60000
        repeat: true
        running: true
        // La cadence choisie par l'utilisateur est la cadence réelle : sans
        // --force, le cache de 5 minutes du service ignorerait un réglage à 1 ou 2.
        onTriggered: root.refresh(true)
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.compte = JSON.parse(text.trim())
                } catch (e) {
                    root.compte = { ok: false, error: "réponse illisible" }
                }
                root.loaded = true
            }
        }
    }

    Row {
        id: contentRow
        spacing: Theme.space3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: "cloud"
            size: Math.round(Theme.widgetWeatherIcon * root.echelle)
            color: root.bas ? Theme.warn : Theme.accent
            opacityLevel: root.ok ? 1.0 : 0.45
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: root.montant(root.total)
                color: root.bas ? Theme.warn : Theme.fg
                font.pixelSize: Math.round(Theme.widgetTemp * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: {
                    if (!root.loaded) return "…"
                    if (!root.ok) return String(root.compte.error || "solde indisponible").split(" (")[0]
                    // « cached » veut dire « lu du cache de 5 minutes », pas
                    // « périmé » : seule une requête ratée pose stale_reason.
                    const perime = root.compte.stale_reason !== undefined
                    if (root.total <= 0) return "crédit épuisé · Ollama Cloud"
                    const rythme = root.conso
                    if (root.bas) return "à recharger" + (rythme ? " · " + rythme : "")
                    return (rythme || "Ollama Cloud") + (perime ? " · valeur périmée" : "")
                }
                color: Qt.alpha(Theme.fg, 0.78)
                font.pixelSize: Math.round(Theme.widgetLabel * root.echelle)
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }
        }
    }

    implicitWidth: contentRow.implicitWidth
    implicitHeight: contentRow.implicitHeight
}
