import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// APPLET RÉSEAU — le Wi-Fi, son réseau, son panneau.
//
// Composant QML : il emporte tout ce qui faisait vivre le bouton réseau de
// l'îlot droit — l'état, la lecture périodique, le balayage, la connexion et le
// panneau de gestion. L'îlot n'en sait plus rien.
//
// La lecture passe par `system_service.py info` toutes les 10 s plutôt que par
// le processus système de l'îlot : l'applet doit pouvoir vivre seul, dans
// n'importe quel îlot, sans dépendre d'un voisin qui l'interrogerait pour lui.
Item {
    id: root
    property var applet: ({})
    property real echelle: 1.0

    // Barre de côté : une seule icône, agrandie, et pas de texte — une valeur
    // coupée au milieu se lit mal. Le nom de l'applet est au survol, le détail
    // dans le popup. `Applet.qml` pose la propriété si elle existe.
    property bool verticale: false
    readonly property int tailleIcone: Math.round(Math.max(11, Math.round(Theme.iconSm * echelle))
                                                  * (verticale ? 1.45 : 1))

    property bool wifiConnected: (Theme.systemInfo && Theme.systemInfo.wifi && Theme.systemInfo.wifi.connected) ? true : false
    property string wifiSsid: (Theme.systemInfo && Theme.systemInfo.wifi && Theme.systemInfo.wifi.ssid) ? String(Theme.systemInfo.wifi.ssid) : ""
    property int wifiSignal: (Theme.systemInfo && Theme.systemInfo.wifi && Theme.systemInfo.wifi.signal) ? Number(Theme.systemInfo.wifi.signal) : 0
    property string netType: (Theme.systemInfo && Theme.systemInfo.wifi && Theme.systemInfo.wifi.type) ? String(Theme.systemInfo.wifi.type) : "wifi"

    // État du panneau
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string expandedSsid: ""
    property string connectingStatus: ""
    property bool connectingBusy: false
    property bool wifiScanQueued: false
    property bool wifiScanQueuedRescan: false

    readonly property bool ouvert: Theme.activePopup === "applet:reseau"

    implicitWidth: netRow.implicitWidth + Math.round(12 * echelle)
    implicitHeight: Math.max(22, Math.round(28 * echelle))

    function synchroniserSystemInfo() {
        const w = (Theme.systemInfo && Theme.systemInfo.wifi) || null
        if (!w) return
        root.wifiConnected = Boolean(w.connected)
        root.wifiSsid = String(w.ssid || "")
        root.wifiSignal = Number(w.signal || 0)
        root.netType = String(w.type || "wifi")
    }

    function signalIconFor(sig, connected) {
        if (!connected && sig <= 0) return "wifi-none"
        if (sig >= 75) return "wifi-full"
        if (sig >= 50) return "wifi-high"
        if (sig >= 25) return "wifi-medium"
        return "wifi-low"
    }

    function rafraichir() {
        Theme.rafraichirSystemInfo()
    }

    function startWifiScan(rescan) {
        const args = ["python3", Quickshell.shellPath("core/system_service.py"), "wifi"]
        if (!rescan) args.push("--no-rescan")
        wifiScanProc.command = args
        wifiScanProc.running = true
    }

    function scanWifi(rescan) {
        wifiScanning = true
        if (wifiScanProc.running) {
            wifiScanQueued = true
            wifiScanQueuedRescan = wifiScanQueuedRescan || Boolean(rescan)
            return
        }
        startWifiScan(rescan)
    }

    function connectToWifi(ssid, password) {
        if (wifiConnectProc.running) return
        connectingBusy = true
        connectingStatus = "Connexion à " + ssid + "..."
        wifiConnectProc.command = [
            "python3",
            Quickshell.shellPath("core/system_service.py"),
            "wifi_connect",
            ssid,
            password || ""
        ]
        wifiConnectProc.running = true
    }

    // Amorçage : l'état Bluetooth est lu une fois au démarrage, pour que le
    // panneau s'ouvre déjà rempli (sinon il est vide le temps d'un aller-retour).
    Component.onCompleted: {
        root.synchroniserSystemInfo()
        root.lireBluetooth()
    }

    Connections {
        target: Theme
        function onSystemInfoChanged() {
            root.synchroniserSystemInfo()
        }
    }

    Process {
        id: wifiScanProc
        onExited: {
            if (root.wifiScanQueued) {
                const rescan = root.wifiScanQueuedRescan
                root.wifiScanQueued = false
                root.wifiScanQueuedRescan = false
                root.startWifiScan(rescan)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.wifiScanQueued) return // périmé : un balayage plus récent est en file
                root.wifiScanning = false
                try {
                    root.wifiNetworks = JSON.parse(text.trim())
                } catch (e) {
                    root.wifiNetworks = []
                }
            }
        }
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.connectingBusy = false
                try {
                    const res = JSON.parse(text.trim())
                    if (res.success) {
                        root.connectingStatus = "✓ Connecté à " + res.ssid
                        root.expandedSsid = ""
                        root.rafraichir()
                        root.scanWifi(false)
                    } else {
                        root.connectingStatus = "✕ Échec : " + (res.message || "Mot de passe incorrect")
                    }
                } catch (e) {
                    root.connectingStatus = "✕ Erreur de connexion"
                }
            }
        }
    }

    // ── bouton de barre ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.globalRadius
        color: root.ouvert
            ? Theme.accent
            : (netMa.containsMouse ? Theme.surfaceVariant : "transparent")

        Behavior on color { ColorAnimation { duration: 140 } }

        Row {
            id: netRow
            anchors.centerIn: parent
            spacing: Math.round(6 * echelle)

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.netType === "ethernet"
                    ? "ethernet"
                    : root.signalIconFor(root.wifiSignal, root.wifiConnected)
                size: root.tailleIcone
                color: root.ouvert ? Theme.bg : (root.wifiConnected ? Theme.accent : Theme.error)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Une bande de côté ne tient pas un SSID : icône seule, et le
                // nom du réseau au survol comme dans le popup.
                visible: !root.verticale
                text: root.wifiConnected
                    ? (root.wifiSsid !== "" ? root.wifiSsid : "WiFi")
                    : "Déconnecté"
                color: root.ouvert ? Theme.bg : Theme.fg
                font.pixelSize: Math.round(Theme.textSm * echelle)
                font.bold: root.wifiConnected
            }
        }

        MouseArea {
            id: netMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Theme.togglePopup("applet:reseau")
        }
    }

    // SUB-SECTION 7.1: INTERACTIVE WIFI MANAGEMENT POPUP
    // ────────────────────────────────────────────────────────────────────────
    Popup {
        ancre: root
        ile: String(root.applet.ile || "")
        alignement: "centre"
        ecart: 5   // quelques pixels plus bas : son item d'ancrage est plus court
        id: wifiPanelPopup
        implicitWidth: 320
        // WiFi 200 + filet + Bluetooth : la hauteur suit le contenu utile.
        implicitHeight: 455
        color: "transparent"
        visible: root.ouvert
        grabFocus: visible && root.expandedSsid !== ""

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Theme.pillRadius
            border.width: 0

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header + Rescan button
                Item {
                    width: parent.width
                    height: 26

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space2

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "wifi"
                            size: Theme.iconSm
                            color: Theme.accent
                            opacityLevel: 1
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Réseaux disponibles"
                            color: Theme.fg
                            font.pixelSize: Theme.textLg
                            font.bold: true
                        }
                    }

                    Rectangle {
                        width: 68
                        height: 24
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: Theme.globalRadius
                        color: rescanMa.containsMouse ? Theme.accent : Theme.surfaceVariant

                        Text {
                            anchors.centerIn: parent
                            text: root.wifiScanning ? "Scan..." : "↻ Scan"
                            color: rescanMa.containsMouse ? Theme.bg : Theme.fg
                            font.pixelSize: Theme.textXs
                            font.bold: true
                        }

                        MouseArea {
                            id: rescanMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scanWifi(true)
                        }
                    }
                }

                // Connection feedback banner
                Rectangle {
                    visible: root.connectingStatus !== ""
                    width: parent.width
                    height: 26
                    radius: Theme.globalRadius
                    color: Theme.surfaceVariant
                    border.color: root.connectingStatus.indexOf("✓") === 0
                        ? Theme.success
                        : (root.connectingStatus.indexOf("✕") === 0 ? Theme.error : Theme.info)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.connectingStatus
                        color: Theme.fg
                        font.pixelSize: Theme.textXs
                        elide: Text.ElideRight
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Scrollable list of WiFi networks with inline password input under clicked SSID
                Flickable {
                    id: wifiFlick
                    width: parent.width
                    // Deux réseaux + la ligne de mot de passe : au-delà, on fait
                    // défiler. Le bloc Bluetooth reste ainsi juste sous le filet.
                    height: root.connectingStatus !== "" ? 175 : 200
                    contentWidth: width
                    contentHeight: networkListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: networkListCol
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: !root.wifiScanning && root.wifiNetworks.length === 0
                            text: "Aucun réseau WiFi détecté."
                            color: Qt.alpha(Theme.fg, 0.7)
                            font.pixelSize: Theme.textSm
                            font.italic: true
                        }

                        Repeater {
                            model: root.wifiNetworks

                            Column {
                                id: netItemCol
                                required property var modelData
                                width: networkListCol.width
                                spacing: 0

                                readonly property bool isExpanded: root.expandedSsid === modelData.ssid

                                // Network Row (Signal icon + SSID + Connected/Lock status)
                                Rectangle {
                                    width: parent.width
                                    height: 36
                                    radius: Theme.globalRadius
                                    color: netItemCol.modelData.in_use
                                        ? Qt.alpha(Theme.accent, 0.22)
                                        : (netRowMa.containsMouse || netItemCol.isExpanded ? Theme.surfaceVariant : Qt.alpha(Theme.surfaceVariant, 0.45))
                                    border.color: netItemCol.modelData.in_use
                                        ? Theme.accent
                                        : (netItemCol.isExpanded ? Theme.accentMuted : "transparent")
                                    border.width: (netItemCol.modelData.in_use || netItemCol.isExpanded) ? 1 : 0

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // Dynamic signal strength icon at start of line
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: root.signalIconFor(netItemCol.modelData.signal, true)
                                            size: Theme.iconSm
                                            color: netItemCol.modelData.signal >= 60
                                                ? Theme.success
                                                : (netItemCol.modelData.signal >= 30 ? Theme.warn : Theme.error)
                                        }

                                        // Network SSID
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: netItemCol.modelData.ssid
                                            color: Theme.fg
                                            font.pixelSize: Theme.textSm
                                            font.bold: netItemCol.modelData.in_use
                                            elide: Text.ElideRight
                                            width: 175
                                        }
                                    }

                                    // Right badge: Signal % + Connected / Lock icon
                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: netItemCol.modelData.in_use
                                                ? "Connecté"
                                                : (netItemCol.modelData.signal + "%")
                                            color: netItemCol.modelData.in_use ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                                            font.pixelSize: Theme.textXs
                                            font.bold: netItemCol.modelData.in_use
                                        }

                                        Icon {
                                            visible: Boolean(netItemCol.modelData.secured)
                                            anchors.verticalCenter: parent.verticalCenter
                                            glyph: "lock"
                                            size: 10
                                            color: Theme.fg
                                        }
                                    }

                                    MouseArea {
                                        id: netRowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (netItemCol.modelData.in_use) return
                                            if (!netItemCol.modelData.secured) {
                                                // Open network -> connect immediately
                                                root.connectToWifi(netItemCol.modelData.ssid, "")
                                            } else {
                                                // Toggle inline password field right below this network
                                                root.expandedSsid = netItemCol.isExpanded ? "" : netItemCol.modelData.ssid
                                            }
                                        }
                                    }
                                }

                                // Inline Password Box directly underneath the clicked network
                                Rectangle {
                                    id: inlinePassBox
                                    visible: netItemCol.isExpanded
                                    width: parent.width
                                    height: visible ? 44 : 0
                                    color: Theme.surfaceVariant
                                    radius: Theme.globalRadius
                                    border.color: Theme.accentMuted
                                    border.width: 1

                                    onVisibleChanged: {
                                        if (visible) {
                                            passInput.text = ""
                                            passInput.forceActiveFocus()
                                        }
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 6

                                        Rectangle {
                                            width: parent.width - 82
                                            height: parent.height
                                            color: Theme.bg
                                            radius: Theme.globalRadius
                                            border.color: passInput.activeFocus ? Theme.accent : Theme.surfaceVariant
                                            border.width: 1

                                            Text {
                                                visible: passInput.text.length === 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                text: "Mot de passe WiFi (ou vide si connu)..."
                                                color: Qt.alpha(Theme.fg, 0.45)
                                                font.pixelSize: Theme.textXs
                                            }

                                            TextInput {
                                                id: passInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                verticalAlignment: TextInput.AlignVCenter
                                                echoMode: TextInput.Password
                                                focus: netItemCol.isExpanded
                                                selectByMouse: true
                                                color: Theme.fg
                                                font.pixelSize: Theme.textSm
                                                clip: true
                                                onAccepted: root.connectToWifi(netItemCol.modelData.ssid, passInput.text)
                                                Keys.onEscapePressed: root.expandedSsid = ""
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.IBeamCursor
                                                acceptedButtons: Qt.NoButton
                                            }
                                        }

                                        Rectangle {
                                            width: 74
                                            height: parent.height
                                            radius: Theme.globalRadius
                                            color: connectBtnMa.containsMouse ? Theme.accentMuted : Theme.accent

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Joindre"
                                                color: Theme.bg
                                                font.pixelSize: Theme.textXs
                                                font.bold: true
                                            }

                                            MouseArea {
                                                id: connectBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.connectToWifi(netItemCol.modelData.ssid, passInput.text)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Bluetooth ────────────────────────────────────────────────
                // Respiration puis filet : deux familles distinctes (réseaux,
                // périphériques) ne doivent pas se lire comme une seule liste.
                Item {
                    width: parent.width
                    height: 16

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.12)
                    }
                }

                Item {
                    width: parent.width
                    height: 22
                    visible: root.btPresent

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "bluetooth"
                            size: Theme.iconSm
                            color: root.btAllume ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Bluetooth"
                            color: root.btAllume ? Theme.fg : Qt.alpha(Theme.fg, 0.55)
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }
                    }

                    // Interrupteur de l'adaptateur : même vocabulaire visuel que
                    // les autres bascules du panneau (pilule pleine quand actif).
                    Rectangle {
                        id: btSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 20
                        radius: 10
                        color: root.btAllume ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            y: 2
                            x: root.btAllume ? parent.width - width - 2 : 2
                            color: root.btAllume ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                            Behavior on x { NumberAnimation { duration: 130 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.btCommande(["basculer"])
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.btPresent && root.btAllume && root.btAppareils.length === 0
                    text: "Aucun appareil appairé."
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Theme.textXs
                    font.italic: true
                }

                Column {
                    width: parent.width
                    spacing: 4
                    visible: root.btPresent && root.btAllume
                    height: Math.min(implicitHeight, 96)
                    clip: true

                    Repeater {
                        model: root.btAppareils

                        Item {
                            required property var modelData
                            width: parent.width
                            height: 26

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: btSurvol.containsMouse ? Qt.alpha(Theme.accent, 0.14) : "transparent"
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.right: etatBt.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.nom || modelData.mac || "")
                                color: modelData.connecte ? Theme.fg : Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: Theme.textXs
                                elide: Text.ElideRight
                            }

                            Text {
                                id: etatBt
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.connecte ? "connecté" : "connecter"
                                color: modelData.connecte ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
                                font.pixelSize: Theme.textXs
                            }

                            MouseArea {
                                id: btSurvol
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.btCommande([modelData.connecte ? "deconnecter" : "connecter",
                                                            String(modelData.mac || "")])
                            }
                        }
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────

    // Bluetooth : même panneau que le WiFi, bloc séparé. Tout vient de
    // core/bluetooth_service.py — le shell n'invente aucun état.
    property bool btPresent: false
    property bool btAllume: false
    property var btAppareils: []

    function majBluetooth(txt) {
        try {
            const d = JSON.parse(txt.trim())
            root.btPresent = d.present === true
            root.btAllume = d.allume === true
            root.btAppareils = d.appaires || []
        } catch (e) { /* réponse partielle : on garde l'état précédent */ }
    }

    function lireBluetooth() {
        if (btProc.running) return
        btProc.running = true
    }

    function btCommande(args) {
        btAction.command = ["python3", Quickshell.shellPath("core/bluetooth_service.py")].concat(args)
        btAction.running = true
    }

    Process {
        id: btProc
        command: ["python3", Quickshell.shellPath("core/bluetooth_service.py"), "etat"]
        stdout: StdioCollector {
            onStreamFinished: root.majBluetooth(text)
        }
    }

    Process {
        id: btAction
        stdout: StdioCollector {
            onStreamFinished: root.majBluetooth(text)
        }
    }

    property bool pretGrab: false
    onOuvertChanged: {
        if (root.ouvert) { root.scanWifi(false); root.lireBluetooth(); delaiGrab.restart() }
        else root.pretGrab = false
    }
    Timer {
        id: delaiGrab
        interval: 150
        onTriggered: root.pretGrab = true
    }

    HyprlandFocusGrab {
        active: root.ouvert && root.pretGrab
        windows: Theme.fenetresGrab(wifiPanelPopup, root)
        onCleared: if (root.ouvert) Theme.activePopup = ""
    }
}
