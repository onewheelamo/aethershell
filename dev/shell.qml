//@ pragma UseQApplication
import QtQuick
import Quickshell

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
}
