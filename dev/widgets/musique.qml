import QtQuick
import ".."
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// MUSIQUE — lecteur permanent sur le bureau (pochette, métadonnées, barre pointillée, progression, contrôles).
Item {
    id: root

    property var options: ({})
    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }
    property string widgetId: ""

    property string lastArt: ""
    property string lastName: ""
    property string lastArtist: ""
    property string lastAlbum: ""
    property string lastSource: ""
    property bool launching: false
    property int posTick: 0

    readonly property var browserHints: ["firefox", "zen", "chromium", "chrome",
                                         "brave", "vivaldi", "opera", "librewolf"]

    readonly property bool ignorerNavigateurs: {
        const v = options ? options.ignorer_navigateurs : undefined
        if (v === undefined || v === null || v === "") return true
        return !(v === false || v === "false" || v === 0 || v === "0")
    }

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

    readonly property string artSource: {
        const u = hasTrack && player.trackArtUrl ? String(player.trackArtUrl) : ""
        if (u === "") return ""
        if (u.indexOf("file://") === 0 || u.indexOf("http") === 0
                || u.indexOf("data:") === 0 || u.indexOf("image://") === 0) return u
        return "file://" + u
    }

    readonly property string sourceLabel: {
        if (hasTrack) return String(player.identity || player.desktopEntry || "Lecteur")
        if (lastSource !== "") return lastSource
        return SystemServices.program("Music") || "Lecteur audio"
    }
    readonly property string titleLabel: hasTrack ? String(player.trackTitle)
                                                 : (lastName !== "" ? lastName : "Aucune lecture")
    readonly property string artistOnly: hasTrack
        ? String(player.trackArtist || player.trackAlbumArtist || "")
        : (lastArtist !== "" ? lastArtist : ("Play pour lancer " + (SystemServices.program("Music") || "le lecteur")))
    readonly property string albumOnly: hasTrack
        ? String(player.trackAlbum || "")
        : lastAlbum

    readonly property string shownArt: artSource !== "" ? artSource : lastArt
    readonly property int cardWidth: Math.round(330 * echelle)

    implicitWidth: cardWidth
    implicitHeight: mainCol.implicitHeight

    onArtSourceChanged: {
        if (artSource === "") return
        lastArt = artSource
        lastName = String(player.trackTitle || "")
        lastArtist = String(player.trackArtist || player.trackAlbumArtist || "")
        lastAlbum = String(player.trackAlbum || "")
        lastSource = String(player.identity || player.desktopEntry || "")
    }

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0))
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" + r : String(r))
    }

    Process {
        id: launcherProc
    }

    function launchPlayer() {
        if (launching) return
        const prog = SystemServices.program("Music")
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

    Timer {
        id: launchGiveUp
        interval: 12000
        onTriggered: root.launching = false
    }

    Column {
        id: mainCol
        width: root.cardWidth
        spacing: Math.round(12 * root.echelle)

        // ── En-tête : Pochette carrée + Source / Titre / Artiste / Album ────
        Row {
            width: parent.width
            spacing: Math.round(14 * root.echelle)

            Rectangle {
                readonly property int artSize: Math.round(80 * root.echelle)
                width: artSize
                height: artSize
                radius: Math.max(12, Math.round(Theme.globalRadius * 0.8))
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
                width: parent.width - Math.round(80 * root.echelle) - Math.round(14 * root.echelle)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(2 * root.echelle)

                Text {
                    width: parent.width
                    text: root.sourceLabel
                    color: Theme.accent
                    opacity: 0.85
                    font.pixelSize: Math.round(10 * root.echelle)
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.titleLabel
                    color: Theme.fg
                    font.pixelSize: Math.round(15 * root.echelle)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.artistOnly !== ""
                    text: root.artistOnly
                    color: Qt.alpha(Theme.fg, 0.82)
                    font.pixelSize: Math.round(13 * root.echelle)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.albumOnly !== ""
                    text: root.albumOnly
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.pixelSize: Math.round(11 * root.echelle)
                    elide: Text.ElideRight
                }
            }
        }

        // ── Ligne pointillée audio réactive (toute la largeur) ───────────────
        Row {
            id: vizDotsRow
            width: parent.width
            readonly property int dotCount: 28
            readonly property real dotGap: Math.round(4 * root.echelle)
            readonly property real dotW: (width - (dotCount - 1) * dotGap) / dotCount
            readonly property var levels: VisualiseurAudio.hauteurs || []
            readonly property bool liveAudio: root.isPlaying && !VisualiseurAudio.silence && levels.length > 0
            spacing: dotGap

            Repeater {
                model: vizDotsRow.dotCount

                delegate: Rectangle {
                    required property int index
                    readonly property real distCenter: Math.abs(index - (vizDotsRow.dotCount - 1) / 2) / ((vizDotsRow.dotCount - 1) / 2)
                    readonly property real bandVal: {
                        if (!vizDotsRow.liveAudio) return 0
                        const _ = VisualiseurAudio.seq
                        const len = vizDotsRow.levels.length
                        const bi = Math.min(len - 1, Math.floor(distCenter * len * 0.85))
                        return Math.max(0, Math.min(1, Number(vizDotsRow.levels[bi]) || 0))
                    }
                    readonly property real intensity: vizDotsRow.liveAudio
                        ? Math.min(1, 0.18 + bandVal * 1.15)
                        : (root.isPlaying ? Math.max(0.18, 0.55 - distCenter * 0.35) : 0.18)
                    width: vizDotsRow.dotW
                    height: Math.round(3 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.accent, intensity)
                    Behavior on color { ColorAnimation { duration: 90 } }
                }
            }
        }

        // ── Progression : temps écoulé | barre | durée ──────────────────────
        Item {
            width: parent.width
            height: Math.round(16 * root.echelle)

            Text {
                id: posText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatTime(root.posNow)
                color: Qt.alpha(Theme.fg, 0.65)
                font.pixelSize: Math.round(11 * root.echelle)
                font.features: { "tnum": 1 }
            }

            Item {
                id: progressTrackWrap
                anchors.left: posText.right
                anchors.leftMargin: Math.round(10 * root.echelle)
                anchors.right: durText.left
                anchors.rightMargin: Math.round(10 * root.echelle)
                anchors.verticalCenter: parent.verticalCenter
                height: Math.round(14 * root.echelle)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(5 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.14)

                    Rectangle {
                        width: parent.width * root.ratio
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.Linear } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.hasTrack && root.player.canSeek && root.durNow > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        if (!root.hasTrack || !root.player.canSeek || root.durNow <= 0) return
                        const frac = Math.max(0, Math.min(1, mouse.x / Math.max(1, width)))
                        root.player.position = frac * root.durNow
                        root.posTick++
                    }
                }
            }

            Text {
                id: durText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatTime(root.durNow)
                color: Qt.alpha(Theme.fg, 0.65)
                font.pixelSize: Math.round(11 * root.echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── Contrôles centrés : Précédent | Carré arrondi Play/Pause | Suivant
        Item {
            width: parent.width
            height: Math.round(52 * root.echelle)

            Row {
                anchors.centerIn: parent
                spacing: Math.round(22 * root.echelle)

                Item {
                    width: Math.round(32 * root.echelle)
                    height: width
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        anchors.centerIn: parent
                        glyph: "previous"
                        size: Math.round(18 * root.echelle)
                        color: Theme.fg
                        opacityLevel: root.hasTrack && root.player.canGoPrevious ? 0.90 : 0.30
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.hasTrack && root.player.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root.hasTrack && root.player.canGoPrevious) root.player.previous()
                    }
                }

                Rectangle {
                    width: Math.round(50 * root.echelle)
                    height: width
                    radius: Math.max(12, Math.round(16 * root.echelle))
                    color: playBtnMa.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        anchors.centerIn: parent
                        glyph: root.isPlaying ? "pause" : "play"
                        size: Math.round(20 * root.echelle)
                        color: Theme.bg
                        opacityLevel: (root.hasTrack || !root.launching) ? 1 : 0.5
                    }

                    MouseArea {
                        id: playBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlayback()
                    }
                }

                Item {
                    width: Math.round(32 * root.echelle)
                    height: width
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        anchors.centerIn: parent
                        glyph: "next"
                        size: Math.round(18 * root.echelle)
                        color: Theme.fg
                        opacityLevel: root.hasTrack && root.player.canGoNext ? 0.90 : 0.30
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.hasTrack && root.player.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root.hasTrack && root.player.canGoNext) root.player.next()
                    }
                }
            }
        }
    }
}
