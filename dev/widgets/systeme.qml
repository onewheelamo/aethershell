import QtQuick
import ".."
import Quickshell

// SYSTÈME — widget bureau avec anneaux CPU/Memory/GPU, barres Threads et VRAM/Disk/Power.
Item {
    id: root
    property var options: ({})
    property string widgetId: ""

    readonly property real echelle: {
        const v = Number(options && options.text_scale)
        if (v >= 60 && v <= 160) return v / 100
        return 1.0
    }

    readonly property var donnees: SystemServices.systemeData
    readonly property bool charge: SystemServices.systemeCharge
    readonly property var barres: (donnees && donnees.compact && donnees.compact.barres) ? donnees.compact.barres : []
    readonly property var detail: (donnees && donnees.detail) ? donnees.detail : ({})

    readonly property int cardWidth: Math.round(310 * echelle)

    function formatGo(v) {
        const n = Number(v)
        if (!isFinite(n)) return "0.0"
        return n.toFixed(1)
    }

    function couleurNiveau(pct) {
        if (pct >= 92) return Theme.error
        if (pct >= 80) return Theme.accentMuted
        return Theme.accent
    }

    function barrePct(cle) {
        for (let i = 0; i < barres.length; ++i) {
            if (barres[i].cle === cle) return Number(barres[i].valeur) || 0
        }
        return 0
    }

    readonly property real cpuPct: (detail.cpu && detail.cpu.pct !== undefined) ? Number(detail.cpu.pct) : barrePct("cpu")
    readonly property real ramPct: {
        if (detail.ram && Number(detail.ram.totale_go) > 0) {
            return 100 * (Number(detail.ram.utilisee_go) || 0) / Number(detail.ram.totale_go)
        }
        return barrePct("ram")
    }
    readonly property bool hasGpu: Boolean(detail.gpu && (detail.gpu.pct !== undefined || detail.gpu.temperature !== undefined || Number(detail.gpu.vram_totale_go) > 0))
    readonly property real gpuPct: (detail.gpu && detail.gpu.pct !== undefined) ? Number(detail.gpu.pct) : barrePct("gpu")

    readonly property var ringsModel: {
        const cpuSub = []
        if (detail.temp && detail.temp.cpu !== undefined) cpuSub.push(Math.round(detail.temp.cpu) + "°C")
        if (detail.cpu && detail.cpu.freq_ghz) cpuSub.push(Number(detail.cpu.freq_ghz).toFixed(1) + " GHz")

        const ramSub = (detail.ram && detail.ram.totale_go)
            ? (formatGo(detail.ram.utilisee_go) + " / " + formatGo(detail.ram.totale_go) + " GiB")
            : ""

        const out = [
            { label: "CPU",    pct: cpuPct, sub: cpuSub.join(" · ") },
            { label: "Memory", pct: ramPct, sub: ramSub }
        ]
        if (hasGpu) {
            const gTemp = (detail.gpu && detail.gpu.temperature !== undefined)
                ? (Math.round(detail.gpu.temperature) + "°C")
                : ""
            out.push({ label: "GPU", pct: gpuPct, sub: gTemp })
        }
        return out
    }

    readonly property var threadsList: (detail.cpu && Array.isArray(detail.cpu.coeurs)) ? detail.cpu.coeurs : []
    readonly property bool hasVram: Boolean(detail.gpu && Number(detail.gpu.vram_totale_go) > 0)
    readonly property bool hasDisk: Boolean(detail.disk && Number(detail.disk.total_go) > 0)
    readonly property bool hasPower: Boolean((detail.gpu && detail.gpu.power_w !== undefined && detail.gpu.power_w !== null) || detail.fan_rpm !== undefined)

    Component.onCompleted: SystemServices.metriquesActif = true

    implicitWidth: cardWidth
    implicitHeight: colonne.implicitHeight

    Column {
        id: colonne
        width: root.cardWidth
        spacing: Math.round(12 * root.echelle)

        // ── En-tête : puce + nom du CPU à gauche, uptime à droite ──────────
        Item {
            width: parent.width
            height: Math.round(28 * root.echelle)

            Rectangle {
                id: cpuBadge
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(26 * root.echelle)
                height: width
                radius: width / 2
                color: Qt.alpha(Theme.fg, 0.10)

                IconSvg {
                    anchors.centerIn: parent
                    nom: "cpu"
                    size: Math.round(14 * root.echelle)
                    couleur: Theme.accent
                }
            }

            Text {
                anchors.left: cpuBadge.right
                anchors.leftMargin: Math.round(8 * root.echelle)
                anchors.right: uptimeText.visible ? uptimeText.left : parent.right
                anchors.rightMargin: Math.round(8 * root.echelle)
                anchors.verticalCenter: parent.verticalCenter
                text: (root.detail.cpu && root.detail.cpu.nom) ? String(root.detail.cpu.nom) : "CPU"
                color: Theme.fg
                font.pixelSize: Math.round(13 * root.echelle)
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                id: uptimeText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Boolean(root.detail.uptime && root.detail.uptime.texte)
                text: root.detail.uptime ? ("up " + String(root.detail.uptime.texte)) : ""
                color: Qt.alpha(Theme.fg, 0.65)
                font.pixelSize: Math.round(11 * root.echelle)
                font.features: { "tnum": 1 }
            }
        }

        // ── 3 Anneaux circulaires : CPU / Memory / GPU ──────────────────────
        Row {
            width: parent.width
            spacing: Math.round(8 * root.echelle)

            Repeater {
                model: root.ringsModel

                delegate: Column {
                    required property var modelData
                    readonly property int ringCount: Math.max(1, root.ringsModel.length)
                    readonly property real colW: Math.floor((parent.width - (ringCount - 1) * Math.round(8 * root.echelle)) / ringCount)
                    readonly property int ringSize: Math.round(76 * root.echelle)
                    readonly property real pctVal: Math.max(0, Math.min(100, Number(modelData.pct) || 0))
                    readonly property color ringColor: root.couleurNiveau(pctVal)
                    width: colW
                    spacing: Math.round(4 * root.echelle)

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: ringSize
                        height: ringSize

                        Canvas {
                            id: ringCanvas
                            anchors.fill: parent
                            readonly property real p: pctVal
                            readonly property color ac: ringColor
                            readonly property color tr: Qt.alpha(Theme.fg, 0.12)
                            onPChanged: requestPaint()
                            onAcChanged: requestPaint()
                            onTrChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                const lw = Math.max(4, Math.round(6 * root.echelle))
                                const cx = width / 2
                                const cy = height / 2
                                const r = Math.max(4, (Math.min(width, height) - lw) / 2)

                                ctx.lineWidth = lw
                                ctx.lineCap = "round"

                                ctx.beginPath()
                                ctx.strokeStyle = tr
                                ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
                                ctx.stroke()

                                if (p > 0) {
                                    const start = -Math.PI / 2
                                    const end = start + Math.PI * 2 * (p / 100)
                                    ctx.beginPath()
                                    ctx.strokeStyle = ac
                                    ctx.arc(cx, cy, r, start, end, false)
                                    ctx.stroke()
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Math.round(pctVal) + "%"
                            color: Theme.fg
                            font.pixelSize: Math.round(16 * root.echelle)
                            font.bold: true
                            font.features: { "tnum": 1 }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(modelData.label)
                        color: Theme.fg
                        font.pixelSize: Math.round(12 * root.echelle)
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: String(modelData.sub || "") !== ""
                        text: String(modelData.sub || "")
                        color: Qt.alpha(Theme.fg, 0.65)
                        font.pixelSize: Math.round(10 * root.echelle)
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        // ── Threads : barres verticales par cœur logique ─────────────────────
        Column {
            visible: root.threadsList.length > 0
            width: parent.width
            spacing: Math.round(6 * root.echelle)

            Item {
                width: parent.width
                height: Math.round(16 * root.echelle)

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Threads"
                    color: Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Math.round(11 * root.echelle)
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(root.threadsList.length)
                    color: Qt.alpha(Theme.fg, 0.65)
                    font.pixelSize: Math.round(11 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            Row {
                width: parent.width
                spacing: Math.round(4 * root.echelle)
                readonly property int n: Math.max(1, root.threadsList.length)
                readonly property real barW: Math.max(4, Math.floor((width - (n - 1) * spacing) / n))

                Repeater {
                    model: root.threadsList

                    delegate: Rectangle {
                        required property var modelData
                        readonly property real val: Math.max(0, Math.min(100, Number(modelData) || 0))
                        width: parent.barW
                        height: Math.round(24 * root.echelle)
                        radius: Math.round(4 * root.echelle)
                        color: Qt.alpha(Theme.fg, 0.10)
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: Math.max(Math.round(3 * root.echelle), Math.round(parent.height * val / 100))
                            radius: Math.round(3 * root.echelle)
                            color: root.couleurNiveau(val)
                            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        // ── Métriques basses : VRAM, Disk, Power ────────────────────────────
        Column {
            width: parent.width
            spacing: Math.round(8 * root.echelle)

            // VRAM
            Item {
                visible: root.hasVram
                width: parent.width
                height: Math.round(18 * root.echelle)
                readonly property real used: (root.detail.gpu && Number(root.detail.gpu.vram_go)) || 0
                readonly property real total: (root.detail.gpu && Number(root.detail.gpu.vram_totale_go)) || 1
                readonly property real ratio: Math.max(0, Math.min(1, used / total))

                IconSvg {
                    id: vramIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    nom: "ram"
                    size: Math.round(13 * root.echelle)
                    couleur: Qt.alpha(Theme.fg, 0.65)
                }

                Text {
                    id: vramLbl
                    anchors.left: vramIcon.right
                    anchors.leftMargin: Math.round(8 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(44 * root.echelle)
                    text: "VRAM"
                    color: Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Math.round(11 * root.echelle)
                }

                Rectangle {
                    anchors.left: vramLbl.right
                    anchors.leftMargin: Math.round(8 * root.echelle)
                    anchors.right: vramVal.left
                    anchors.rightMargin: Math.round(10 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(5 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.13)

                    Rectangle {
                        width: Math.max(Math.round(5 * root.echelle), parent.width * parent.parent.ratio)
                        height: parent.height
                        radius: parent.radius
                        color: root.couleurNiveau(parent.parent.ratio * 100)
                    }
                }

                Text {
                    id: vramVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatGo(parent.used) + " / " + root.formatGo(parent.total) + " GiB"
                    color: Qt.alpha(Theme.fg, 0.80)
                    font.pixelSize: Math.round(11 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            // Disk
            Item {
                visible: root.hasDisk
                width: parent.width
                height: Math.round(18 * root.echelle)
                readonly property real used: (root.detail.disk && Number(root.detail.disk.utilise_go)) || 0
                readonly property real total: (root.detail.disk && Number(root.detail.disk.total_go)) || 1
                readonly property real ratio: Math.max(0, Math.min(1, used / total))

                IconSvg {
                    id: diskIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    nom: "disque"
                    size: Math.round(13 * root.echelle)
                    couleur: Qt.alpha(Theme.fg, 0.65)
                }

                Text {
                    id: diskLbl
                    anchors.left: diskIcon.right
                    anchors.leftMargin: Math.round(8 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(44 * root.echelle)
                    text: "Disk"
                    color: Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Math.round(11 * root.echelle)
                }

                Rectangle {
                    anchors.left: diskLbl.right
                    anchors.leftMargin: Math.round(8 * root.echelle)
                    anchors.right: diskVal.left
                    anchors.rightMargin: Math.round(10 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(5 * root.echelle)
                    radius: height / 2
                    color: Qt.alpha(Theme.fg, 0.13)

                    Rectangle {
                        width: Math.max(Math.round(5 * root.echelle), parent.width * parent.parent.ratio)
                        height: parent.height
                        radius: parent.radius
                        color: root.couleurNiveau(parent.parent.ratio * 100)
                    }
                }

                Text {
                    id: diskVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatGo(parent.used) + " / " + root.formatGo(parent.total) + " GiB"
                    color: Qt.alpha(Theme.fg, 0.80)
                    font.pixelSize: Math.round(11 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }

            // Power
            Item {
                visible: root.hasPower
                width: parent.width
                height: Math.round(18 * root.echelle)

                Icon {
                    id: pwrIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "power"
                    size: Math.round(13 * root.echelle)
                    color: Qt.alpha(Theme.fg, 0.65)
                }

                Text {
                    anchors.left: pwrIcon.right
                    anchors.leftMargin: Math.round(8 * root.echelle)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Power"
                    color: Qt.alpha(Theme.fg, 0.72)
                    font.pixelSize: Math.round(11 * root.echelle)
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const parts = []
                        if (root.detail.gpu && root.detail.gpu.power_w !== undefined && root.detail.gpu.power_w !== null) {
                            parts.push(Math.round(Number(root.detail.gpu.power_w)) + " W")
                        }
                        if (root.detail.fan_rpm !== undefined && root.detail.fan_rpm !== null) {
                            parts.push(Math.round(Number(root.detail.fan_rpm)) + " rpm")
                        }
                        return parts.join(" · ")
                    }
                    color: Qt.alpha(Theme.fg, 0.80)
                    font.pixelSize: Math.round(11 * root.echelle)
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
