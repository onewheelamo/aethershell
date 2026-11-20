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

    function categoryGlyph(cat) {
        const c = String(cat || "").toLowerCase()
        if (c.indexOf("syst") >= 0 || c.indexOf("réglage") >= 0 || c.indexOf("reglage") >= 0) return "cog"
        if (c.indexOf("réseau") >= 0 || c.indexOf("reseau") >= 0) return "wifi"
        if (c.indexOf("jeu") >= 0) return "rocket"
        if (c.indexOf("média") >= 0 || c.indexOf("media") >= 0) return "music"
        if (c.indexOf("audio") >= 0) return "volume"
        if (c.indexOf("bureau") >= 0) return "file-document"
        if (c.indexOf("dév") >= 0 || c.indexOf("dev") >= 0) return "cog"
        if (c.indexOf("graph") >= 0) return "palette"
        if (c.indexOf("navig") >= 0) return "search"
        if (c.indexOf("util") >= 0) return "widgets"
        if (c.indexOf("récent") >= 0 || c.indexOf("recent") >= 0) return "history"
        return "folder"
    }

    function categoriesEntries() {
        const counts = ({})
        const order = []
        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            if (!app || !app.name) continue
            const cat = String(app.category || "").trim() || "Autres"
            if (counts[cat] === undefined) {
                counts[cat] = 0
                order.push(cat)
            }
            counts[cat] += 1
        }
        order.sort(function (a, b) {
            if (a === "Autres") return 1
            if (b === "Autres") return -1
            return counts[b] - counts[a] || a.localeCompare(b)
        })
        const out = []
        if (Theme.launchHistory && root.history.length > 0) {
            out.push({
                kind: "category",
                category: "__recent__",
                name: "Récents",
                desc: root.history.length + " lancements récents",
                icon: "",
                glyph: "history",
                tag: "dossier"
            })
        }
        for (let j = 0; j < order.length; ++j) {
            const cat = order[j]
            const n = counts[cat]
            out.push({
                kind: "category",
                category: cat,
                name: cat,
                desc: n + (n > 1 ? " applications" : " application"),
                icon: "",
                glyph: root.categoryGlyph(cat),
                tag: n + " apps"
            })
        }
        return out
    }

    function appsInCategory(catName, includeBack) {
        const out = []
        if (includeBack !== false) {
            out.push({
                kind: "category_back",
                name: "Retour aux catégories",
                desc: catName === "__recent__" ? "Récents" : String(catName || ""),
                icon: "",
                glyph: "chevron-left",
                tag: "retour"
            })
        }
        if (catName === "__recent__") {
            return out.concat(root.recentEntries(20))
        }
        const cible = String(catName || "").trim() || "Autres"
        const apps = []
        for (let i = 0; i < root.appIndex.length; ++i) {
            const app = root.appIndex[i]
            if (!app || !app.name) continue
            const cat = String(app.category || "").trim() || "Autres"
            if (cat !== cible) continue
            apps.push({
                kind: "app",
                name: app.name,
                exec: app.exec,
                desc: app.comment || app.generic || "",
                generic: app.generic || "",
                icon: app.icon || "",
                tag: app.category || ""
            })
        }
        apps.sort(function (a, b) { return String(a.name).localeCompare(String(b.name)) })
        return out.concat(apps)
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
                Quickshell.shellPath("core/as-core"), "launch-history",
                "add", String(entry.name), String(entry.exec), String(entry.icon || "")
            ])
        }
    }
}
