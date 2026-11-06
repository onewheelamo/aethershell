import QtQuick
// Les singletons du shell (Theme, Icon) sont déclarés dans le qmldir du dossier
// parent : sans cet import, un composant en sous-dossier les voit "not defined".
import ".."
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// MUSIQUE — lecteur permanent sur le bureau.
//
// Même source et mêmes contrôles que le popup média de l'îlot central : l'objet
// `Mpris.players` de Quickshell, filtrage des navigateurs (Firefox & co. déclarent
// un lecteur MPRIS pour leurs vidéos), précédent / lecture-pause / suivant.
//
// Deux exigences propres au widget :
//  - une pochette toujours affichée : MPRIS oublie tout quand le lecteur se ferme,
//    donc on mémorise la dernière vue (en mémoire de session) ;
//  - lecteur fermé, un clic sur play lance le programme (app_vars.json, clé
//    « Music ») puis la lecture dès qu'un lecteur MPRIS apparaît.
Item {
    id: root

    property var options: ({})

    // Échelle du texte, réglée par widget depuis le panneau (options.text_scale,
    // en pourcentage). 100 = taille du thème ; les widgets de compte LLM partent
    // plus petit (85) parce qu'ils affichent deux lignes de texte dense.
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    // Renseigné par main.qml : identité de l'entrée dans widgets.json.
    property string widgetId: ""

    // Dernière piste vue, pour garder une pochette et un titre quand le lecteur
    // disparaît. Volontairement en mémoire : pas d'état écrit sur disque.
    property string lastArt: ""
    property string lastName: ""
    property string lastArtist: ""
    property bool launching: false
    property int posTick: 0

    readonly property var browserHints: ["firefox", "zen", "chromium", "chrome",
                                         "brave", "vivaldi", "opera", "librewolf"]

    // Réglage du widget : un onglet qui joue une vidéo n'est pas de la musique.
    // Par défaut on ignore les navigateurs ; l'option permet de les suivre.
    readonly property bool ignorerNavigateurs: {
        const v = options ? options.ignorer_navigateurs : undefined
        if (v === undefined || v === null || v === "") return true
        return !(v === false || v === "false" || v === 0 || v === "0")
    }

    // Comme l'îlot central : on ignore les navigateurs, et on préfère le lecteur
    // qui joue réellement. Une piste en pause reste sélectionnée.
    readonly property var player: {
        const list = (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
        let paused = null
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!p || !p.trackTitle) continue
            const ident = (p.identity || p.desktopEntry || p.dbusName || "").toLowerCase()
            let isBrowser = false
            for (let k = 0; k < browserHints.length; k++) {
                if (ident.indexOf(browserHints[k]) >= 0) { isBrowser = true; break }
            }
            if (isBrowser && ignorerNavigateurs) continue
            if (p.isPlaying) return p
            if (!paused) paused = p
        }
        return paused
    }

    readonly property bool hasTrack: player !== null && !!player.trackTitle
    readonly property bool isPlaying: hasTrack && player.isPlaying

    readonly property real posNow: { posTick; return hasTrack ? Math.max(0, player.position) : 0 }
    readonly property real durNow: hasTrack ? Math.max(0, player.length) : 0
    readonly property real ratio: durNow > 0 ? Math.min(1, posNow / durNow) : 0

    // mpv-mpris sert la pochette en data:, d'autres en file:// ou https : seul un
    // chemin nu a besoin du préfixe.
    readonly property string artSource: {
        const u = hasTrack && player.trackArtUrl ? String(player.trackArtUrl) : ""
        if (u === "") return ""
        if (u.indexOf("file://") === 0 || u.indexOf("http") === 0
                || u.indexOf("data:") === 0 || u.indexOf("image://") === 0) return u
        return "file://" + u
    }

    readonly property string artistLabel: {
        if (!hasTrack) return lastArtist
        const artist = player.trackArtist || player.trackAlbumArtist || ""
        const album = player.trackAlbum || ""
        if (artist && album) return artist + " · " + album
        return artist || album
    }

    readonly property string titleLabel: hasTrack ? String(player.trackTitle)
                                                 : (lastName !== "" ? lastName : "Aucune lecture")
    readonly property string subtitleLabel: hasTrack ? artistLabel
        : (lastArtist !== "" ? lastArtist
                             : "Play pour lancer " + (Theme.program("Music") || "le lecteur"))

    readonly property string shownArt: artSource !== "" ? artSource : lastArt

    implicitWidth: 320
    implicitHeight: contentRow.implicitHeight

    // Mémorise la pochette et le libellé dès qu'une piste valide apparaît.
    onArtSourceChanged: {
        if (artSource === "") return
        lastArt = artSource
        lastName = String(player.trackTitle || "")
        lastArtist = artistLabel
    }

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0))
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" + r : String(r))
    }

    // `Quickshell.execDetached(["strawberry"])` ne lançait rien depuis ce widget :
    // le journal ne montrait aucune erreur et aucun processus. Un Process, comme
    // partout ailleurs dans le shell, est observable (`running`) et fonctionne.
    Process {
        id: launcherProc
    }

    function launchPlayer() {
        if (launching) return
        const prog = Theme.program("Music")
        if (prog === "") return
        launching = true
        launcherProc.command = [prog]
        launcherProc.running = true
        launchGiveUp.restart()
    }

    function togglePlayback() {
        if (hasTrack && player.canTogglePlaying) {
            player.togglePlaying()
            return
        }
        if (launching) return
        launchPlayer()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.hasTrack && root.isPlaying
        onTriggered: root.posTick++
    }

    // Le lecteur lancé met quelques centaines de ms à publier son MPRIS : on
    // surveille son apparition puis on démarre la lecture.
    Timer {
        interval: 400
        repeat: true
        running: root.launching
        onTriggered: {
            if (!root.player) return
            root.launching = false
            if (root.player.canTogglePlaying && !root.player.isPlaying)
                root.player.togglePlaying()
        }
    }

    // Abandon au bout de 12 s si rien ne s'est présenté (programme absent, crash).
    Timer {
        id: launchGiveUp
        interval: 12000
        onTriggered: root.launching = false
    }

    Row {
        id: contentRow
        spacing: Theme.space3

        // Pochette : toujours dessinée, celle du morceau courant ou la dernière vue.
        Rectangle {
            width: 60
            height: 60
            radius: Theme.globalRadius
            color: Theme.surfaceVariant
            clip: true

            Image {
                anchors.fill: parent
                source: root.shownArt
                visible: root.shownArt !== ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Icon {
                anchors.centerIn: parent
                visible: root.shownArt === ""
                glyph: "music"
                size: Math.round(Theme.iconLg * root.echelle)
                color: Theme.accentMuted
                opacityLevel: 0.7
            }
        }

        Column {
            width: root.implicitWidth - 60 - Theme.space3
            spacing: 3

            Text {
                width: parent.width
                text: root.titleLabel
                color: Theme.fg
                font.pixelSize: Math.round(Theme.textSm * root.echelle)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.subtitleLabel
                color: Theme.accentMuted
                font.pixelSize: Math.round(Theme.textXs * root.echelle)
                elide: Text.ElideRight
            }

            // Progression : 2 px, même famille que la barre du popup média.
            Item {
                width: parent.width
                height: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    radius: 1
                    color: Qt.alpha(Theme.fg, 0.16)

                    Rectangle {
                        width: parent.width * root.ratio
                        height: parent.height
                        radius: 1
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }
                }
            }

            // Une seule Row, sans imbrication : une Row dans une Row avec des
            // ancrages déclenche « Cannot specify left, right, horizontalCenter,
            // fill or centerIn anchors for items inside Row » et la rangée entière
            // cesse de s'afficher (mesuré : plus aucun contrôle dans la carte).
            Row {
                width: parent.width
                spacing: Theme.space2

                Text {
                    id: posText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(root.posNow)
                    color: Qt.alpha(Theme.fg, 0.65)
                    font.pixelSize: Math.round(Theme.text2xs * root.echelle)
                    font.features: { "tnum": 1 }
                }

                // Écart extensible : pousse les contrôles à droite sans ancrage.
                Item {
                    width: Math.max(0, parent.width - posText.implicitWidth
                                    - prevIcon.width - playIcon.width - nextIcon.width
                                    - durText.implicitWidth - Theme.space2 * 5)
                    height: 1
                }

                Icon {
                    id: prevIcon
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "previous"
                    size: Math.round(Theme.iconSm * root.echelle)
                    color: Theme.fg
                    opacityLevel: root.hasTrack && root.player.canGoPrevious ? 0.85 : 0.25

                    MouseArea {
                        width: parent.width + 12
                        height: parent.height + 12
                        x: -6
                        y: -6
                        cursorShape: root.hasTrack && root.player.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root.hasTrack && root.player.canGoPrevious) root.player.previous()
                    }
                }

                Icon {
                    id: playIcon
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root.isPlaying ? "pause" : "play"
                    size: Math.round(Theme.iconSm * root.echelle)
                    color: Theme.accent
                    opacityLevel: (root.hasTrack || !root.launching) ? 1 : 0.5

                    MouseArea {
                        width: parent.width + 14
                        height: parent.height + 14
                        x: -7
                        y: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlayback()
                    }
                }

                Icon {
                    id: nextIcon
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "next"
                    size: Math.round(Theme.iconSm * root.echelle)
                    color: Theme.fg
                    opacityLevel: root.hasTrack && root.player.canGoNext ? 0.85 : 0.25

                    MouseArea {
                        width: parent.width + 12
                        height: parent.height + 12
                        x: -6
                        y: -6
                        cursorShape: root.hasTrack && root.player.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root.hasTrack && root.player.canGoNext) root.player.next()
                    }
                }

                Text {
                    id: durText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(root.durNow)
                    color: Qt.alpha(Theme.fg, 0.65)
                    font.pixelSize: Math.round(Theme.text2xs * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
