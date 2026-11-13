import QtQuick
import QtQuick.Layouts
import Quickshell
import "."

// ══════════════════════════════════════════════════════════════════════
// PANNEAU ÉTENDU DE L'ÎLOT DYNAMIQUE (IslandPanel.qml)
// ══════════════════════════════════════════════════════════════════════
// Contenu complet du mode « panneau » (680 × 420 px) :
// - En-tête permanent (date, média rapide, bouton réglages, fermer)
// - Rail vertical gauche à libellés horizontaux (5 onglets stricts)
// - Zone de contenu à droite chargeant l'onglet actif
// ══════════════════════════════════════════════════════════════════════

Item {
    id: root

    property var clockDate: new Date()
    property var activePlayer: null
    property var validPlayers: []
    property bool isPlaying: false
    property string mediaTitle: ""
    property bool isMediaActive: false

    readonly property var sysInfo: Theme.systemInfo || ({})
    readonly property var batInfo: sysInfo.battery || ({})
    readonly property bool isLaptop: Boolean(batInfo && batInfo.present)

    readonly property var tabsModel: [
        { idx: 0, glyph: "widgets", label: "Contrôles",        src: "IslandTabControles.qml" },
        { idx: 1, glyph: "music",   label: "Média & Son",      src: "IslandTabMedia.qml" },
        { idx: 2, glyph: "bell",    label: "Alertes & Tâches", src: "IslandTabAlertes.qml" },
        { idx: 3, glyph: "cog",     label: "Système & Réseau", src: "IslandTabSysteme.qml" },
        { idx: 4, glyph: "palette", label: "Apparence",        src: "IslandTabApparence.qml" }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── En-tête permanent du panneau (hauteur = Theme.barHeight) ─────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.barHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.padH + 4
                anchors.rightMargin: Theme.padH
                spacing: 12

                // Date + Heure
                Text {
                    text: Qt.formatDate(root.clockDate, "ddd d MMM") + "  ·  " + Qt.formatTime(root.clockDate, "HH:mm")
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textSm
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                // Séparateur + Média rapide si actif
                Rectangle {
                    visible: root.isMediaActive
                    width: 1
                    height: 14
                    color: Qt.alpha(Theme.fg, 0.2)
                }

                Text {
                    visible: root.isMediaActive
                    Layout.fillWidth: true
                    text: (root.isPlaying ? "▶ " : "⏸ ") + root.mediaTitle
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.textXs
                    color: Theme.accent
                    elide: Text.ElideRight

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.islandPanelTab = 1
                    }
                }

                Item {
                    visible: !root.isMediaActive
                    Layout.fillWidth: true
                }

                // Bouton réglages complets
                Rectangle {
                    visible: Theme.showConfigButton
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 8
                    color: cfgMa.containsMouse ? Qt.alpha(Theme.accent, 0.22) : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        glyph: "cog"
                        size: Theme.iconSm
                        color: cfgMa.containsMouse ? Theme.accent : Theme.fg
                    }

                    MouseArea {
                        id: cfgMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.islandPanelOpen = false
                            Theme.configPanelVisible = true
                        }
                    }
                }

                // Bouton Fermer
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    radius: 8
                    color: closeMa.containsMouse ? Qt.alpha(Theme.error, 0.25) : Qt.alpha(Theme.fg, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: closeMa.containsMouse ? Theme.error : Theme.fg
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.islandPanelOpen = false
                            Theme.islandNeedsKeyboard = false
                        }
                    }
                }
            }
        }

        // Ligne séparatrice sous l'en-tête
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.fg, 0.12)
        }

        // ── Corps : Rail vertical gauche (164 px) + Contenu onglet ──────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Rail vertical gauche
            Item {
                Layout.preferredWidth: 164
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Repeater {
                        model: root.tabsModel
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: Theme.islandPanelTab === modelData.idx

                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 10
                            color: active
                                ? Qt.alpha(Theme.accent, 0.20)
                                : (tabMa.containsMouse ? Qt.alpha(Theme.fg, 0.07) : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }

                            // Liseré vertical d'accent à gauche
                            Rectangle {
                                visible: parent.active
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 20
                                radius: 1.5
                                color: Theme.accent
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 10

                                Icon {
                                    glyph: parent.parent.modelData.glyph
                                    size: Theme.iconMd
                                    color: parent.parent.active ? Theme.accent : Qt.alpha(Theme.fg, 0.78)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: parent.parent.modelData.label
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.textSm
                                    font.weight: parent.parent.active ? Font.Bold : Font.Medium
                                    color: parent.parent.active ? Theme.fg : Qt.alpha(Theme.fg, 0.82)
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.islandNeedsKeyboard = false
                                    Theme.islandPanelTab = parent.modelData.idx
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.alpha(Theme.fg, 0.1)
                    }

                    // Pied de rail : infos rapides
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 3

                        Text {
                            visible: root.isLaptop
                            text: "Batterie : " + Math.round(Number((root.batInfo && root.batInfo.percent) || 0)) + " %"
                                  + ((root.batInfo && root.batInfo.charging) ? " ⚡" : "")
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: Qt.alpha(Theme.fg, 0.7)
                        }

                        Text {
                            text: "Alertes  : " + Theme.notifCount + (Theme.doNotDisturb ? " (N.P.D.)" : "")
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.textXs
                            color: Qt.alpha(Theme.fg, 0.7)
                        }
                    }
                }
            }

            // Séparateur vertical rail / contenu
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: Qt.alpha(Theme.fg, 0.12)
            }

            // Zone de contenu à droite
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Loader {
                    id: tabLoader
                    anchors.fill: parent
                    anchors.margins: 14
                    source: {
                        let idx = Math.max(0, Math.min(root.tabsModel.length - 1, Theme.islandPanelTab))
                        return root.tabsModel[idx].src
                    }
                    onLoaded: {
                        if (!item) return
                        if (Theme.islandPanelTab === 1) {
                            item.activePlayer = Qt.binding(() => root.activePlayer)
                            item.validPlayers = Qt.binding(() => root.validPlayers)
                        }
                    }
                }
            }
        }
    }
}
