import QtQuick
import QtQuick.Shapes
import "."

// ══════════════════════════════════════════════════════════════════════
// SURFACE FLOUTÉE UNIFIÉE (SurfaceFloutee.qml)
// ══════════════════════════════════════════════════════════════════════
// Rendu par `Shape.CurveRenderer` (anticrénelage analytique par fragment shader,
// sans facettes polygonales ni FBO MSAA) pour des arrondis nets à toute taille.
// Le flou d'arrière-plan est assuré exclusivement par le compositeur Hyprland
// (règle `shell-blur`).
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property real rayon: Theme.pillRadius
    property color teinte: Theme.surfaceBg
    property color bordureCouleur: Theme.accent
    property int bordureLargeur: Theme.barBorder ? 1 : 0
    property bool actif: true

    Shape {
        id: forme
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: width > 0 && height > 0

        readonly property real demiTrait: root.bordureLargeur > 0 ? root.bordureLargeur * 0.5 : 0
        readonly property real x0: demiTrait
        readonly property real y0: demiTrait
        readonly property real w: Math.max(0, width - root.bordureLargeur)
        readonly property real h: Math.max(0, height - root.bordureLargeur)
        readonly property real r: Math.max(0, Math.min(root.rayon, w * 0.5, h * 0.5))

        ShapePath {
            fillColor: root.teinte
            strokeColor: root.bordureLargeur > 0 ? root.bordureCouleur : "transparent"
            strokeWidth: root.bordureLargeur > 0 ? root.bordureLargeur : -1
            joinStyle: ShapePath.RoundJoin

            Behavior on fillColor { ColorAnimation { duration: 180 } }
            Behavior on strokeColor { ColorAnimation { duration: 180 } }

            startX: forme.x0 + forme.r
            startY: forme.y0

            PathLine { x: forme.x0 + forme.w - forme.r; y: forme.y0 }
            PathArc {
                x: forme.x0 + forme.w
                y: forme.y0 + forme.r
                radiusX: forme.r
                radiusY: forme.r
                useLargeArc: false
                direction: PathArc.Clockwise
            }
            PathLine { x: forme.x0 + forme.w; y: forme.y0 + forme.h - forme.r }
            PathArc {
                x: forme.x0 + forme.w - forme.r
                y: forme.y0 + forme.h
                radiusX: forme.r
                radiusY: forme.r
                useLargeArc: false
                direction: PathArc.Clockwise
            }
            PathLine { x: forme.x0 + forme.r; y: forme.y0 + forme.h }
            PathArc {
                x: forme.x0
                y: forme.y0 + forme.h - forme.r
                radiusX: forme.r
                radiusY: forme.r
                useLargeArc: false
                direction: PathArc.Clockwise
            }
            PathLine { x: forme.x0; y: forme.y0 + forme.r }
            PathArc {
                x: forme.x0 + forme.r
                y: forme.y0
                radiusX: forme.r
                radiusY: forme.r
                useLargeArc: false
                direction: PathArc.Clockwise
            }
        }
    }
}
