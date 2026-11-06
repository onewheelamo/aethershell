//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// Point d'entrée attendu par `quickshell`.
//
// Le Loader DOIT rester à l'intérieur d'un ShellRoot : un Loader placé à la
// racine du fichier fait créer par Quickshell un ProxyFloatingWindow pour
// héberger les fenêtres chargées, et ce proxy devient une fenêtre blanche vide
// tuilée par le compositeur — une par instance. Mesuré : racine Loader = 1
// fenêtre blanche, ShellRoot + Loader = 0.
ShellRoot {
    Loader {
        source: "main.qml"
    }

    // L'historique des notifications est lu par deux FileView (tiroir et îlot
    // droit). Sur une installation neuve le fichier n'existe pas encore, et
    // chacun émet alors « Read of ... failed: File does not exist » à chaque
    // démarrage. Le créer vide une fois suffit : c'est un journal, pas un état.
    Process {
        running: true
        command: ["bash", "-c",
            "d=\"${XDG_CACHE_HOME:-$HOME/.cache}/quickshell\"; " +
            "mkdir -p \"$d\"; " +
            "[ -e \"$d/notifications-history.jsonl\" ] || : > \"$d/notifications-history.jsonl\""]
    }
}
