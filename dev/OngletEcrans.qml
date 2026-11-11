import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Écrans & Système » du panneau de configuration, sorti de config_panel.qml.
// Le panneau le charge par URL et ne l'instancie qu'a l'ouverture de
// l'onglet : le corps n'a pas bouge d'un caractere, hors indentation.
//
// `root` et `mainFlickable` viennent du panneau sous les noms qu'ils avaient
// deja dans ce corps, donc les appels a la racine sont restes intacts.
// `sections` et `cibles` sont remplies apres la decoupe (voir decouper.py) :
// le panneau ne peut plus nommer ces ids, il les demande ici.
Column {
    id: bloc
    property var root
    property var mainFlickable

    // Plusieurs onglets restent montés depuis qu'on ne les décharge plus en
    // quittant : sans ce masque, ils s'empilaient les uns sur les autres
    // (le `visible:` du panneau avait été retiré à la découpe).
    visible: root ? root.currentTab === 3 : false
    width: mainFlickable ? mainFlickable.width : 0

    readonly property var sections: ({
        "ecrans_moniteurs": secEcrans,
        "ecrans_profils": secProfils,
        "systeme_horloge": secHorloge,
        "systeme_nuit": secNuit,
        "ecrans_captures": secCaptures,
        "systeme_maj": secMaj
    })

    readonly property var cibles: ({
        "monitorsRow": monitorsRow,
        "timezoneRow": timezoneRow,
        "idleTimeoutRow": idleTimeoutRow,
        "screenshotsDirRow": screenshotsDirRow,
        "shellMajRow": shellMajRow
    })

    // ── Mise à jour du shell ─────────────────────────────────────────────────
    // Une seule ligne sert à installer **et** à mettre à jour, comme pour Ollama :
    //
    //   curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | sh
    //
    // `core/maj_shell.py` compare la version déployée (`core/version.json`, écrit
    // par `deploy.sh`) au dernier tag publié sur GitHub. Il ne sort sur le réseau
    // qu'une fois toutes les `intervalleMin` minutes — 280 par défaut — et le
    // minuteur ci-dessous ne fait que lui redemander l'état : le cache répond.
    // L'intervalle est publié par le script, pour n'avoir qu'une constante.
    property string majEtat: ""
    property string majLocale: ""
    property string majDistante: ""
    property string majVerifie: ""
    property string majDetail: "vérification…"
    property string majCopie: ""
    property int intervalleMin: 280
    property bool majOccupe: false
    property string majCommande: "curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | sh"

    readonly property bool majDisponible: majEtat === "disponible"
    readonly property string majResume: majLocale === ""
        ? "vérification…"
        : (majDisponible ? majLocale + " → " + majDistante
                         : (majEtat === "a_jour" ? majLocale + " · à jour"
                                                 : majLocale + " · état inconnu"))

    function verifierMaj(force) {
        if (procMaj.running) return
        procMaj.command = ["python3", Quickshell.shellPath("core/maj_shell.py")]
                          .concat(force ? ["--force"] : [])
        procMaj.running = true
    }

    function appliquerMaj(texte) {
        try {
            const d = JSON.parse(texte)
            bloc.majEtat = String(d.etat || "")
            bloc.majLocale = String(d.locale || "")
            bloc.majDistante = String(d.distante || "")
            bloc.majDetail = String(d.detail || "")
            bloc.majVerifie = String(d.verifie_le || "")
            if (d.commande) bloc.majCommande = String(d.commande)
            // Le script fait foi : changer la fenêtre de vérification ne touche
            // qu'à `INTERVALLE_MIN` dans core/maj_shell.py.
            if (d.intervalle_min) bloc.intervalleMin = Number(d.intervalle_min)
        } catch (e) {
            bloc.majEtat = "inconnu"
            bloc.majDetail = "réponse illisible de core/maj_shell.py"
        }
    }

    Process {
        id: procMaj
        onRunningChanged: bloc.majOccupe = running
        stdout: StdioCollector {
            onStreamFinished: bloc.appliquerMaj(text)
        }
        onExited: code => {
            if (code !== 0 && bloc.majEtat === "") {
                bloc.majEtat = "inconnu"
                bloc.majDetail = "core/maj_shell.py a échoué (code " + code + ")"
            }
        }
    }

    // Toutes les 280 minutes, et seulement tant que l'onglet est à l'écran :
    // fermer le panneau ne laisse aucun minuteur derrière lui. `triggeredOnStart`
    // donne l'état dès l'ouverture, sans attendre la première échéance.
    Timer {
        interval: Math.max(1, bloc.intervalleMin) * 60 * 1000
        running: bloc.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: bloc.verifierMaj(false)
    }

    // Retour visuel du bouton « Copier la ligne ».
    Timer {
        id: finCopie
        interval: 2200
        onTriggered: bloc.majCopie = ""
    }

spacing: 12

// Tiroir : moniteurs détectés, moniteur principal, résolution et
// fréquence.
CollapsibleSection {
    id: secEcrans
    objectName: "secEcrans"
    title: "Moniteurs & résolution"
    summary: root.selectedMonitorName + " · " + root.monitorsList.length + " écran(s)"
    icon: "monitor"
    expanded: root.sectionOpen("ecrans_moniteurs", false)
    onToggled: expanded => {
        root.setPanelSection("ecrans_moniteurs", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ecrans_moniteurs")
    }

Text {
    width: parent.width
    text: "Moniteurs détectés (" + root.hostName + ") — cliquer pour sélectionner un écran"
    color: Theme.accent
    font.pixelSize: Theme.textLg
    font.bold: true
    wrapMode: Text.WordWrap
}

// Liste des moniteurs détectés (HDMI-A-1 sur une tour, eDP-1 sur un portable)
Row {
    id: monitorsRow   // ancre de recherche
    objectName: "monitorsRow"
    spacing: 10
    width: parent.width

    Repeater {
        model: root.monitorsList

        Rectangle {
            id: monCard
            required property var modelData
            readonly property bool isSel: root.selectedMonitorName === modelData.name
            width: (parent.width - 10 * Math.max(0, root.monitorsList.length - 1))
                   / Math.max(1, root.monitorsList.length)
            height: 54
            radius: Theme.globalRadius
            color: isSel ? Qt.alpha(Theme.accent, 0.22) : Theme.surfaceVariant
            border.color: isSel ? Theme.accent : Theme.accentMuted
            border.width: isSel ? 2 : 1

            Column {
                anchors.centerIn: parent
                spacing: 2
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Text {
                        text: monCard.modelData.name + " (" + monCard.modelData.width + "x" + monCard.modelData.height + "@" + monCard.modelData.refreshRate + "Hz)"
                        color: monCard.isSel ? Theme.accent : Theme.fg
                        font.pixelSize: Theme.textSm
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: !!monCard.modelData.is_primary
                        width: 52
                        height: 16
                        radius: 3
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "Principal"
                            color: Theme.bg
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: monCard.modelData.description || "Sortie vidéo active"
                    color: Qt.alpha(Theme.fg, 0.7)
                    font.pixelSize: Theme.textXs
                    elide: Text.ElideRight
                    width: monCard.width - 16
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedMonitorName = monCard.modelData.name
            }
        }
    }
}

// Statut / Action Écran Principal
Rectangle {
    visible: root.monitorsList.length > 1
    width: parent.width
    height: 32
    radius: Theme.globalRadius
    readonly property bool isSelectedPrimary: root.currentMonitorObj && !!root.currentMonitorObj.is_primary
    color: isSelectedPrimary ? Qt.alpha(Theme.accent, 0.12) : (makePrimMa.containsMouse ? Theme.accent : Theme.surfaceVariant)
    border.color: Theme.accent
    border.width: 1

    Row {
        anchors.centerIn: parent
        spacing: 8
        Icon {
            glyph: "check"
            size: Theme.iconSm
            color: parent.parent.isSelectedPrimary ? Theme.accent : (makePrimMa.containsMouse ? Theme.bg : Theme.accent)
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.isSelectedPrimary
                ? "« " + root.selectedMonitorName + " » est l'écran principal (Workspaces 1 à 5)"
                : "Définir « " + root.selectedMonitorName + " » comme écran principal"
            color: parent.parent.isSelectedPrimary ? Theme.accent : (makePrimMa.containsMouse ? Theme.bg : Theme.fg)
            font.pixelSize: Theme.textXs
            font.bold: true
        }
    }

    MouseArea {
        id: makePrimMa
        anchors.fill: parent
        enabled: !parent.isSelectedPrimary
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.runConfigCmd(["monitor_primary", root.selectedMonitorName])
    }
}

// Resolution & Refresh Rate Dropdown Selector
Text {
    width: parent.width
    text: "Résolution & Fréquence pour « " + root.selectedMonitorName + " » :"
    color: Theme.accent
    font.pixelSize: Theme.textMd
    font.bold: true
    wrapMode: Text.WordWrap
}

Column {
    width: parent.width
    spacing: 4

    // Bouton principal du menu déroulant
    Rectangle {
        id: resDropdownBtn
        width: parent.width
        height: 36
        radius: Theme.globalRadius
        color: resBtnMa.containsMouse ? Qt.alpha(Theme.accent, 0.18) : Theme.surfaceVariant
        border.color: root.resDropdownOpen ? Theme.accent : Theme.accentMuted
        border.width: 1

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Icon {
                glyph: "monitor"
                size: Theme.iconSm
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const m = root.currentMonitorObj
                    return m ? ("Mode actif : " + m.width + "x" + m.height + "@" + m.refreshRate + "Hz") : "Auto (Preferred)"
                }
                color: Theme.fg
                font.pixelSize: Theme.textSm
                font.bold: true
            }
        }

        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.resDropdownOpen ? "chevron-up" : "chevron-down"
            size: Theme.iconSm
            color: Theme.accent
        }

        MouseArea {
            id: resBtnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resDropdownOpen = !root.resDropdownOpen
        }
    }

    // Liste déroulante des modes
    Rectangle {
        visible: root.resDropdownOpen
        width: parent.width
        height: Math.min(220, resCol.height + 8)
        radius: Theme.globalRadius
        color: Theme.surface
        border.color: Theme.accent
        border.width: 1
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: 4
            contentWidth: width
            contentHeight: resCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: resCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.currentMonitorModes

                    Rectangle {
                        required property string modelData
                        width: parent.width
                        height: 30
                        radius: Theme.globalRadius - 2
                        readonly property bool isCurrent: {
                            const m = root.currentMonitorObj
                            if (!m) return false
                            if (modelData === "preferred") return false
                            return modelData === (m.width + "x" + m.height + "@" + m.refreshRate)
                        }
                        color: itemMa.containsMouse ? Qt.alpha(Theme.accent, 0.25) : (isCurrent ? Qt.alpha(Theme.accent, 0.12) : "transparent")

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Icon {
                                glyph: isCurrent ? "check" : "chevron-right"
                                size: 14
                                color: isCurrent ? Theme.accent : Qt.alpha(Theme.fg, 0.35)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData === "preferred" ? "Auto (Preferred)" : (modelData + "Hz")
                                color: isCurrent ? Theme.accent : Theme.fg
                                font.pixelSize: Theme.textXs
                                font.bold: isCurrent
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const curScale = root.currentMonitorObj ? String(root.currentMonitorObj.scale || 1) : "1"
                                root.runConfigCmd(["monitor_mode", root.selectedMonitorName, modelData, curScale])
                                root.resDropdownOpen = false
                            }
                        }
                    }
                }
            }
        }
    }
}

// Scale factor selector (Mouse only)
}

// Tiroir : mise à l'échelle, profils multi-écrans et mode tablette.
CollapsibleSection {
    id: secProfils
    objectName: "secProfils"
    title: "Profils & rotation"
    summary: root.isLaptop ? "portable" : "fixe"
    icon: "tablet"
    expanded: root.sectionOpen("ecrans_profils", false)
    onToggled: expanded => {
        root.setPanelSection("ecrans_profils", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ecrans_profils")
    }

Row {
    spacing: 10
    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (3 * 58 + 3 * 10 + 8)
        text: "Mise à l'échelle (Scale) de " + root.selectedMonitorName + " :"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        elide: Text.ElideRight
    }

    Repeater {
        model: ["1", "1.25", "1.5"]
        Rectangle {
            required property string modelData
            readonly property bool activeScale: root.currentMonitorObj && Math.abs(Number(root.currentMonitorObj.scale) - Number(modelData)) < 0.05
            width: 58
            height: 26
            radius: Theme.globalRadius
            color: activeScale ? Theme.accent : Theme.surfaceVariant
            Text {
                anchors.centerIn: parent
                text: modelData + "x"
                color: parent.activeScale ? Theme.bg : Theme.fg
                font.pixelSize: Theme.textXs
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const m = root.currentMonitorObj
                    const curMode = m ? (m.width + "x" + m.height + "@" + m.refreshRate) : "preferred"
                    root.runConfigCmd(["monitor_mode", root.selectedMonitorName, curMode, modelData])
                }
            }
        }
    }
}

// Section réservée au portable : profils multi-écrans et rotation tablette
Column {
    visible: root.isLaptop
    width: parent.width
    spacing: 10

    Text {
        text: "Profils Multi-Écrans & Mode Tablette (portable uniquement)"
        color: Theme.accent
        font.pixelSize: Theme.textMd
        font.bold: true
    }

    Row {
        spacing: 8
        width: parent.width

        Repeater {
            model: [
                { id: "dual", title: "Étendu (TV + laptop)" },
                { id: "tv", title: "TV uniquement (dock)" },
                { id: "laptop", title: "Nomade (laptop seul)" }
            ]

            Rectangle {
                required property var modelData
                width: (parent.width - 16) / 3
                height: 32
                radius: Theme.globalRadius
                color: profMa.containsMouse ? Theme.accent : Theme.surfaceVariant
                Text {
                    anchors.centerIn: parent
                    text: modelData.title
                    color: profMa.containsMouse ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }
                MouseArea {
                    id: profMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["monitor_profile", modelData.id])
                }
            }
        }
    }

    Row {
        spacing: 8
        Repeater {
            model: [
                { t: "0", label: "0° Normal" },
                { t: "2", label: "180° Tablette" },
                { t: "1", label: "90° Portrait G" },
                { t: "3", label: "270° Portrait D" }
            ]

            Rectangle {
                required property var modelData
                width: 152
                height: 28
                radius: Theme.globalRadius
                color: rotMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: rotMa.containsMouse ? Theme.bg : Theme.fg
                    font.pixelSize: Theme.textXs
                }
                MouseArea {
                    id: rotMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["rotate", modelData.t])
                }
            }
        }
    }
}

Rectangle {
    width: parent.width
    height: 1
    color: Theme.surfaceVariant
}

// System Time, Network Shortcut (& Battery 80% Limiter if Laptop)
}

// Tiroir : énergie, veille, fuseau horaire et batterie
CollapsibleSection {
    id: secHorloge
    objectName: "secHorloge"
    title: "Énergie & horloge"
    summary: "Veille : " + root.idleSuspendLabel + " · " + (root.ntpSynced ? "NTP synchronisé" : "NTP manuel")
    icon: "power"
    expanded: root.sectionOpen("systeme_horloge", false)
    onToggled: expanded => {
        root.setPanelSection("systeme_horloge", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("systeme_horloge")
    }

Column {
    width: parent.width
    spacing: 12

    // ── Mise en veille du système (inactivité) ────────────────────
    Column {
        id: idleTimeoutRow
        objectName: "idleTimeoutRow"
        width: parent.width
        spacing: 6

        Row {
            width: parent.width
            spacing: 8

            Text {
                text: "Mise en veille automatique :"
                color: Theme.accent
                font.pixelSize: Theme.textSm
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "inactivité avant suspension (hypridle)"
                color: Qt.alpha(Theme.fg, 0.55)
                font.pixelSize: Theme.textXs
            }
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: [
                    { label: "15 min", value: 900 },
                    { label: "30 min", value: 1800 },
                    { label: "1 heure (défaut)", value: 3600 },
                    { label: "2 heures", value: 7200 },
                    { label: "3 heures", value: 10800 },
                    { label: "Jamais", value: 0 }
                ]

                Rectangle {
                    required property var modelData
                    readonly property bool actif: root.idleSuspendTimeout === modelData.value
                    width: idlePillText.implicitWidth + 18
                    height: 28
                    radius: Theme.globalRadius
                    color: actif ? Theme.accent : Theme.surfaceVariant
                    border.width: 1
                    border.color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.15)

                    Text {
                        id: idlePillText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: actif ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                        font.bold: actif
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.idleSuspendTimeout = modelData.value
                            root.runConfigCmd(["idle_timeout", String(modelData.value)])
                        }
                    }
                }
            }
        }
    }

    // ── Limite batterie 80% (portable) ─────────────────────────────
    Rectangle {
        visible: root.isLaptop
        width: parent.width
        height: 44
        radius: Theme.globalRadius
        color: root.batLimit80 ? Theme.success : Theme.surfaceVariant
        border.color: Theme.success
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: root.batLimit80 ? "Limite 80% : active" : "Activer la limite 80%"
            color: root.batLimit80 ? Theme.bg : Theme.fg
            font.pixelSize: Theme.textXs
            font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.batLimit80 = !root.batLimit80
                root.runConfigCmd(["battery", root.batLimit80 ? "80" : "100"])
            }
        }
    }

    // ── Fuseau & NTP ──────────────────────────────────────────────
    Rectangle {
        id: timezoneRow
        objectName: "timezoneRow"
        width: parent.width
        height: 46
        radius: Theme.globalRadius
        color: Theme.surfaceVariant

        Column {
            anchors.centerIn: parent
            spacing: 2
            Text {
                text: "Fuseau : " + root.timezoneStr
                color: Theme.fg
                font.pixelSize: Theme.textXs
                font.bold: true
            }
            Text {
                text: root.ntpSynced ? "✓ Horloge NTP synchronisée" : "⚠ NTP non synchronisé"
                color: root.ntpSynced ? Theme.success : Theme.warn
                font.pixelSize: Theme.textXs
            }
        }
    }

    // ── WiFi ──────────────────────────────────────────────────────
    Rectangle {
        width: parent.width
        height: 44
        radius: Theme.globalRadius
        color: openWifiMa.containsMouse ? Theme.accent : Theme.surfaceVariant
        border.color: Theme.accent
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "Ouvrir le panneau réseau / WiFi"
            color: openWifiMa.containsMouse ? Theme.bg : Theme.fg
            font.pixelSize: Theme.textSm
            font.bold: true
        }

        MouseArea {
            id: openWifiMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Theme.configPanelVisible = false
                Theme.activePopup = "wifi"
            }
        }
    }
}
}

// Mode nuit : le filtre chaud de l'écran. Une plage horaire vide
// signifie « à la main » — c'est l'icône de l'applet luminosité qui
// décide ; dès qu'une plage existe, le service s'en charge seul.
CollapsibleSection {
    id: secNuit
    objectName: "secNuit"
    title: "Mode nuit"
    summary: root.nuitAllumee ? ("allumé · " + root.nuitTemp + " K") : "éteint"
    icon: "weather-night"
    expanded: root.sectionOpen("systeme_nuit", false)
    onToggled: expanded => {
        root.setPanelSection("systeme_nuit", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("systeme_nuit")
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "Température appliquée par hyprsunset. Plus la valeur est basse, "
                + "plus l'écran tire vers l'orange."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        Row {
            spacing: 8

            Repeater {
                model: [2700, 3400, 4000, 5000]

                Rectangle {
                    required property var modelData
                    readonly property bool actif: root.nuitTemp === modelData
                    width: 74
                    height: 28
                    radius: Theme.globalRadius
                    color: actif ? Qt.alpha(Theme.accent, 0.28) : Theme.surfaceVariant
                    border.color: actif ? Theme.accent : Theme.accentMuted
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData + " K"
                        color: actif ? Theme.accent : Qt.alpha(Theme.fg, 0.75)
                        font.pixelSize: Theme.textXs
                        font.bold: actif
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reglerNuit(["temperature", String(modelData)])
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Plage horaire automatique — laisser vide pour commander à la main."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        Row {
            spacing: 8

            Rectangle {
                width: 76
                height: 28
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champNuitDe
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textXs
                    clip: true
                    Component.onCompleted: text = root.nuitDe
                    Connections {
                        target: root
                        function onNuitDeChanged() {
                            if (!champNuitDe.activeFocus) champNuitDe.text = root.nuitDe
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "→"
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 76
                height: 28
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champNuitA
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textXs
                    clip: true
                    Component.onCompleted: text = root.nuitA
                    Connections {
                        target: root
                        function onNuitAChanged() {
                            if (!champNuitA.activeFocus) champNuitA.text = root.nuitA
                        }
                    }
                }
            }

            Rectangle {
                width: 92
                height: 28
                radius: Theme.globalRadius
                color: survolNuit.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "Enregistrer"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: survolNuit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reglerNuit(["plage", champNuitDe.text.trim(), champNuitA.text.trim()])
                }
            }

            Rectangle {
                width: 74
                height: 28
                radius: Theme.globalRadius
                color: survolSansPlage.containsMouse ? Qt.alpha(Theme.error, 0.14) : "transparent"
                border.color: Qt.alpha(Theme.fg, 0.18)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "Aucune"
                    color: Qt.alpha(Theme.fg, 0.6)
                    font.pixelSize: Theme.textXs
                }

                MouseArea {
                    id: survolSansPlage
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        champNuitDe.text = ""
                        champNuitA.text = ""
                        root.reglerNuit(["plage", "", ""])
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: (root.nuitAllumee ? "Mode nuit allumé" : "Mode nuit éteint")
                + (root.nuitDe !== "" ? " · plage " + root.nuitDe + " → " + root.nuitA : " · manuel")
            color: root.nuitAllumee ? Theme.accent : Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Theme.textXs
        }
    }
}


// Captures d'écran : dossier d'enregistrement, lu par core/screenshot.sh.
CollapsibleSection {
    id: secCaptures
    objectName: "secCaptures"
    title: "Captures d'écran"
    summary: root.resumeChemin(root.screenshotsDir)
    icon: "screen-shot"
    expanded: root.sectionOpen("ecrans_captures", false)
    onToggled: expanded => {
        root.setPanelSection("ecrans_captures", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("ecrans_captures")
    }

// Dossier des captures d'écran (lu par core/screenshot.sh)
Row {
    id: screenshotsDirRow   // ancre de recherche
    objectName: "screenshotsDirRow"
    spacing: 8
    width: parent.width

    Text {
        width: 145
        anchors.verticalCenter: parent.verticalCenter
        text: "Screenshots"
        color: Theme.fg
        font.pixelSize: Theme.textSm
        font.bold: true
    }

    Rectangle {
        width: parent.width - 145 - 85 - 70 - 3 * 8
        height: 28
        color: Theme.bg
        radius: Theme.globalRadius
        border.color: shotsDirInput.activeFocus ? Theme.accent : Theme.surfaceVariant
        border.width: 1
        clip: true

        TextInput {
id: shotsDirInput
anchors.fill: parent
anchors.margins: 6
verticalAlignment: TextInput.AlignVCenter
text: Theme.screenshotsDir || root.screenshotsDir
color: Theme.fg
font.pixelSize: Theme.textXs
onAccepted: {
    if (shotsDirInput.text.trim() !== "") {
        root.runConfigCmd(["style", "screenshots_dir", shotsDirInput.text.trim()])
    }
}
        }
    }

    Rectangle {
        width: 70
        height: 28
        radius: Theme.globalRadius
        color: shotsPickMa2.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
        border.color: Theme.accentMuted
        border.width: 1

        Row {
anchors.centerIn: parent
spacing: 4

Icon {
    anchors.verticalCenter: parent.verticalCenter
    glyph: "folder"
    size: Math.round(Theme.iconSm * 0.78)
    color: shotsPickMa2.containsMouse ? Theme.bg : Theme.accent
    opacityLevel: 1
}

Text {
    anchors.verticalCenter: parent.verticalCenter
    text: "Choisir"
    color: shotsPickMa2.containsMouse ? Theme.bg : Theme.fg
    font.pixelSize: Theme.textXs
}
        }

        MouseArea {
id: shotsPickMa2
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: root.ouvrirSelecteur("screenshots_dir", "Dossier des captures d'écran", shotsDirInput.text)
        }
    }

    Rectangle {
        width: 85
        height: 28
        radius: Theme.globalRadius
        color: shotsDirSaveMa.containsMouse ? Theme.accentMuted : Theme.accent

        Text {
anchors.centerIn: parent
text: "Appliquer"
color: Theme.bg
font.pixelSize: Theme.textXs
font.bold: true
        }

        MouseArea {
id: shotsDirSaveMa
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: {
    if (shotsDirInput.text.trim() !== "") {
        root.runConfigCmd(["style", "screenshots_dir", shotsDirInput.text.trim()])
    }
}
        }
    }
}
}

// Mise à jour du shell : la version posée, celle publiée sur GitHub, et les
// gestes qui en découlent. « Mettre à jour » ouvre un terminal au lieu d'agir
// en douce : le déploiement redémarre le shell, et une commande qui s'exécute
// sans qu'on la voie est une commande qu'on ne peut pas interrompre.
CollapsibleSection {
    id: secMaj
    objectName: "secMaj"
    title: "Mise à jour du shell"
    summary: bloc.majResume
    icon: "download"
    expanded: root.sectionOpen("systeme_maj", false)
    onToggled: expanded => {
        root.setPanelSection("systeme_maj", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("systeme_maj")
        if (expanded && bloc.majLocale === "") bloc.verifierMaj(false)
    }

Column {
    width: parent.width
    spacing: 10

    // Version installée + état, sur une carte : c'est la ligne que la recherche
    // du panneau vise (`shellMajRow`).
    Rectangle {
        id: shellMajRow
        objectName: "shellMajRow"
        width: parent.width
        height: 62
        radius: Theme.globalRadius
        color: Theme.surfaceVariant
        border.color: bloc.majDisponible ? Theme.accent : Theme.accentMuted
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 3

            Row {
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bloc.majLocale !== "" ? bloc.majLocale : "version inconnue"
                    color: Theme.fg
                    font.pixelSize: Theme.textMd
                    font.bold: true
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: majPilule.implicitWidth + 16
                    height: 18
                    radius: 4
                    color: bloc.majDisponible ? Theme.accent : Theme.surfaceBg
                    border.width: 1
                    border.color: bloc.majDisponible ? Theme.accent : Qt.alpha(Theme.fg, 0.2)

                    Text {
                        id: majPilule
                        anchors.centerIn: parent
                        text: bloc.majOccupe
                              ? "vérification…"
                              : (bloc.majDisponible ? bloc.majDistante + " disponible"
                              : (bloc.majEtat === "a_jour" ? "à jour"
                              : (bloc.majEtat === "inconnu" ? "état inconnu" : "…")))
                        color: bloc.majDisponible ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                        font.bold: bloc.majDisponible
                    }
                }
            }

            Text {
                width: parent.width
                text: bloc.majDetail
                color: Qt.alpha(Theme.fg, 0.7)
                font.pixelSize: Theme.textXs
                elide: Text.ElideRight
            }
        }
    }

    Row {
        width: parent.width
        spacing: 8

        // Revérifier tout de suite : `--force` passe outre les 280 minutes.
        Rectangle {
            width: 158
            height: 30
            radius: Theme.globalRadius
            color: majVerifMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
            border.width: 1
            border.color: Theme.accentMuted

            Row {
                anchors.centerIn: parent
                spacing: 6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "refresh"
                    size: Math.round(Theme.iconSm * 0.8)
                    color: Theme.accent
                    opacityLevel: 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bloc.majOccupe ? "Vérification…" : "Vérifier maintenant"
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                }
            }

            MouseArea {
                id: majVerifMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !bloc.majOccupe
                onClicked: bloc.verifierMaj(true)
            }
        }

        // La même ligne que pour une première installation, ouverte dans le
        // terminal par défaut (`core/maj_terminal.sh` sait lequel existe).
        Rectangle {
            width: 160
            height: 30
            radius: Theme.globalRadius
            color: majActionMa.containsMouse ? Theme.accentMuted : Theme.accent

            Row {
                anchors.centerIn: parent
                spacing: 6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "download"
                    size: Math.round(Theme.iconSm * 0.8)
                    color: Theme.bg
                    opacityLevel: 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mettre à jour"
                    color: Theme.bg
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }
            }

            MouseArea {
                id: majActionMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["bash", Quickshell.shellPath("core/maj_terminal.sh"),
                                                    bloc.majCommande])
            }
        }

        // Pour poser le shell sur une autre machine : la ligne, dans le
        // presse-papiers, sans avoir à la retaper.
        Rectangle {
            width: 132
            height: 30
            radius: Theme.globalRadius
            color: majCopieMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
            border.width: 1
            border.color: Theme.accentMuted

            Text {
                anchors.centerIn: parent
                text: bloc.majCopie !== "" ? "Ligne copiée" : "Copier la ligne"
                color: Theme.fg
                font.pixelSize: Theme.textXs
            }

            MouseArea {
                id: majCopieMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy',
                                             "sh", bloc.majCommande])
                    bloc.majCopie = "copié"
                    finCopie.restart()
                }
            }
        }
    }

    Text {
        width: parent.width
        text: "Installation et mise à jour passent par la même ligne, vérifiée toutes les "
              + bloc.intervalleMin + " minutes."
        color: Qt.alpha(Theme.fg, 0.5)
        font.pixelSize: Theme.textXs
        wrapMode: Text.WordWrap
    }
}
}
