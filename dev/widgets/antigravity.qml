import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit « not defined ».
import ".."
import Quickshell
import Quickshell.Io

// ANTIGRAVITY — quand le quota de l'abonnement Google AI Pro revient.
//
// Les données viennent de core/antigravity_service.py, qui lit les logs du CLI
// (le seul endroit où le quota est écrit — l'abonnement n'a pas d'API). Ce n'est
// donc pas un pourcentage : le service déduit l'heure de remise à zéro du
// dernier « RESOURCE_EXHAUSTED … Resets in 2h58m », et le widget fait défiler le
// temps qui reste.
//
// Deux fenêtres coexistent : une courte (~3 h) pour les modèles courants, une
// longue (~151 h, hebdomadaire) pour les modèles premium — c'est la plus
// lointaine qui commande, puisqu'elle bloque encore quand la courte est passée.
//
// Antigravity sert Gemini, Claude (Opus / Sonnet 5.5) et GPT-OSS sous le même
// abonnement : ce widget couvre donc les trois fournisseurs d'un coup, là où
// leurs API respectives exigeraient une clé d'administration.
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
    // Horloge locale : le décompte avance sans relancer le service.
    property real maintenant: Date.now() / 1000

    readonly property bool ok: loaded && compte && compte.ok === true
    readonly property bool epuise: root.ok && root.compte.state === "exhausted"
    readonly property real echeance: {
        if (!root.ok || !compte.windows) return 0
        let fin = 0
        for (let i = 0; i < compte.windows.length; i++)
            fin = Math.max(fin, Number(compte.windows[i].reset_at) || 0)
        return fin
    }
    readonly property real reste: Math.max(0, root.echeance - root.maintenant)

    readonly property int refreshMin: {
        const v = Number(options && options.refresh_min)
        return (v >= 1 && v <= 120) ? Math.round(v) : 5
    }

    // « 26 min », « 2h58 », « 2 j 02 » — le format suit la grandeur du délai.
    function duree(secondes) {
        if (!root.ok || secondes <= 0) return "—"
        const s = Math.floor(secondes)
        const jours = Math.floor(s / 86400)
        const heures = Math.floor((s % 86400) / 3600)
        const minutes = Math.floor((s % 3600) / 60)
        if (jours > 0) return jours + " j " + (heures < 10 ? "0" : "") + heures
        if (heures > 0) return heures + "h" + (minutes < 10 ? "0" : "") + minutes
        return minutes + " min"
    }

    function refresh(force) {
        const args = ["python3", Quickshell.shellPath("core/antigravity_service.py")]
        if (force) args.push("--force")
        proc.command = args
        proc.running = true
    }

    Component.onCompleted: refresh(false)

    Timer {
        interval: root.refreshMin * 60000
        repeat: true
        running: true
        onTriggered: root.refresh(true)
    }

    // Le décompte, lui, bat toutes les 30 s et ne coûte rien.
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.maintenant = Date.now() / 1000
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
                root.maintenant = Date.now() / 1000
            }
        }
    }

    Row {
        id: contentRow
        spacing: Theme.space3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            glyph: "rocket"
            size: Math.round(Theme.widgetWeatherIcon * root.echelle)
            color: root.epuise ? Theme.warn : Theme.accent
            opacityLevel: root.ok ? 1.0 : 0.45
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: {
                    if (!root.loaded) return "…"
                    if (!root.ok) return "—"
                    return root.epuise ? root.duree(root.reste) : "libre"
                }
                color: root.epuise ? Theme.warn : Theme.fg
                font.pixelSize: Math.round(Theme.widgetTemp * root.echelle)
                font.weight: Font.Light
                font.features: { "tnum": 1 }
                style: Text.Raised
                styleColor: Qt.alpha(Theme.bg, 0.55)
            }

            Text {
                text: {
                    if (!root.loaded) return "…"
                    if (!root.ok) return String(root.compte.error || "quota illisible").split(" (")[0]
                    return root.epuise ? "quota épuisé · Antigravity" : "Antigravity · quota libre"
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
