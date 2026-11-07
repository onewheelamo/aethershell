import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Fond « verre dépoli » autonome pour les surfaces du shell.
//
// Une surface Wayland ne peut pas lire ce qu'elle recouvre : le flou derrière
// une couche est fait par Hyprland (règle `blur` du namespace), et il ne sait
// pas flouter plus que ce que sa passe Kawase permet. Sous ~0,7 d'opacité, le
// texte des cartes se lit alors à travers les fenêtres. Ce composant redessine
// le fond d'écran **dans** la surface et le floute avec MultiEffect : le verre
// devient autonome, sans dépendre du compositeur.
//
// Ce qu'il ne fait pas : il ne montre pas les fenêtres. Le fond redessiné est
// celui du bureau nu ; à intensité 1 la surface ne laisse plus rien transparaître.
// L'intensité (0 = éteint) est donc l'arbitre entre lisibilité et transparence.
//
// Le cadrage est volontairement approximatif : `fillMode: PreserveAspectCrop`
// sur les bornes de la surface, pas un alignement pixel au pixel avec l'écran.
// Sous flou et à faible opacité, le décalage ne se voit pas ; un vrai recalage
// demanderait la position écran de chaque surface, que layer-shell ne donne pas
// au shell.
Item {
    id: racine

    // Intensité du verre : 0 = inactif (aucun coût de rendu), 1 = opaque.
    property real intensite: 0
    // Rayon des coins, pour épouser la carte qui l'accueille.
    property real rayon: 0
    // Force du flou : MultiEffect attend 0..1 (1 = flou maximal pour `blurMax`).
    property real flou: 0.85
    property int flouMax: 48
    // Chemin du fond d'écran courant : lu au démarrage auprès d'awww, avec un
    // repli sur le dossier de fonds si le démon ne répond pas.
    property string fond: ""

    readonly property bool actif: intensite > 0.01 && fond !== ""
    visible: actif
    opacity: intensite

    // awww (fork de swww) tient le fond courant ; `awww query` le dit par écran.
    Process {
        id: sonde
        command: ["awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).match(/currently displaying:.*?(?:image|video):\s*(\S+)/)
                if (m) racine.fond = m[1]
                else racine.fond = racine.fondDeRepli()
            }
        }
    }

    // Repli : premier fichier image du dossier de fonds du thème.
    function fondDeRepli() {
        const dir = Theme.wallpaperDir || ""
        return dir !== "" ? dir.replace(/\/?$/, "/") + "wallhaven-zy2doj.png" : ""
    }

    // Le fond est décodé une fois, à petite taille : le flou efface la
    // différence et le coût de décodage d'un 1920×1080 par surface serait payé
    // à chaque ouverture.
    Image {
        id: image
        anchors.fill: parent
        source: racine.fond !== "" ? "file://" + racine.fond : ""
        sourceSize.width: Math.max(160, Math.round(width / 4))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        blurEnabled: true
        blur: racine.flou
        blurMax: racine.flouMax
        saturation: 0.9
    }

    // Voile de couleur : sans lui, le verre tire vers les teintes du fond et
    // les cartes du thème se détachent mal.
    Rectangle {
        anchors.fill: parent
        radius: racine.rayon
        color: Qt.alpha(Theme.bg, 0.28)
    }

    Rectangle {
        anchors.fill: parent
        radius: racine.rayon
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.06)
    }
}
