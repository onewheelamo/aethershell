import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris

// ════════════════════════════════════════════════════════════════════════════
// PANNEAU MÉDIA — le popup MPRIS, sorti de island_center.qml
// ════════════════════════════════════════════════════════════════════════════
// L'applet « musique » l'ouvre en posant Theme.activePopup = "media" ; il se
// dessine sous l'îlot qui l'héberge (`ancre`). Rien de la barre ici : ce fichier
// ne connaît ni les applets, ni les îlots, seulement MPRIS et son propre état.
// ════════════════════════════════════════════════════════════════════════════

Item {
    id: panneau

    // Item de référence : l'applet qui porte ce panneau. `Applet.qml` le pose
    // juste après la création, d'où l'absence de `required` ; la fenêtre ne
    // s'affiche qu'une fois l'ancre connue et l'ouverture demandée.
    property Item ancre: null
    property bool ouvert: false
    // Compteur d'horloge : la barre de progression lit `player.position`, qui
    // n'est pas une propriété observable. Ce compteur la force à se réévaluer —
    // il n'était jamais déclaré, donc le minuteur levait « Cannot assign to
    // non-existent property » une fois par seconde et la barre restait figée.
    property int mediaProgressTick: 0
    // Emplacement de l'applet (« barre:place ») : c'est la barre qui décide de
    // quel côté le panneau s'ouvre.
    readonly property string ileAncre: (panneau.ancre && panneau.ancre.ile)
                                       ? String(panneau.ancre.ile) : ""

    // L'attrapeur de focus de l'îlot a besoin de la *fenêtre*, pas de
    // cet Item : les deux ne sont pas au même niveau d'imbrication.
    readonly property var surface: fenetre

    // Durée de lecture en m:ss — le panneau média est le seul à en avoir besoin.
    function formatPlaybackTime(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0
        const total = Math.floor(sec)
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" + s : String(s))
    }


    // ────────────────────────────────────────────────────────────────────────
    // SECTION 3: MPRIS MEDIA INTEGRATION
    // ────────────────────────────────────────────────────────────────────────
    // Live tracking of currently playing media & lecture position (toutes les 1s quand ouvert)
    property bool mediaPollTick: false
    Timer {
        interval: 1000
        running: panneau.ouvert
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            panneau.mediaPollTick = !panneau.mediaPollTick
            panneau.mediaProgressTick++
        }
    }

    // Tout lecteur ayant une piste, en lecture ou non. Il pilote le popup (sinon
    // une pause le refermerait) **et** la zone média de la pilule : lier celle-ci à
    // « en lecture » la faisait disparaître entre deux pistes, la pilule se
    // rétractait puis se rouvrait. La zone n'apparaissant qu'au survol, montrer
    // une piste en pause ne gêne pas.
    readonly property var mediaPlayer: {
        const _ = panneau.mediaPollTick
        const list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p) continue
            const ident = (p.identity || p.desktopEntry || p.dbusName || "").toLowerCase()
            // Ignore browsers (Firefox, Zen, Chrome, Chromium, Brave...) to avoid ads and video previews
            if (ident.indexOf("firefox") >= 0 || ident.indexOf("zen") >= 0
                || ident.indexOf("chromium") >= 0 || ident.indexOf("chrome") >= 0
                || ident.indexOf("brave") >= 0) {
                continue
            }
            if (p.trackTitle) return p
        }
        return null
    }

    readonly property var activeMediaInfo: {
        const p = panneau.mediaPlayer
        if (!p) return null
        const title = (p.trackTitle || "").trim()
        const artist = (p.trackArtist || p.trackAlbumArtist || "").trim()
        return {
            title: title,
            artist: artist,
            label: artist ? (artist + " — " + title) : title
        }
    }


    // Cliquer à côté referme le panneau. Armé après le map, et porté par le
    // panneau lui-même — même mécanique que le calendrier.
    //
    // `onRunningChanged` ne doit pas désarmer : ce Timer ne se répète pas, donc
    // il repasse `running` à false dès sa première échéance. Le laisser remettre
    // `attrapeurPret` à false désarmait l'attrapeur dans la même foulée, et le
    // panneau ne se refermait jamais au clic extérieur. Le désarmement se fait
    // sur la fermeture, dans `onOuvertChanged`.
    property bool attrapeurPret: false
    Timer {
        interval: 180
        running: panneau.ouvert
        onTriggered: panneau.attrapeurPret = true
    }
    onOuvertChanged: if (!panneau.ouvert) panneau.attrapeurPret = false

    readonly property var fenetresGrab: Theme.fenetresGrab(fenetre, panneau.ancre)
    HyprlandFocusGrab {
        active: panneau.ouvert && panneau.attrapeurPret
        windows: panneau.fenetresGrab
        onCleared: Theme.activePopup = ""
    }

    // Échap ferme le panneau, comme celui du calendrier : l'îlot qui héberge
    // l'ancre reçoit le clavier, la fenêtre du popup ne le prend jamais.
    Shortcut {
        sequence: "Escape"
        enabled: panneau.ouvert
        onActivated: Theme.activePopup = ""
    }

    // ────────────────────────────────────────────────────────────────────────
    // SECTION 7B: MEDIA POPUP (MPRIS CONTROLS)
    // ────────────────────────────────────────────────────────────────────────
    // Ouvre sous la pilule quand on clique la zone média. Les contrôles passent
    // directement par l'objet du joueur (Services.Mpris), sans process externe.
    PopupWindow {
        id: fenetre
        readonly property var player: panneau.mediaPlayer
        // Le lecteur disparaît (fermé, piste stoppée) : on referme le popup plutôt
        // que de laisser un grab de focus sans fenêtre.
        onPlayerChanged: {
            if (player === null && panneau.ouvert) Theme.activePopup = ""
        }
        readonly property real posNow: { panneau.mediaProgressTick; return player ? Math.max(0, player.position) : 0 }
        readonly property real durNow: player ? Math.max(0, player.length) : 0
        readonly property real ratio: durNow > 0 ? Math.min(1, posNow / durNow) : 0
        readonly property string artSource: {
            const u = player && player.trackArtUrl ? player.trackArtUrl : ""
            if (u === "") return ""
            // mpv-mpris sert la pochette en data: base64 ; d'autres lecteurs en
            // file:// ou https. Seul un chemin nu a besoin du préfixe.
            if (u.indexOf("file://") === 0 || u.indexOf("http") === 0
                || u.indexOf("data:") === 0 || u.indexOf("image://") === 0) return u
            return "file://" + u
        }

        anchor.item: panneau.ancre
        // Même règle que les popups d'applet : la barre qui porte l'applet donne
        // le côté. Sous la barre du haut, à côté d'une barre latérale, au-dessus
        // de la barre du bas.
        anchor.rect.x: Theme.ancrePopupX(panneau.ileAncre, panneau.ancre, implicitWidth, "centre")
        anchor.rect.y: Theme.ancrePopupY(panneau.ileAncre, panneau.ancre, implicitHeight)
        anchor.adjustment: PopupAdjustment.All
        implicitWidth: 360
        implicitHeight: mediaCol.implicitHeight + 28
        color: "transparent"
        visible: panneau.ouvert && player !== null && panneau.ancre !== null

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceBg
            radius: Theme.globalRadius
            border.color: Theme.accent
            border.width: 1

            Column {
                id: mediaCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 12

                Row {
                    width: parent.width
                    spacing: Theme.space3

                    Rectangle {
                        width: 80
                        height: 80
                        radius: 5
                        color: Theme.surfaceVariant
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: fenetre.artSource
                            visible: fenetre.artSource !== ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: fenetre.artSource === ""
                            glyph: "music"
                            size: Theme.iconLg
                            color: Theme.accentMuted
                            opacityLevel: 0.7
                        }
                    }

                    Column {
                        width: parent.width - 80 - Theme.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space1

                        Text {
                            width: parent.width
                            text: fenetre.player ? fenetre.player.trackTitle : ""
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: {
                                if (!fenetre.player) return ""
                                const artist = fenetre.player.trackArtist || fenetre.player.trackAlbumArtist || ""
                                const album = fenetre.player.trackAlbum || ""
                                if (artist && album) return artist + " · " + album
                                return artist || album
                            }
                            color: Theme.accentMuted
                            font.pixelSize: Theme.textSm
                            elide: Text.ElideRight
                        }
                    }
                }

                // Barre de progression : 3 px, même famille que l'OSD (2 px) mais
                // lisible à la taille du popup agrandi
                Item {
                    width: parent.width
                    height: 14

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 3
                        radius: 1
                        color: Theme.surfaceVariant

                        Rectangle {
                            width: parent.width * fenetre.ratio
                            height: parent.height
                            radius: 1
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }
                }

                Row {
                    width: parent.width

                    Text {
                        text: panneau.formatPlaybackTime(fenetre.posNow)
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.textXs
                        font.features: { "tnum": 1 }
                    }

                    Item { width: parent.width - 90; height: 1 }

                    Text {
                        text: "-" + panneau.formatPlaybackTime(fenetre.durNow - fenetre.posNow)
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Theme.textXs
                        font.features: { "tnum": 1 }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "previous"
                        size: Theme.iconLg
                        color: Theme.fg
                        opacityLevel: fenetre.player && fenetre.player.canGoPrevious ? 0.9 : 0.3

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: fenetre.player && fenetre.player.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (fenetre.player && fenetre.player.canGoPrevious) fenetre.player.previous()
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 34
                        radius: Theme.globalRadius
                        color: playMa.containsMouse ? Theme.surfaceVariant : "transparent"

                        Icon {
                            anchors.centerIn: parent
                            glyph: fenetre.player && fenetre.player.isPlaying ? "pause" : "play"
                            size: Theme.iconLg
                            color: Theme.accent
                            opacityLevel: fenetre.player && fenetre.player.canTogglePlaying ? 1 : 0.3
                        }

                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (fenetre.player && fenetre.player.canTogglePlaying) fenetre.player.togglePlaying()
                        }
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "next"
                        size: Theme.iconLg
                        color: Theme.fg
                        opacityLevel: fenetre.player && fenetre.player.canGoNext ? 0.9 : 0.3

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: fenetre.player && fenetre.player.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (fenetre.player && fenetre.player.canGoNext) fenetre.player.next()
                        }
                    }
                }
            }
        }
    }

}
