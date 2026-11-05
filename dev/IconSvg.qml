import QtQuick
import QtQuick.Shapes

// ICON SVG — les icônes qui n'existent pas dans la fonte Nerd.
//
// La table `Icon.qml` ne couvre que Nerd Font : ni CPU, ni GPU, ni thermomètre.
// Plutôt que d'y ajouter des codepoints au hasard (un glyphe absent rend une
// icône vide, sans erreur), ces dessins sont décrits ici en SVG et rendus par
// QtQuick.Shapes : monochromes, redimensionnables, teintés par `couleur`, et
// nets à toutes les échelles — contrairement à une fonte, un tracé ne dépend
// pas d'un jeu de glyphes installé.
//
//   IconSvg { nom: "gpu"; size: 14; couleur: Theme.accent }
//
// Grille de 24 × 24, tracé seul (pas de remplissage) : l'épaisseur du trait
// suit la taille, donc une icône de 11 px reste lisible.
Item {
    id: root

    property string nom: ""
    property real size: Theme.iconSm
    property color couleur: Theme.fg
    property real opacite: 1.0
    /// Épaisseur du trait, **en pixels de rendu** : elle est divisée par le
    /// facteur d'échelle pour rester constante. Exprimée dans la grille 24 × 24,
    /// une icône de 14 px aurait un trait de 0,9 px, gris et mou.
    property real trait: 1.25

    implicitWidth: Math.ceil(size)
    implicitHeight: Math.ceil(size)
    opacity: opacite

    readonly property real k: size / 24

    // ── tracés ───────────────────────────────────────────────────────────────
    // Chaque dessin tient dans 24 × 24 et laisse 3 px de marge : deux icônes
    // côte à côte gardent la même respiration optique.
    readonly property var chemins: ({
        // Tracés volontairement pauvres : à 14 px, un détail de plus est une
        // tache. Boîtier et broches suffisent à lire « puce ».
        "cpu": "M8 4v2 M16 4v2 M8 18v2 M16 18v2 M4 8h2 M4 16h2 M18 8h2 M18 16h2"
             + " M7 6h10v12H7z",
        // Barrette : le rectangle et les contacts du bas.
        "ram": "M3 8h18v7H3z M5 15v3 M9 15v3 M12 15v3 M16 15v3 M19 15v3",
        // Carte graphique : carte, ventilateur, trois broches.
        "gpu": "M4 6h16v9H4z M12 8a3 3 0 1 0 0 6a3 3 0 1 0 0-6z"
             + " M8 15v3 M12 15v3 M16 15v3",
        // Thermomètre : tube et réservoir.
        "temp": "M12 4a1.8 1.8 0 0 1 1.8 1.8v8a3.4 3.4 0 1 1-3.6 0v-8A1.8 1.8 0 0 1 12 4z"
              + " M12 17.2a1.4 1.4 0 1 0 0.01 0",
        // Disque : plateau avec son axe.
        "disque": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0"
                + " M12 9.5a2.5 2.5 0 1 0 0 5a2.5 2.5 0 1 0 0-5z"
                + " M12 3v1.5 M12 19.5V21",
        // Réseau : trois nœuds reliés.
        "reseau": "M12 3.5h0 M12 6.5v3 M5 14.5h14 M12 9.5v5"
                + " M12 4.5a2 2 0 1 0 0.01 0"
                + " M5 16.5a2 2 0 1 0 0.01 0 M19 16.5a2 2 0 1 0 0.01 0"
    })

    readonly property string chemin: chemins[nom] || ""

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.k; yScale: root.k }

        ShapePath {
            strokeColor: root.couleur
            fillColor: "transparent"
            strokeWidth: root.trait / Math.max(0.05, root.k)
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.chemin }
        }
    }
}
