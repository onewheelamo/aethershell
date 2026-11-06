#!/usr/bin/env python3
"""Applique les choix de l'assistant de bienvenue, en une fois.

Lecture d'un JSON, soit dans le fichier donné en argument (ce que fait le
panneau : il écrit /run/user/<uid>/qs-first-run.json puis passe le chemin), soit
sur stdin pour un essai en ligne de commande :

    {"kb_layout": "fr",
     "dossiers": {"PICTURES": "/home/x/Images", ...},
     "programmes": {"Terminal": "alacritty", ...},
     "widgets_ajouter": ["horloge"], "widgets_retirer": ["musique"]}

L'ordre compte : le clavier d'abord (il réécrit `binds.lua`, dont la nomenclature
de workspaces dépend), puis les dossiers, puis les programmes, puis les widgets.
La marque de premier lancement n'est posée qu'à la fin : si une étape échoue, le
rapport le dit et l'assistant pourra être relancé.

Sortie : un rapport JSON sur stdout. Les messages des fonctions de
config_manager sont redirigés vers stderr pour ne pas polluer ce JSON.
"""
import contextlib
import json
import os
import subprocess
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE_DIR)
import config_manager as cm  # noqa: E402
import bar_applets as ba  # noqa: E402

# Où vont les applets une fois la barre principale choisie. Décision prise pour
# l'utilisateur, comme demandé : bureaux à gauche, horloge au centre, et l'état de
# la machine à droite dans l'ordre où on le lit.
PLACEMENT_BARRE = (
    ("debut", ["workspaces"]),
    ("milieu", ["horloge"]),
    ("fin", ["systray", "reseau", "volume", "luminosite", "alimentation"]),
)


def appliquer_dossier(cle, chemin):
    """Crée le dossier s'il manque, puis l'inscrit comme dossier XDG."""
    chemin = os.path.expanduser(str(chemin or "").strip())
    if not chemin.startswith("/") or chemin == "/":
        return False, "chemin invalide"
    os.makedirs(chemin, exist_ok=True)
    if not os.path.isdir(chemin):
        return False, "dossier non créé"
    # `xdg-user-dirs-update` attend le nom sans le suffixe _DIR : PICTURES donne
    # XDG_PICTURES_DIR (avec PICTURES_DIR, il écrit XDG_PICTURES_DIR_DIR).
    out = subprocess.run(["xdg-user-dirs-update", "--set", cle, chemin],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return False, (out.stderr or out.stdout).strip()[:120] or "échec xdg-user-dirs-update"
    return True, chemin


def appliquer_barre(barre, rapport):
    """Allume la barre choisie (et elle seule) puis y pose les applets.

    « haut » n'a pas de barre à allumer : c'est celle qui existe toujours. Les
    trois autres passent par style_vars.json, exactement comme le panneau.
    """
    for cle, actif in (("bar_bottom", barre == "bas"),
                       ("bar_left", barre == "cote-gauche"),
                       ("bar_right", barre == "cote-droite")):
        cm.update_style_var(cle, "true" if actif else "false")
    for zone, applets in PLACEMENT_BARRE:
        for n, applet in enumerate(applets):
            ile = f"{barre}:{zone}"
            ba.activer(applet, ile)
            ba.ordonner(applet, str((n + 1) * 10))
            rapport["applets"].append({"applet": applet, "ile": ile,
                                       "ordre": (n + 1) * 10})


def lire_choix():
    """Les choix, du fichier donné en argument ou de l'entrée standard."""
    if len(sys.argv) > 1:
        chemin = sys.argv[1]
        with open(chemin, encoding="utf-8") as fh:
            choix = json.load(fh)
        try:
            os.unlink(chemin)       # fichier de passage : il n'a plus d'utilité
        except OSError:
            pass
        return choix
    return json.load(sys.stdin)


def main():
    try:
        choix = lire_choix()
    except Exception as exc:
        print(json.dumps({"erreurs": [f"choix illisibles : {exc}"]}, ensure_ascii=False))
        return 1

    rapport = {"clavier": None, "dossiers": [], "programmes": [], "widgets": [],
               "applets": [], "barre": None, "erreurs": []}

    with contextlib.redirect_stdout(sys.stderr):
        layout = str(choix.get("kb_layout") or "").strip()
        if layout:
            try:
                # Pas de marque de premier lancement ici : elle vient à la fin.
                cm.set_kb_layout(layout, mark_first_run_done=False)
                rapport["clavier"] = layout
            except Exception as exc:
                rapport["erreurs"].append(f"clavier : {exc}")

        for cle, chemin in (choix.get("dossiers") or {}).items():
            try:
                ok, detail = appliquer_dossier(cle, chemin)
            except Exception as exc:
                ok, detail = False, str(exc)
            rapport["dossiers"].append({"xdg": cle, "chemin": detail, "ok": ok})
            if not ok:
                rapport["erreurs"].append(f"dossier {cle} : {detail}")

        for alias, commande in (choix.get("programmes") or {}).items():
            commande = str(commande or "").strip()
            if not commande:
                continue
            try:
                ok = cm.set_app_var(alias, commande)
            except Exception as exc:
                ok, commande = False, f"{commande} ({exc})"
            rapport["programmes"].append({"alias": alias, "commande": commande, "ok": bool(ok)})
            if not ok:
                rapport["erreurs"].append(f"programme {alias} : refusé")

        barre = str(choix.get("barre") or "").strip()
        if barre in ("haut", "bas", "cote-gauche", "cote-droite"):
            try:
                appliquer_barre(barre, rapport)
                rapport["barre"] = barre
            except Exception as exc:
                rapport["erreurs"].append(f"barre : {exc}")

        poses = {}
        for w in cm.load_widgets():
            poses.setdefault(str(w.get("type")), str(w.get("id")))
        for nature in choix.get("widgets_ajouter") or []:
            if nature in cm.WIDGET_TYPES and nature not in poses:
                try:
                    nouveau = cm.widget_add(nature, 1, 120, 160)
                    rapport["widgets"].append({"type": nature, "action": "ajouté", "id": nouveau})
                except Exception as exc:
                    rapport["erreurs"].append(f"widget {nature} : {exc}")
        for nature in choix.get("widgets_retirer") or []:
            if nature in poses:
                try:
                    cm.widget_remove(poses[nature])
                    rapport["widgets"].append({"type": nature, "action": "retiré"})
                except Exception as exc:
                    rapport["erreurs"].append(f"widget {nature} : {exc}")

        if not rapport["erreurs"]:
            cm.complete_first_run()

    print(json.dumps(rapport, ensure_ascii=False))
    return 0 if not rapport["erreurs"] else 3


if __name__ == "__main__":
    sys.exit(main())
