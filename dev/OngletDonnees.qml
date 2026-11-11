import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Onglet « Données & Comptes » du panneau de configuration, sorti de config_panel.qml.
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
    visible: root ? root.currentTab === 7 : false
    width: mainFlickable ? mainFlickable.width : 0
    property var ncEtatProc

    readonly property var sections: ({
        "widgets_api": secApiKeys,
        "donnees_localisation": secLocalisation,
        "quickshell_calendrier": secCalendrier,
        "widgets_homelab": secHomelab,
        "taches_fichiers": secTaches
    })

    readonly property var cibles: ({
        "secLocalisation": secLocalisation
    })
spacing: 12


// Tiroir : fournisseurs d'IA, une ligne par fournisseur. Les clés
// ne sortent jamais du shell : le fichier est en mode 600.
CollapsibleSection {
    id: secApiKeys
    objectName: "secApiKeys"
    title: "Accès API"
    summary: Object.keys(root.apiKeys).length + " clés"
    icon: "lock"
    expanded: root.sectionOpen("widgets_api", false)
    onToggled: expanded => {
        root.setPanelSection("widgets_api", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_api")
    }

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            text: "Une ligne par fournisseur LLM (core/llm_providers.json). La clé est "
                + "rangée dans core/secrets.json et n'apparaît jamais en clair."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        // Une ligne par fournisseur déclaré : plus de bloc à recopier
        // quand on ajoute OpenAI, Claude ou Gemini.
        Repeater {
            model: root.llmProviders

            Column {
                id: fournisseur
                required property var modelData
                width: parent.width
                spacing: 6
                // L'état est par fournisseur : « clé refusée » doit
                // rester sous la ligne qui a échoué.
                readonly property string etat: root.cleEtats[modelData.id] || ""

                Text {
                    width: parent.width
                    text: modelData.label + " — " + (modelData.summary || "") + "."
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }

                // Un fournisseur local (quota lu sur la machine) n'a
                // pas de clé : afficher un champ vide laisserait croire
                // qu'il en manque une.
                Text {
                    width: parent.width
                    visible: (modelData.key || "") === ""
                    text: "aucune clé — la donnée est lue localement"
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.text2xs
                    font.italic: true
                }

                Row {
                    width: parent.width
                    spacing: 10
                    visible: (modelData.key || "") !== ""

                    Rectangle {
                        width: parent.width - 130
                        height: 32
                        color: Theme.bg
                        radius: Theme.globalRadius
                        border.color: champ.activeFocus ? Theme.accent : Theme.surfaceVariant
                        border.width: 1

                        TextInput {
                            id: champ
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.info
                            font.pixelSize: Theme.textSm
                            echoMode: TextInput.Password
                            selectByMouse: true
                            onAccepted: root.enregistrerCleApi(fournisseur.modelData, champ)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            visible: champ.text.length === 0
                            text: root.apiKeys[fournisseur.modelData.key]
                                  ? "Clé enregistrée (…" + root.apiKeys[fournisseur.modelData.key].tail + ")"
                                  : (fournisseur.modelData.hint || "clé d'API")
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.pixelSize: Theme.textXs
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 32
                        radius: Theme.globalRadius
                        color: enregistrerCle.containsMouse ? Theme.accentMuted : Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Enregistrer"
                            color: Theme.bg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }

                        MouseArea {
                            id: enregistrerCle
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.enregistrerCleApi(fournisseur.modelData, champ)
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: fournisseur.etat !== ""
                    text: fournisseur.etat
                    color: (fournisseur.etat.startsWith("clé acceptée")
                            || fournisseur.etat.startsWith("enregistrée"))
                           ? Theme.success : Theme.error
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}

// Tiroir : localisation de l'utilisateur. Un seul endroit pour « où
// suis-je » : l'applet et le widget météo, l'horloge et le calendrier
// lisent les clés user_location_* de style_vars.json.
CollapsibleSection {
    id: secLocalisation
    objectName: "secLocalisation"
    title: "Localisation"
    summary: root.timezoneStr
    icon: "cloud"
    expanded: root.sectionOpen("donnees_localisation", false)
    onToggled: expanded => {
        root.setPanelSection("donnees_localisation", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("donnees_localisation")
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "Ville et coordonnées lues par les applets et widgets qui ont besoin de "
                + "savoir où l'on est — la météo d'abord, mais aussi l'horloge et le calendrier "
                + "pour le fuseau. Sans coordonnées, ils annoncent « localisation non réglée » "
                + "plutôt que d'inventer une position."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
            height: contentHeight
        }

        // Ville + bouton de vérification (géocodage Open-Meteo, sans clé).
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 76
                anchors.verticalCenter: parent.verticalCenter
                text: "Ville"
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: parent.width - 76 - 8 - verifier.width - 8
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champVille
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textSm
                    clip: true
                    text: Theme.userLocationVille
                    onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                              champLon.text, champTz.text)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: "Paris, France"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: Theme.textSm
                    }
                }
            }

            Rectangle {
                id: verifier
                width: 96
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: geocodage.running ? "…" : "Vérifier"
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.geocoder(champVille.text)
                }
            }
        }

        // Latitude / longitude : remplies par « Vérifier », modifiables à la main.
        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 76
                anchors.verticalCenter: parent.verticalCenter
                text: "Latitude"
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 120
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champLat
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    text: Theme.userLocationSet ? String(Theme.userLocationLat) : ""
                    onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                              champLon.text, champTz.text)
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Longitude"
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 120
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champLon
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    text: Theme.userLocationSet ? String(Theme.userLocationLon) : ""
                    onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                              champLon.text, champTz.text)
                }
            }
        }

        Row {
            width: parent.width
            spacing: 8

            Text {
                width: 76
                anchors.verticalCenter: parent.verticalCenter
                text: "Fuseau"
                color: Qt.alpha(Theme.fg, 0.75)
                font.pixelSize: Theme.textXs
            }

            Rectangle {
                width: 200
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champTz
                    anchors.fill: parent
                    anchors.margins: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textSm
                    text: Theme.userLocationTz
                    onAccepted: root.enregistrerLocalisation(champVille.text, champLat.text,
                                                              champLon.text, champTz.text)
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Europe/Paris"
                color: Qt.alpha(Theme.fg, 0.35)
                font.pixelSize: Theme.text2xs
            }
        }

        Text {
            id: etatLocalisation
            width: parent.width
            text: Theme.userLocationSet
                  ? "Réglée : " + (Theme.userLocationVille || "sans nom")
                    + " (" + Theme.userLocationLat + ", " + Theme.userLocationLon + ")"
                    + (Theme.userLocationTz ? " · " + Theme.userLocationTz : "")
                  : "Non réglée : les applets et widgets qui en dépendent le disent à l'écran."
            color: Theme.userLocationSet ? Qt.alpha(Theme.fg, 0.6) : Qt.alpha(Theme.warn, 0.85)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
            height: contentHeight
        }

        // Géocodage : le service météo sait déjà le faire, on lui demande
        // la même chose que pour un `--city`, et il rend le fuseau en plus.
        Process {
            id: geocodage
            stdout: StdioCollector {
                onStreamFinished: {
                    let d = null
                    try { d = JSON.parse(String(text).trim()) } catch (e) { d = null }
                    if (!d || !d.ok) {
                        etatLocalisation.text = "Ville introuvable : "
                            + String((d && d.error) || "réponse illisible")
                        return
                    }
                    champVille.text = d.libelle || d.ville || ""
                    champLat.text = String(d.lat)
                    champLon.text = String(d.lon)
                    champTz.text = d.tz || ""
                    root.enregistrerLocalisation(champVille.text, champLat.text,
                                                 champLon.text, champTz.text)
                }
            }
        }
    }
}

// Tiroir : identifiants du calendrier Nextcloud. Sert à l'applet
// « calendrier » comme au widget « date » — même fichier, même
// saisie. Le secret n'est jamais réaffiché : place-holder avec ses
// quatre derniers caractères, et un champ vide ne l'efface pas.
CollapsibleSection {
    id: secCalendrier
    objectName: "secCalendrier"
    title: "Calendrier Nextcloud"
    summary: root.ncStatut !== "" ? root.ncStatut : "non configuré"
    icon: "calendar"
    expanded: root.sectionOpen("quickshell_calendrier", false)
    onToggled: expanded => {
        root.setPanelSection("quickshell_calendrier", expanded)
        if (expanded) {
            if (Theme.panelAccordion) root.fermerAutresTiroirs("quickshell_calendrier")
            ncEtatProc.running = true
        }
    }
    Component.onCompleted: ncEtatProc.running = true

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            text: "Le calendrier lit le calendrier Nextcloud par CalDAV. "
                  + "Le mot de passe demandé est un mot de passe "
                  + "d'application, pas celui du compte."
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Math.max(9, Theme.textXs - 1)
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: [
                { cle: "url", libelle: "Adresse du serveur",
                  exemple: "https://cloud.exemple.org" },
                { cle: "user", libelle: "Identifiant",
                  exemple: "prenom.nom" },
                { cle: "app_password", libelle: "Mot de passe d'application",
                  exemple: "xxxxx-xxxxx-xxxxx-xxxxx" }
            ]

            Column {
                id: champCol
                required property var modelData
                width: parent.width
                spacing: 5

                // Les deux premiers champs arrivent pré-remplis ; le mot
                // de passe jamais, on ne fait qu'annoncer sa fin.
                readonly property string initiale: modelData.cle === "url"
                    ? String(root.ncEtat.url || "")
                    : (modelData.cle === "user" ? String(root.ncEtat.user || "") : "")
                readonly property bool secret: modelData.cle === "app_password"
                readonly property string rappel: secret
                    ? (root.ncEtat.mot_de_passe_present
                       ? "Enregistré (…" + String(root.ncEtat.mot_de_passe_fin || "") + ")"
                       : "aucun mot de passe") + " — laisser vide pour ne pas changer"
                    : String(modelData.exemple)

                Text {
                    text: modelData.libelle
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                }

                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: parent.width - 130
                        height: 32
                        color: Theme.bg
                        radius: Theme.globalRadius
                        border.color: ncChamp.activeFocus ? Theme.accent : Theme.surfaceVariant
                        border.width: 1

                        TextInput {
                            id: ncChamp
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.info
                            font.pixelSize: Theme.textSm
                            selectByMouse: true
                            echoMode: champCol.secret ? TextInput.Password : TextInput.Normal
                            text: champCol.initiale
                            onAccepted: root.enregistrerNc(champCol.modelData.cle, text)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            width: parent.width - 20
                            visible: ncChamp.text.length === 0
                            text: champCol.rappel
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.pixelSize: Theme.textXs
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        width: 120
                        height: 32
                        radius: Theme.globalRadius
                        color: ncEnreg.containsMouse ? Theme.accentMuted : Theme.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Enregistrer"
                            color: Theme.bg
                            font.pixelSize: Theme.textSm
                            font.bold: true
                        }

                        MouseArea {
                            id: ncEnreg
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.enregistrerNc(champCol.modelData.cle, ncChamp.text)
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.ncStatut !== ""
            text: root.ncStatut
            color: root.ncStatut.startsWith("Enregistré") ? Theme.success : Theme.error
            font.pixelSize: Theme.textXs
        }
    }
}


// Homelab : l'applet et le widget interrogent l'API Proxmox. L'URL et
// l'identifiant du jeton ne sont pas secrets et vivent dans
// homelab.json ; le secret du jeton suit le chemin des clés d'API.
CollapsibleSection {
    id: secHomelab
    objectName: "secHomelab"
    title: "Homelab (Proxmox)"
    summary: root.homelabUrl !== "" ? root.resumeChemin(root.homelabUrl) : "non configuré"
    icon: "cloud-check"
    expanded: root.sectionOpen("widgets_homelab", false)
    onToggled: expanded => {
        root.setPanelSection("widgets_homelab", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("widgets_homelab")
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            width: parent.width
            text: "L'applet et le widget lisent l'état du nœud et des machines virtuelles. "
                + "Dans Proxmox : Datacenter → Permissions → API Tokens, rôle PVEAuditor, "
                + "puis décocher « Privilege Separation » ou donner les droits en lecture seule."
            color: Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: Theme.textXs
            wrapMode: Text.WordWrap
        }

        // ── URL ────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: parent.width - enregUrl.width - 8
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champPveUrl
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textSm
                    clip: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: "https://pve.lan:8006"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: Theme.textSm
                    }
                    Component.onCompleted: text = root.homelabUrl
                    Connections {
                        target: root
                        function onHomelabUrlChanged() {
                            if (!champPveUrl.activeFocus) champPveUrl.text = root.homelabUrl
                        }
                    }
                }
            }

            Rectangle {
                id: enregUrl
                width: 92
                height: 30
                radius: 6
                color: survolUrl.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "Enregistrer"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: survolUrl
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.homelabSet("proxmox_url", champPveUrl.text.trim())
                }
            }
        }

        // ── identifiant du jeton (hermes@pam!applet) ───────────
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: parent.width - enregId.width - 8
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champPveId
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textSm
                    clip: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: "utilisateur@pam!nom-du-jeton"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: Theme.textSm
                    }
                    Component.onCompleted: text = root.homelabTokenId
                    Connections {
                        target: root
                        function onHomelabTokenIdChanged() {
                            if (!champPveId.activeFocus) champPveId.text = root.homelabTokenId
                        }
                    }
                }
            }

            Rectangle {
                id: enregId
                width: 92
                height: 30
                radius: 6
                color: survolId.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "Enregistrer"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: survolId
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.homelabSet("proxmox_token_id", champPveId.text.trim())
                }
            }
        }

        // ── secret du jeton ────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: parent.width - enregSecret.width - 8
                height: 30
                radius: 6
                color: Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                TextInput {
                    id: champPveSecret
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    font.pixelSize: Theme.textSm
                    clip: true
                    echoMode: TextInput.Password
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: root.homelabTokenPresent
                              ? "enregistré (…" + root.homelabTokenTail + ") — collez-en un nouveau pour le remplacer"
                              : "secret du jeton (uuid)"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: Theme.textSm
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            Rectangle {
                id: enregSecret
                width: 92
                height: 30
                radius: 6
                color: survolSecret.containsMouse ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "Enregistrer"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: survolSecret
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.homelabSetSecret(champPveSecret.text)
                        champPveSecret.text = ""
                    }
                }
            }
        }
    }
}

// ── Tâches : fichiers suivis par l'applet et le widget ──────────
// Le widget voit tous ces fichiers ; l'applet n'en montre qu'un, et
// c'est celui marqué « affiché ». Rien ici n'est un réglage du dépôt :
// les chemins vivent dans core/todo.json, sur la machine.
CollapsibleSection {
    id: secTaches
    objectName: "secTaches"
    title: "Tâches — fichiers suivis"
    summary: root.todoFichiers.length + " fichiers"
    icon: "check"
    expanded: root.sectionOpen("taches_fichiers", false)
    onToggled: expanded => {
        root.setPanelSection("taches_fichiers", expanded)
        if (expanded && Theme.panelAccordion) root.fermerAutresTiroirs("taches_fichiers")
    }

    Column {
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            text: "Chaque ligne `- [ ] **Titre**` d'un fichier Markdown devient "
                  + "une case à cocher. Cocher dans le panneau commande l'étape "
                  + "à l'agent, qui réécrit la ligne une fois faite."
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: Math.max(9, Theme.textXs - 1)
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: root.todoFichiers.length === 0
            text: "Aucun fichier suivi."
            color: Qt.alpha(Theme.fg, 0.45)
            font.pixelSize: Theme.textXs
        }

        Repeater {
            model: root.todoFichiers

            Row {
                required property var modelData
                width: parent.width
                spacing: 8

                Text {
                    width: Math.round(parent.width * 0.28)
                    text: String(modelData.nom || "")
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width - Math.round(parent.width * 0.28) - 46
                    text: String(modelData.chemin || "")
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: Math.max(9, Theme.textXs - 1)
                    elide: Text.ElideMiddle
                }

                // Une croix dans un rond, comme les autres retraits du
                // panneau : un mot entier ne tenait pas dans la ligne et
                // se retrouvait coupé.
                Rectangle {
                    width: 22
                    height: 22
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: croixRetirer.containsMouse ? Theme.error
                                                      : Qt.alpha(Theme.fg, 0.08)
                    border.width: 1
                    border.color: Qt.alpha(Theme.error, 0.45)

                    Icon {
                        anchors.centerIn: parent
                        glyph: "close"
                        size: Math.round(Theme.iconSm * 0.78)
                        color: croixRetirer.containsMouse ? Theme.bg : Theme.error
                        opacityLevel: 1
                    }

                    MouseArea {
                        id: croixRetirer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runConfigCmd(["todo_del", String(modelData.nom || "")])
                    }
                }
            }
        }

        // Ajouter un fichier : le nom est libre, le chemin est étendu
        // par l'applet (`~` reste `~`, c'est elle qui l'interprète).
        // Bouton "Choisir" graphique pour sélectionner un fichier .md.
        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: 130
                height: 30
                radius: 6
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.2)

                TextInput {
                    id: nouveauTodoNom
                    anchors.fill: parent
                    anchors.margins: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                    selectByMouse: true
                    clip: true
                    onTextEdited: root.todoErreur = ""
                    onAccepted: nouveauTodoChemin.forceActiveFocus()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: nouveauTodoNom.text === ""
                        text: "nom (ex. perso)"
                        color: Qt.alpha(Theme.fg, 0.3)
                        font.pixelSize: Theme.textXs
                    }
                }
            }

            Rectangle {
                width: parent.width - 130 - 70 - 90 - 24
                height: 30
                radius: 6
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: 1
                border.color: root.todoErreur !== ""
                              ? Qt.alpha(Theme.error, 0.65) : Qt.alpha(Theme.fg, 0.2)

                TextInput {
                    id: nouveauTodoChemin
                    anchors.fill: parent
                    anchors.margins: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.textXs
                    selectByMouse: true
                    clip: true
                    onTextEdited: root.todoErreur = ""
                    onAccepted: root.ajouterTodo()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: nouveauTodoChemin.text === ""
                        text: "~/chemin/vers/todo.md"
                        color: Qt.alpha(Theme.fg, 0.3)
                        font.pixelSize: Theme.textXs
                    }
                }
            }

            // Bouton "Choisir" graphique (comme pour les fonds d'écran et captures)
            Rectangle {
                width: 70
                height: 30
                radius: 6
                color: todoPickMa.containsMouse ? Theme.accentMuted : Theme.surfaceVariant
                border.color: Theme.accentMuted
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 4

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "folder"
                        size: Math.round(Theme.iconSm * 0.78)
                        color: todoPickMa.containsMouse ? Theme.bg : Theme.accent
                        opacityLevel: 1
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Choisir"
                        color: todoPickMa.containsMouse ? Theme.bg : Theme.fg
                        font.pixelSize: Theme.textXs
                    }
                }

                MouseArea {
                    id: todoPickMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ouvrirSelecteurFichier("todo_md", "Choisir un fichier Markdown", nouveauTodoChemin.text, ["md", "markdown"])
                }
            }

            Rectangle {
                width: 90
                height: 30
                radius: 6
                color: survolTodoAjout.containsMouse
                       ? Qt.alpha(Theme.accent, 0.3) : Qt.alpha(Theme.accent, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "+ Ajouter"
                    color: Theme.accent
                    font.pixelSize: Theme.textXs
                    font.bold: true
                }

                MouseArea {
                    id: survolTodoAjout
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.ajouterTodo()
                }
            }
        }

        Text {
            width: parent.width
            visible: root.todoErreur !== ""
            text: root.todoErreur
            color: Theme.error
            font.pixelSize: Math.max(9, Theme.textXs - 1)
            wrapMode: Text.WordWrap
        }

        // Quel fichier l'applet montre : le widget, lui, les voit tous.
        Row {
            width: parent.width
            spacing: 6
            visible: root.todoFichiers.length > 0

            Text {
                width: 150
                text: "Affiché par l'applet"
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: Theme.textXs
            }

            Repeater {
                model: root.todoFichiers

                Rectangle {
                    required property var modelData
                    readonly property bool choisi: root.todoFocus === String(modelData.nom)
                    width: Math.max(56, labelChoisi.implicitWidth + 18)
                    height: 24
                    radius: 6
                    color: choisi ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.06)
                    border.width: 1
                    border.color: choisi ? Qt.alpha(Theme.accent, 0.5)
                                         : Qt.alpha(Theme.fg, 0.18)

                    Text {
                        id: labelChoisi
                        anchors.centerIn: parent
                        text: String(modelData.nom || "")
                        color: choisi ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: Math.max(9, Theme.textXs - 1)
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.runConfigCmd(["todo_focus", String(modelData.nom || "")])
                            root.todoFocus = String(modelData.nom || "")
                        }
                    }
                }
            }
        }

        // ── Surveillance des tâches par Hermes ──────────────────
        Row {
            width: parent.width
            spacing: 12

            Column {
                width: parent.width - 50
                spacing: 2

                Text {
                    width: parent.width
                    text: "Surveillance des tâches par Hermes"
                    color: root.todoSurveillance ? Theme.accent : Theme.fg
                    font.pixelSize: Theme.textSm
                    font.bold: true
                }

                Text {
                    width: parent.width
                    text: "Lorsque cette option est active, cocher une case confie l'exécution de la tâche à Hermes via la file d'attente. Désactivé : simple gestionnaire de cases Markdown locales."
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: Theme.textXs
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                width: 38
                height: 20
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                color: root.todoSurveillance ? Theme.accent : Qt.alpha(Theme.fg, 0.14)

                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    y: 2
                    x: root.todoSurveillance ? parent.width - width - 2 : 2
                    color: root.todoSurveillance ? Theme.bg : Qt.alpha(Theme.fg, 0.75)
                    Behavior on x { NumberAnimation { duration: 130 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runConfigCmd(["todo_surveillance"])
                }
            }
        }
    }
}

}
