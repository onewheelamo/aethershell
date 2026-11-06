#!/bin/sh
# Ouvre la cible d'une notification — fenêtre déjà ouverte d'abord.
#
# Usage : notif_open.sh <libellé> [--focus <motif>]... -- <commande> [args...]
#
# Un clic sur le titre d'une notification qui demande une autorisation ne doit
# pas lancer une seconde instance : l'application tourne déjà, elle attend. On
# cherche donc sa fenêtre (classe Wayland d'abord, titre ensuite) et on la met au
# focus — ce qui bascule aussi sur son workspace. Si aucune fenêtre ne
# correspond, on lance la commande ; et si elle échoue, la sortie d'erreur est
# remontée en notification critique au lieu d'être perdue — le même piège que
# « la capture vidéo ne marche pas », où rien ne disait pourquoi.
label="$1"
[ $# -gt 0 ] && shift

motifs=""
while [ $# -gt 0 ]; do
    case "$1" in
        --focus)
            [ $# -ge 2 ] && motifs="$motifs
$2"
            shift 2
            ;;
        --) shift; break ;;
        *) break ;;
    esac
done

# 1. une fenêtre déjà ouverte porte-t-elle un des motifs ?
if [ -n "$motifs" ] && command -v hyprctl >/dev/null 2>&1; then
    adresse=$(printf '%s' "$motifs" | python3 -c '
import json, subprocess, sys

motifs = [m.strip().lower() for m in sys.stdin.read().split("\n") if m.strip()]
if not motifs:
    sys.exit(0)
try:
    clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"],
                                        capture_output=True, text=True, timeout=3).stdout)
except Exception:
    sys.exit(0)

# Deux passes : la classe d abord (fiable), le titre ensuite — un titre contient
# n importe quoi, y compris le nom de l application cherchee.
for passe in ("classe", "titre"):
    for c in clients:
        if passe == "classe":
            champs = [c.get("class", ""), c.get("initialClass", "")]
        elif len(motifs):
            champs = [c.get("title", "")]
        for champ in champs:
            v = str(champ).lower()
            for m in motifs:
                if passe == "classe":
                    if v == m or m in v:
                        print(c.get("address", "")); sys.exit(0)
                elif len(m) >= 4 and m in v:
                    print(c.get("address", "")); sys.exit(0)
sys.exit(0)')
    if [ -n "$adresse" ]; then
        # Hyprland 0.57 (config Lua) : `hyprctl dispatch focuswindow address:…`
        # est réévalué comme du Lua et échoue au parsing (« ')' expected near
        # 'address' »), donc le script retombait sur le lancement — et VS Code
        # ouvrait une seconde fenêtre sur le workspace courant. Le dispatcher
        # s'appelle par `repl`, et il bascule bien de workspace (mesuré : 2 → 3).
        if hyprctl repl "hl.dispatch(hl.dsp.focus({ window = \"address:$adresse\" }))" \
                >/dev/null 2>&1; then
            exit 0
        fi
        if hyprctl dispatch focuswindow "address:$adresse" >/dev/null 2>&1; then
            exit 0
        fi
    fi
fi

# 2. sinon, lancer la cible
[ $# -eq 0 ] && exit 0            # cible « focus » sans repli : rien à lancer

# Lancer en tâche de fond et n'observer que les deux premières secondes : un échec
# immédiat (binaire absent, permission) se voit, alors qu'une application qui vit
# sa vie ne retient pas le script. Avant, la substitution de commande attendait sa
# fermeture : un gestionnaire de fichiers restait donc accroché, et la
# notification d'erreur n'arrivait qu'à la fin de la session. Le sous-shell écrit
# son code de sortie dans un fichier ; tant que ce fichier est vide, l'application
# tourne encore.
journal=$(mktemp)
statut=$(mktemp)
# `</dev/null >/dev/null 2>&1` ferme aussi les descripteurs hérités du script :
# sans ça, l'appelant qui lit notre sortie standard attendrait la fermeture de
# l'application, et le script semblerait bloquant alors qu'il a rendu la main.
( "$@" >/dev/null 2>"$journal" ; echo $? > "$statut" ) </dev/null >/dev/null 2>&1 &
sleep 2
status=0
if [ -s "$statut" ]; then
    status=$(cat "$statut")
fi
if [ "$status" -ne 0 ]; then
    detail=$(head -n 3 "$journal" | tr '\n' ' ')
    [ -n "$detail" ] || detail="code $status"
    notify-send -a "quickshell" -u critical "Impossible d'ouvrir : $label" "$detail"
fi
rm -f "$journal" "$statut"
exit "$status"
