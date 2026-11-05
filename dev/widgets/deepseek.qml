import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit « not defined ».
import ".."
import Quickshell
import Quickshell.Io

// DEEPSEEK — solde de l'API, pour savoir quand remettre des fonds.
//
// Les données viennent de core/deepseek_service.py (GET /user/balance), lancé
// par un Process : c'est le patron des autres widgets, un script Python qui rend
// une ligne de JSON. L'API publique ne donne que le solde — pas de pourcentage
// de quota ni d'historique — donc c'est le solde qui s'affiche, avec une alerte
// visuelle quand il devient bas.
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

    property var solde: ({})
    property bool loaded: false

    readonly property bool ok: loaded && solde && solde.ok === true
    readonly property real total: root.ok ? Number(solde.total) : 0
    // Seuil d'alerte : sous 5 unités (¥ ou $), on ne tient plus longtemps.
    readonly property bool bas: root.ok && root.total < 5

    // Minutes entre deux requêtes, réglables par widget (`refresh_min`).
    readonly property int refreshMin: {
        const v = Number(options && options.refresh_min)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    readonly property string symbole: {
        if (!root.ok) return ""
        if (solde.currency === "CNY") return "¥"
        if (solde.currency === "USD") return "$"
        return ""
    }

    function montant(valeur) {
        if (!root.ok) return "—"
        return root.symbole + Number(valeur).toFixed(2)
    }

    function refresh(force) {
        const args = ["python3", Quickshell.shellPath("core/deepseek_service.py")]
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
                    root.solde = JSON.parse(text.trim())
                } catch (e) {
                    root.solde = { ok: false, error: "réponse illisible" }
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
            glyph: "wallet"
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
                // Lisible sur un wallpaper clair sans ajouter de carte.
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: {
                    if (!root.loaded) return "…"
                    // Le service détaille la cause entre parenthèses ; à cette
                    // taille, seul le début tient et suffit à agir.
                    if (!root.ok) return String(root.solde.error || "solde indisponible").split(" (")[0]
                    if (!root.solde.available) return "solde épuisé · DeepSeek"
                    // « cached » veut dire « lu du cache de 5 minutes », pas
                    // « périmé » : seule une requête ratée pose stale_reason.
                    const perime = root.solde.stale_reason !== undefined
                    return (root.bas ? "à recharger" : "DeepSeek") + (perime ? " · valeur périmée" : "")
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
