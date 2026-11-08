import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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
// Le cadrage suit l'écran, pas la surface : le fond est dessiné à la taille de
// l'écran puis décalé de l'inverse de la position de la surface. Sans cela un
// îlot de barre montrait le **centre** du fond — un morceau sans rapport avec ce
// qu'il recouvre — et la coupure se lisait au bord de l'îlot comme une couture
// de couleur.
//
// `origineEcran` est la position de la fenêtre sur l'écran. Elle vaut (0,0) pour
// la barre (pleine largeur, en haut) ; les surfaces flottantes doivent la
// renseigner, layer-shell ne la leur donne pas.
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

    // Position de la fenêtre sur l'écran (0,0 pour la barre) et taille de
    // l'écran : c'est ce qui recale le fond redessiné sur le vrai.
    property point origineEcran: Qt.point(0, 0)
    readonly property size ecran: Qt.size(racine.Screen.width, racine.Screen.height)
    readonly property point positionEcran: {
        const p = racine.mapToItem(null, 0, 0)
        return Qt.point(Math.round(p.x + origineEcran.x), Math.round(p.y + origineEcran.y))
    }

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

    // ── Fond recadré à l'écran, quand il existe ───────────────────────────────
    // `parallaxe_layers.py` écrit `fond-ecran.png` (1920×1080, même cadrage que
    // le démon de fond) à côté des calques. À l'échelle 1 il n'y a plus ni
    // réduction ni recadrage par Qt : le fond redessiné tombe au pixel près sur
    // celui du compositeur, et la couture de teinte au bord des îlots disparaît.
    // Sans ce fichier on retombe sur l'ancien chemin (décodage réduit + découpe).
    readonly property string nomFond: {
        const p = String(racine.fond)
        if (p === "") return ""
        return p.split("/").pop().replace(/\.[^.]+$/, "")
    }
    readonly property string racineFonds: {
        let d = String(Theme.wallpaperDir || "")
        const home = Quickshell.env("HOME") || ""
        if (d.startsWith("$HOME")) d = home + d.slice(5)
        else if (d.startsWith("~")) d = home + d.slice(1)
        return d.replace(/\/?$/, "/")
    }
    readonly property string cheminEcran: racine.nomFond === "" ? ""
        : racine.racineFonds + "profondeur/" + racine.nomFond + "/fond-ecran.png"
    property bool ecranPret: false

    Image {
        id: imageEcran
        anchors.fill: parent
        source: racine.cheminEcran !== "" ? "file://" + racine.cheminEcran : ""
        // La fenêtre du fond à montrer se choisit par `sourceClipRect`, pas en
        // déplaçant l'image : MultiEffect aligne la texture de sa source sur son
        // propre coin, donc une image décalée sortait déformée (le fond de la
        // barre montrait la mauvaise région).
        // À l'échelle 1 (fond-ecran.png fait exactement la taille de l'écran), la
        // découpe est au pixel : aucun rééchantillonnage, donc plus de couture.
        readonly property point coin: Qt.point(
            Math.max(0, Math.min(racine.ecran.width - width, racine.positionEcran.x)),
            Math.max(0, Math.min(racine.ecran.height - height, racine.positionEcran.y)))
        sourceClipRect: Qt.rect(coin.x, coin.y, width, height)
        fillMode: Image.Pad
        asynchronous: true
        cache: true
        visible: false
        layer.enabled: true
        onStatusChanged: racine.ecranPret = (status === Image.Ready)
    }

    // Le fond est décodé une fois, à petite taille : le flou efface la
    // différence et le coût de décodage d'un 1920×1080 par surface serait payé
    // à chaque ouverture.
    // Cadre découpé : le fond y est posé à la taille de l'écran, décalé pour que
    // le pixel sous la surface soit le bon. Le flou est appliqué au cadre
    // (`layer.effect`), pas à une source recadrée sur la surface : un MultiEffect
    // étirerait son entrée sur ses propres bornes et perdrait le décalage.
    // Le fond est pris **sous la surface** : `sourceClipRect` découpe la bonne
    // fenêtre de l'image d'écran, donc le fond redessiné est celui qu'on
    // recouvre et non le centre de l'image. Le rendu reste borné à la surface,
    // ce qui évite le rectangle flouté qui dépassait des pastilles arrondies.
    Image {
        id: image
        anchors.fill: parent
        source: racine.fond !== "" ? "file://" + racine.fond : ""
        sourceSize.width: Math.max(160, Math.round(width / 4))
        // `sourceClipRect` s'exprime dans les pixels de l'image **décodée**, pas
        // ceux de l'écran : sans ce rapport, la fenêtre demandée sortait de
        // l'image pour les surfaces de droite et Qt servait un coin sombre —
        // visible dès qu'on montait le flou interne.
        readonly property real rapport: width > 0 ? sourceSize.width / racine.ecran.width : 0
        sourceClipRect: Qt.rect(racine.positionEcran.x * rapport,
                                racine.positionEcran.y * rapport,
                                width * rapport,
                                height * rapport)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        // Le fond à l'échelle 1 d'abord ; le décodage réduit seulement s'il
        // manque (fond jamais découpé en calques).
        source: racine.ecranPret ? imageEcran : image
        blurEnabled: true
        blur: racine.flou
        blurMax: racine.flouMax
        saturation: 1.0
    }

    // Voile de couleur : sans lui, le verre tire vers les teintes du fond et
    // les cartes du thème se détachent mal.
    Rectangle {
        anchors.fill: parent
        radius: racine.rayon
        // Le voile s'efface à mesure que le verre devient opaque : à 100 % le
        // fond est déjà flouté et lisible, et plus rien n'assombrit la teinte.
        color: Qt.alpha("#000000", 0.15 * (1.0 - Math.min(1.0, racine.intensite)))
    }

    Rectangle {
        anchors.fill: parent
        radius: racine.rayon
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.06)
    }
}
