pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Moteur unifié du lanceur : index d'applications, alias (app_vars.json) et historique.
QtObject {
    id: root

    property var appIndex: []
    property var aliases: ({})
    property var history: []
    property bool watchActive: false

    property FileView appIndexFile: FileView {
        path: Quickshell.shellPath("core/app_index.json")
        watchChanges: root.watchActive
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.appIndex = Array.isArray(parsed) ? parsed : []
            } catch (e) { root.appIndex = [] }
        }
    }

    property FileView aliasFile: FileView {
        path: Quickshell.shellPath("core/app_vars.json")
        watchChanges: root.watchActive
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.aliases = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
            } catch (e) { root.aliases = ({}) }
        }
    }

    property FileView historyFile: FileView {
        path: Quickshell.shellPath("core/launch_history.json")
        watchChanges: root.watchActive
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.history = Array.isArray(parsed) ? parsed : []
            } catch (e) { root.history = [] }
        }
    }

    function reload() {
        appIndexFile.reload()
        aliasFile.reload()
        historyFile.reload()
    }

    function iconForCommand(cmd) {
        const bin = String(cmd || "").trim().split(/\s+/)[0] || ""
        const base = bin.substring(bin.lastIndexOf("/") + 1).toLowerCase()
        if (base === "") return ""
        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            const ex = String(app.exec || "").trim().split(/\s+/)[0] || ""
            const exBase = ex.substring(ex.lastIndexOf("/") + 1).toLowerCase()
            if (exBase === base) return app.icon || ""
        }
        return base
    }

    function recentEntries(limit) {
        if (!Theme.launchHistory || root.history.length === 0) return []
        const n = limit > 0 ? limit : root.history.length
        return root.history.slice(0, n).map(h => {
            const hasAlias = root.aliases && root.aliases[h.name] !== undefined
            const cmd = hasAlias ? String(root.aliases[h.name]) : String(h.exec || "")
            const ic = hasAlias ? root.iconForCommand(cmd) : (h.icon || root.iconForCommand(cmd))
            return { kind: "recent", name: h.name, exec: cmd, desc: cmd, icon: ic, tag: "récent" }
        })
    }

    function searchAppsAndAliases(query, limit) {
        const needle = String(query || "").trim().toLowerCase()
        const maxN = limit > 0 ? limit : 8
        const scored = []

        for (const name in root.aliases) {
            const cmd = String(root.aliases[name] || "").trim()
            if (cmd === "") continue
            const low = String(name).toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 95 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 70 - low.length
            else if (low.indexOf(needle) >= 0 || cmd.toLowerCase().indexOf(needle) >= 0) score = 50 - low.length
            if (score >= 0) {
                scored.push({
                    entry: { kind: "alias", name: name, exec: cmd, desc: "Alias · " + cmd, icon: root.iconForCommand(cmd), tag: "alias" },
                    score: score
                })
            }
        }

        const motsConfig = ["config", "configuration", "reglages", "réglages", "parametres", "paramètres", "aethershell"]
        let scoreConfig = -1
        for (let k = 0; k < motsConfig.length; ++k) {
            const mot = motsConfig[k]
            if (mot.indexOf(needle) === 0) scoreConfig = Math.max(scoreConfig, 96 - mot.length)
            else if (mot.indexOf(needle) >= 0) scoreConfig = Math.max(scoreConfig, 55 - mot.length)
        }
        if (scoreConfig >= 0) {
            scored.push({
                entry: { kind: "alias", name: "Config — Panneau de réglages", exec: "SUPER + SHIFT + H", desc: "SUPER + SHIFT + H", icon: "", tag: "alias", action: "open-config", glyph: "cog" },
                score: scoreConfig
            })
        }

        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            if (!app || !app.name) continue
            const low = String(app.name).toLowerCase()
            let score = -1
            if (low.indexOf(needle) === 0) score = 100 - low.length
            else if (low.indexOf(" " + needle) >= 0) score = 60 - low.length
            else if (low.indexOf(needle) >= 0) score = 40 - low.length
            else if (String(app.generic || "").toLowerCase().indexOf(needle) >= 0
                     || String(app.comment || "").toLowerCase().indexOf(needle) >= 0) score = 10
            if (score >= 0) {
                scored.push({
                    entry: { kind: "app", name: app.name, exec: app.exec, desc: app.comment || app.generic || "", generic: app.generic || "", icon: app.icon || "", tag: app.category || "" },
                    score: score
                })
            }
        }

        scored.sort((a, b) => b.score - a.score || String(a.entry.name).localeCompare(String(b.entry.name)))
        return scored.slice(0, maxN).map(x => x.entry)
    }

    function launch(entry) {
        if (!entry || !entry.exec) return
        const shell = entry.kind === "cmd"
            ? 'cd "$HOME" && ' + entry.exec
            : 'cd "$HOME" && exec ' + entry.exec
        SystemServices.launchInScope(shell)
        if (Theme.launchHistory && entry.name) {
            Quickshell.execDetached([
                "python3", Quickshell.shellPath("core/launch_history.py"),
                "add", String(entry.name), String(entry.exec), String(entry.icon || "")
            ])
        }
    }
}
